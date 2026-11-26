import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import descriptor, security
from omnia.api import Api
from omnia.store import Store

DESCRIPTOR = {
    "format": 1, "name": "Port",
    "inputs": [{"id": "game", "role": "game", "check": {"nup_build_id": "e0f3ccfa"}}],
    "saves": ["{local}/port", "{install}/Game/user", "{install}/profile.txt", "{install}/slots/*.sav", "{input:game}/x", "{home}", "{local}/../x"],
    "folders": {"saves": [{"path": "{install}/Game/user", "if": "{install}/Game/user"}, {"path": "{local}/port"}], "game": [{"path": "{install}/Game"}]},
    "actions": [{"id": "saves", "label": "Partidas", "open": "saves"}, {"id": "ghost", "label": "X", "open": "missing"}],
    "system": {"linux": {"glibc": "2.35", "graphics": {"vulkan": "1.3"}}},
    "exit_codes": {"3": "No encuentra tu copia", "1": "ok"},
}


class DescriptorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = self.tmp / "home"
        (self.home / ".local/share").mkdir(parents=True)
        self.root = self.tmp / "ports/port"
        (self.root / "Game").mkdir(parents=True)
        (self.root / "descriptor-tmp").mkdir()
        (self.root / "recomplauncher.json").write_text(json.dumps(DESCRIPTOR))
        env = mock.patch.dict(os.environ, {"HOME": str(self.home), "XDG_DATA_HOME": str(self.home / ".local/share"),
                                           "XDG_CONFIG_HOME": str(self.home / ".config")})
        env.start()
        self.addCleanup(env.stop)

    def test_load_rejects_bad_files(self):
        self.assertEqual(descriptor.load(self.tmp / "nada"), {})
        (self.root / "recomplauncher.json").write_text("[1, 2]")
        self.assertEqual(descriptor.load(self.root), {})
        (self.root / "recomplauncher.json").write_text("{")
        self.assertEqual(descriptor.load(self.root), {})

    def test_expand_resolves_known_placeholders_and_rejects_the_rest(self):
        expand = lambda t: descriptor.expand(t, self.root)
        self.assertEqual(expand("{install}/Game/user"), str(self.root / "Game/user"))
        self.assertEqual(expand("{local}/port"), str(self.home / ".local/share/port"))
        self.assertEqual(expand("{data}/saves"), str(self.root / "recompdata/saves"))
        for bad in ("{input:game}/x", "{pad}/x", "{nope}/x", "{home}", "{local}", "{local}/../x", "relativo/x", "", None, "{install}/a\0b"):
            self.assertIsNone(expand(bad), bad)

    def test_saves_spec_splits_files_and_folders_and_skips_unsafe_paths(self):
        (self.root / "profile.txt").write_text("1")
        spec = descriptor.saves_spec(self.root)
        self.assertEqual(spec["files"], [str(self.root / "profile.txt"), str(self.root / "slots/*.sav")])
        self.assertEqual(spec["dirs"], [str(self.home / ".local/share/port"), str(self.root / "Game/user")])

    def test_folders_pick_the_first_existing_candidate(self):
        self.assertEqual(descriptor.folders(self.root)["saves"], str(self.home / ".local/share/port"))
        (self.root / "Game/user").mkdir()
        self.assertEqual(descriptor.folders(self.root)["saves"], str(self.root / "Game/user"))
        self.assertEqual(descriptor.folders(self.root)["game"], str(self.root / "Game"))

    def test_actions_only_for_existing_named_folders(self):
        (self.home / ".local/share/port").mkdir()
        self.assertEqual([a["id"] for a in descriptor.actions(self.root)], ["saves"])

    def test_build_id_compatibility(self):
        data = DESCRIPTOR
        self.assertEqual(descriptor.build_id_prefixes(data), ["e0f3ccfa"])
        self.assertEqual(descriptor.compatibility(data, "E0F3CCFAF50065AE")["state"], "ok")
        self.assertEqual(descriptor.compatibility(data, "277178b7dba1")["state"], "mismatch")
        self.assertEqual(descriptor.compatibility(data, "")["state"], "unknown")
        self.assertEqual(descriptor.compatibility({}, "abcd1234")["state"], "unknown")
        self.assertEqual(descriptor.build_id_prefixes({"inputs": [{"check": {"nup_build_id": "zz"}}]}), [])

    def test_requirements_and_exit_codes(self):
        self.assertEqual([(r["key"], r["ok"]) for r in descriptor.requirements(DESCRIPTOR, glibc="2.40")], [("glibc", True), ("vulkan", None)])
        self.assertFalse(descriptor.requirements(DESCRIPTOR, glibc="2.31")[0]["ok"])
        self.assertEqual(descriptor.requirements({}), [])
        self.assertEqual(descriptor.exit_message(DESCRIPTOR, 3), "No encuentra tu copia")
        self.assertEqual(descriptor.exit_message(DESCRIPTOR, 9), "")


class DescriptorApiTests(DescriptorTests):
    def setUp(self):
        super().setUp()
        self.store = Store(self.tmp / "cfg")
        self.api = Api(self.store, security.new_token(self.tmp / "run"), [], scan_fn=list, fs_roots=[self.tmp],
                       backup_root=str(self.tmp / "backups"))
        self.api.serve()
        self.addCleanup(self.api.stop)
        self.exe = self.root / "AppRun"
        self.exe.write_text("#!/bin/sh\n")
        self.exe.chmod(0o755)
        self.game = {"id": "g1", "name": "Port Game", "platform": "sw2", "catalogSlug": "port-game",
                     "ports": [{"id": "p1", "name": "Port", "launch": [str(self.exe)], "check": str(self.exe), "cwd": str(self.root)}]}
        self.store.set_games([self.game])

    def test_library_exposes_backup_folders_and_requirements(self):
        (self.root / "Game/user").mkdir()
        entry = self.api.library({})["games"][0]
        self.assertTrue(entry["ports"][0]["canBackup"])
        self.assertEqual({a["id"] for a in entry["folderActions"]}, {"saves"})
        self.assertEqual([r["key"] for r in entry["requirements"]], ["glibc", "vulkan"])

    def test_descriptor_saves_feed_the_backup_config(self):
        (self.root / "Game/user").mkdir()
        (self.root / "Game/user/slot0").write_text("x")
        info = self.api.saves_info({"id": "g1", "port": "p1"})
        self.assertTrue(info["configured"])
        self.assertEqual(info["folder"], str(self.root / "Game/user"))

    def test_user_choice_beats_the_descriptor(self):
        self.store.state["saves"] = {"g1": {"spec": {"dirs": [str(self.tmp / "mias")]}}}
        (self.tmp / "mias").mkdir()
        self.assertEqual(self.api.saves_info({"id": "g1", "port": "p1"})["spec"], {"dirs": [str(self.tmp / "mias")]})

    def test_folder_open_only_for_named_existing_folders(self):
        opened = []
        self.api.open_fn = opened.append
        (self.root / "Game/user").mkdir()
        self.assertEqual(self.api.folder_open({"_body": {"gameId": "g1", "folder": "saves"}}), {"ok": True})
        self.assertEqual(opened, [str(self.root / "Game/user")])
        from omnia.api import ApiError
        for body in ({"gameId": "g1", "folder": "../etc"}, {"gameId": "g1", "folder": "nope"}, {"gameId": "zz", "folder": "saves"}):
            with self.assertRaises(ApiError):
                self.api.folder_open({"_body": body})

    def test_dump_copy_reports_compatibility_with_the_port(self):
        dump = self.tmp / "volcado"
        dump.mkdir()
        rom = {"id": "rom-1", "name": "ROM", "platform": "sw2", "catalogSlug": "port-game", "auto": "roms",
               "ports": [{"id": "rom-1-main", "name": "x", "launch": [], "check": str(dump),
                          "rom": {"path": str(dump), "system": "switch", "buildId": "e0f3ccfaf50065ae"}}]}
        self.store.set_games([self.game, rom])
        self.store.state["catalog_platforms"] = {"port-game": ["switch2"]}
        copy = self.api.library({})["games"][0]["romCopy"]
        self.assertEqual(copy["compat"]["state"], "ok")
        rom["ports"][0]["rom"]["buildId"] = "277178b7dba1"
        self.store.set_games([self.game, rom])
        self.assertEqual(self.api.library({})["games"][0]["romCopy"]["compat"]["state"], "mismatch")


if __name__ == "__main__":
    unittest.main()


class ExitWatchTests(DescriptorApiTests):
    class Proc:
        def __init__(self, code):
            self.code = code

        def wait(self):
            return self.code

    def run_watch(self, code):
        entry = self.store.find_game("g1")
        self.api._watch_exit(entry, entry["ports"][0], self.Proc(code))
        import threading, time
        deadline = time.time() + 3
        while time.time() < deadline and any(t.name == "omnia-exit-watch" and t.is_alive() for t in threading.enumerate()):
            time.sleep(0.02)

    def test_declared_exit_code_is_reported_in_the_library(self):
        self.run_watch(3)
        self.assertEqual(self.api.library({})["games"][0]["lastExit"]["message"], "No encuentra tu copia")

    def test_ok_zero_and_unknown_codes_are_not_warnings(self):
        for code in (0, 1, 9):
            self.run_watch(code)
        self.assertIsNone(self.api.library({})["games"][0]["lastExit"])
