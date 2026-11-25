import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from omnia.api import Api, ApiError
from omnia.games.heroic import HeroicDetector
from omnia.games.steam import SteamDetector
from omnia.store import Store


class GameRemovalTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.home = self.root / "home"
        self.home.mkdir()
        self.commands = []
        self.store = Store(self.root / "config")
        self.detectors = [SteamDetector(self.home), HeroicDetector(self.home)]
        self.api = Api(self.store, "token", fs_roots=[self.home], scan_fn=lambda: self.commands,
                       detectors=self.detectors)
        self.addCleanup(self.api.package_installs.shutdown)
        self.addCleanup(self.api.httpd.server_close)

    def write(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def steam(self, flags=4):
        library = self.home / ".local/share/Steam/steamapps"
        exe = self.write(library / "common/Game/binary", "executable")
        registry = self.write(library / "appmanifest_42.acf",
                              f'"AppState" {{ "appid" "42" "name" "Game" "installdir" "Game" "StateFlags" "{flags}" }}')
        self.api.refresh({})
        return registry, exe

    def remove(self, gid, expected=None):
        return self.api.installation_remove({"_body": {"gameId": gid, "expectedPath": expected}})

    def test_removes_steam_files_and_manifest_only_and_leaves_proton_data(self):
        registry, exe = self.steam()
        save = self.write(registry.parent / "compatdata/42/pfx/save", "save")
        other = self.write(self.home / "another-game", "unrelated game with a shared working directory")
        self.store.set_games(self.store.games() + [{"id": "manual-other", "ports": [
            {"cwd": str(self.home), "check": str(other)}]}])
        preview = self.api.installation_removal_preview({"id": "steam-42"})
        self.assertEqual(preview, {"path": str(exe.parent), "client": "steam"})
        self.commands = ["/usr/bin/steam -silent"]
        with self.assertRaisesRegex(ApiError, "Cierra Steam"):
            self.remove("steam-42", preview["path"])
        self.commands = []
        with self.assertRaisesRegex(ApiError, "cambió"):
            self.remove("steam-42", str(exe.parent / "other"))
        self.assertTrue(exe.exists())
        self.assertEqual(self.remove("steam-42", preview["path"])["product"], "42")
        self.assertFalse(exe.parent.exists())
        self.assertFalse(registry.exists())
        self.assertTrue(save.exists())
        self.assertEqual(self.api.refresh({})["total"], 1)
        self.assertTrue(other.exists())

    def test_blocks_steam_update_and_another_app_with_same_directory(self):
        registry, exe = self.steam(4 | 1024)
        with self.assertRaisesRegex(ApiError, "actualización"):
            self.remove("steam-42")
        registry.write_text(registry.read_text().replace("1028", "4"))
        self.write(registry.with_name("appmanifest_99.acf"),
                   '"AppState" { "appid" "99" "name" "Other" "installdir" "Game" "StateFlags" "4" }')
        with self.assertRaisesRegex(ApiError, "comparte"):
            self.remove("steam-42")
        self.assertTrue(exe.exists())

    def test_heroic_registry_and_other_game_remain_consistent(self):
        exe = self.write(self.home / "Games/GOG One/main.exe", "executable")
        other = self.write(self.home / "Games/GOG Two/main.exe", "other")
        rows = [{"appName": "123", "install_path": str(exe.parent)}, {"appName": "456", "install_path": str(other.parent)}]
        registry = self.write(self.home / ".config/heroic/gog_store/installed.json", json.dumps({"installed": rows}))
        self.api.refresh({})
        with patch("omnia.removal.write_json_atomic", side_effect=OSError):
            with self.assertRaisesRegex(ApiError, "retirar todos"):
                self.remove("heroic-gog-123")
        self.assertTrue(exe.exists())
        self.assertEqual(json.loads(registry.read_text())["installed"], rows)
        result = self.remove("heroic-gog-123")
        self.assertEqual((result["store"], result["product"]), ("gog", "123"))
        self.assertFalse(exe.exists())
        self.assertEqual(json.loads(registry.read_text())["installed"], rows[1:])
        self.assertTrue(other.exists())

    def test_uses_own_store_registry_for_epic_and_amazon(self):
        for sid, relative, key in (("epic", "installed.json", "app_name"), ("amazon", "nile/installed.json", "id")):
            with self.subTest(store=sid):
                exe = self.write(self.home / f"Games/{sid}/Game/bin/main.exe", "executable")
                folder = exe.parent.parent
                cfg = self.root / sid
                rows = [{key: "Product", "path": str(folder)}]
                registry = self.write(cfg / relative, json.dumps(rows))
                self.api._store_map = {sid: SimpleNamespace(dir=cfg)}
                gid = "manual-" + sid
                game = {"id": gid, "store_id": {"store": sid, "id": "Product"},
                        "ports": [{"check": str(exe)}]}
                self.store.set_games([game])
                self.assertEqual(self.remove(gid)["product"], "Product")
                self.assertEqual(json.loads(registry.read_text()), [])
                self.assertFalse(folder.exists())

    def test_only_removes_gog_with_the_exact_primary_executable(self):
        exe = self.write(self.home / "Games/GOG/bin/game.exe", "executable")
        marker = exe.parent.parent / "goggame-123.info"
        gid = "manual-gog"
        self.store.set_games([{"id": gid, "detectedIdentity": {"store": "gog", "id": "123"},
                              "ports": [{"check": str(exe)}]}])
        self.write(marker, json.dumps({"playTasks": [{"isPrimary": True, "path": "bin/launcher.exe"}]}))
        with self.assertRaisesRegex(ApiError, "verificar qué archivos"):
            self.remove(gid)
        self.assertTrue(exe.exists())
        self.write(marker, json.dumps({"playTasks": [{"isPrimary": True, "path": "bin/game.exe"}]}))
        self.assertEqual(self.remove(gid)["product"], "123")
        self.assertFalse(exe.exists())

    def test_unlink_manual_does_not_delete_files_and_symlink_is_rejected(self):
        exe = self.write(self.home / "Games/native", "manual game")
        self.store.set_games([{"id": "manual-native", "ports": [{"check": str(exe)}]}])
        with self.assertRaisesRegex(ApiError, "verificar qué archivos"):
            self.remove("manual-native")
        self.api.game_remove({"id": "manual-native"})
        self.assertTrue(exe.exists())
        registry, steam_exe = self.steam()
        real = steam_exe.parent.with_name("Other")
        steam_exe.parent.rename(real)
        steam_exe.parent.symlink_to(real, target_is_directory=True)
        with self.assertRaisesRegex(ApiError, "seguridad"):
            self.remove("steam-42")
        self.assertTrue(registry.exists())
        self.assertTrue((real / steam_exe.name).exists())
