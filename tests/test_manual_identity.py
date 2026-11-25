import json
import struct
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from omnia.api import Api, ApiError
from omnia.service import sync_unlinked_art
from omnia.store import Store


def version_entry(key, value=b"", kind=0, children=()):
    prefix = bytearray(struct.pack("<HHH", 0, len(value) // 2 if kind else len(value), kind))
    prefix += (key + "\0").encode("utf-16-le")
    prefix += b"\0" * (-len(prefix) % 4) + value
    for child in children:
        prefix += b"\0" * (-len(prefix) % 4) + child
    struct.pack_into("<H", prefix, 0, len(prefix))
    return prefix


def write_pe(path, product=""):
    resource = bytearray(1024)
    version = version_entry("VS_VERSION_INFO", children=[
        version_entry("StringFileInfo", children=[
            version_entry("040904b0", children=[
                version_entry("ProductName", (product + "\0").encode("utf-16-le"), 1),
            ]),
        ]),
    ])
    for at, key, offset in ((0, 16, 0x80000020), (32, 1, 0x80000040), (64, 1033, 96)):
        struct.pack_into("<HHII", resource, at + 12, 0, 1, key, offset)
    struct.pack_into("<II", resource, 96, 0x1080, len(version))
    resource[128:128 + len(version)] = version
    image = bytearray(512)
    image[:2] = b"MZ"
    struct.pack_into("<I", image, 60, 128)
    image[128:132] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", image, 132, 0x8664, 1, 0, 0, 0, 240, 2)
    struct.pack_into("<H", image, 152, 0x20B)
    struct.pack_into("<II", image, 152 + 112 + 16, 0x1000, len(resource))
    struct.pack_into("<III", image, 392 + 12, 0x1000, len(resource), len(image))
    path.write_bytes(image + resource)


class ManualIdentityTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.store = Store(self.root / "config")
        self.api = Api(self.store, "token", fs_roots=[self.root], scan_fn=lambda: [])
        self.addCleanup(self.api.package_installs.shutdown)
        self.addCleanup(self.api.httpd.server_close)

    def test_reads_pe_title_without_running_it_and_rejects_dll_and_bad_files(self):
        path = self.root / "binary.exe"
        write_pe(path, "Juego de prueba ™")
        self.assertEqual(self.api.game_suggest({"path": str(path)})["name"], "Juego de prueba ™")
        file = bytearray(path.read_bytes())
        struct.pack_into("<H", file, 150, 0x2002)
        path.write_bytes(file)
        with self.assertRaisesRegex(ApiError, "Windows válido"):
            self.api.game_suggest({"path": str(path)})
        path.write_bytes(b"random text")
        with self.assertRaisesRegex(ApiError, "Windows válido"):
            self.api.game_suggest({"path": str(path)})

    def test_uses_native_desktop_name_only_for_matching_executable(self):
        path = self.root / "binary"
        path.write_bytes(b"#!/bin/sh\nexit 1\n")
        path.chmod(0o755)
        desktop = self.root / "binary.desktop"
        desktop.write_text("[Desktop Entry]\nType=Application\nName=Native Adventure\nExec=other\n")
        self.assertEqual(self.api.game_suggest({"path": str(path)})["name"], "binary")
        desktop.write_text("[Desktop Entry]\nType=Application\nName=Native Adventure\nExec=binary %U\n")
        self.assertEqual(self.api.game_suggest({"path": str(path)})["name"], "Native Adventure")
        body = {"name": "Native Adventure", "kind": "native", "exe": str(path), "inspectExecutable": True}
        added = self.api.game_add({"_body": body})
        self.assertEqual(self.api.game_add({"_body": body})["id"], added["id"])
        self.assertEqual(len(self.store.games()), 1)

    def test_stores_verified_gog_identity_and_explicit_catalog_choice(self):
        path = self.root / "binary.exe"
        write_pe(path, "Original")
        (self.root / "goggame-123.info").write_text(json.dumps({
            "name": "Edición GOG", "playTasks": [{"isPrimary": True, "path": "binary.exe"}],
        }))
        with patch("omnia.manual.shutil.which", return_value="umu-run"), patch(
                "omnia.online_catalog.game_detail", return_value={"data": {"slug": "original"}}):
            result = self.api.game_add({"_body": {"name": "Mi nombre", "kind": "windows", "exe": str(path),
                                                  "inspectExecutable": True, "catalogSlug": "original",
                                                  "identity": {"store": "steam", "id": "999"}}})
        game = self.store.find_game(result["id"])
        self.assertEqual(game["name"], "Mi nombre")
        self.assertEqual(game["detectedIdentity"], {"store": "gog", "id": "123"})
        self.assertEqual(game["art"]["sgdb"], "Edición GOG")
        self.assertEqual(game["catalogSlug"], "original")
        self.assertNotIn("store_id", game)
        self.assertTrue(self.api.library({})["games"][0]["canUninstall"])
        with self.assertRaisesRegex(ApiError, "seguridad"):
            self.api.installation_removal_preview({"id": game["id"]})

    def test_resolves_existing_steam_installation_from_its_path_without_adding_a_duplicate(self):
        path = self.root / "binary"
        path.write_bytes(b"#!/bin/sh\n")
        path.chmod(0o755)
        self.store.set_games([{"id": "steam-42", "name": "Steam Edition", "auto": "steam",
                               "ports": [{"folder": str(self.root)}]}])
        suggestion = self.api.game_suggest({"path": str(path)})
        self.assertEqual(suggestion["identity"], {"store": "steam", "id": "42"})
        self.assertEqual(self.api.game_add({"_body": {"exe": str(path), "inspectExecutable": True}})["id"], "steam-42")
        self.assertEqual(len(self.store.games()), 1)

    def test_steam_sidecar_must_match_owned_title_and_passes_appid_to_art_lookup(self):
        path = self.root / "binary.exe"
        write_pe(path, "Game: Anniversary")
        (self.root / "steam_appid.txt").write_text("42\n")
        games = [{"id": "42", "title": "Different Edition"}]
        self.api._store_map = {"steam": SimpleNamespace(library=lambda: games)}
        self.assertNotIn("identity", self.api.game_suggest({"path": str(path)}))
        games[0]["title"] = "Game Anniversary"
        with patch("omnia.manual.shutil.which", return_value="umu-run"):
            result = self.api.game_add({"_body": {"name": "My game", "kind": "windows", "exe": str(path),
                                                  "inspectExecutable": True}})
        game = self.store.find_game(result["id"])
        self.assertEqual(game["detectedIdentity"], {"store": "steam", "id": "42"})
        with patch("omnia.online_catalog.lookup_pc_artwork", return_value={}) as lookup:
            sync_unlinked_art(self.store, game, {})
        lookup.assert_called_once_with("Game Anniversary", None, "42")
