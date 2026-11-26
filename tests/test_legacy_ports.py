"""Compatibilidad de importación única; Omnia no detecta ni lanza RecompLauncher."""
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from omnia.games.legacy_recomp import migrate_installed_ports, repair_launch_args, start_args
from omnia.store import Store


class LegacyPortMigration(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.source = self.tmp / "legacy-data"
        (self.source / "cache").mkdir(parents=True)
        self.port = self.tmp / "ports" / "longshot"
        self.port.mkdir(parents=True)
        self.apprun = self.port / "AppRun"
        self.apprun.write_text("#!/bin/sh\nexit 0\n")
        self.apprun.chmod(0o755)
        self.store = Store(self.tmp / "omnia")

    def write_manifest(self, entries, apps=()):
        (self.source / "library.json").write_text(json.dumps({"installed": entries}))
        (self.source / "cache/pc-catalog.json").write_text(json.dumps({"apps": list(apps)}))

    def test_imports_local_entry_and_history_once(self):
        self.write_manifest(
            {"longshot": {"id": "longshot", "name": "Longshot", "path": str(self.port),
                           "last_played": 1700000000, "played_secs": 3600}},
            [{"id": "longshot", "origin": "switch2", "tags": ["Port"]}],
        )
        self.assertEqual(migrate_installed_ports(self.store, [self.source]), 1)
        (game,) = self.store.games()
        self.assertEqual((game["id"], game["name"], game["variant"], game["platform"]),
                         ("recomp-longshot", "The Legend of Zelda: Ocarina of Time", "Longshot", "sw2"))
        self.assertEqual(game["ports"][0]["launch"], [str(self.apprun.resolve())])
        self.assertEqual(game["played"], {"last": 1700000000, "secs": 3600})
        self.assertTrue(self.apprun.exists())
        self.assertEqual(migrate_installed_ports(self.store, [self.source]), 0)

    def test_rejects_executable_outside_port_folder(self):
        outside = self.tmp / "outside"
        outside.write_text("#!/bin/sh\n")
        outside.chmod(0o755)
        self.write_manifest({"unsafe": {"id": "unsafe", "path": str(self.port), "exe": str(outside)}})
        self.assertEqual(migrate_installed_ports(self.store, [self.source]), 0)
        self.assertEqual(self.store.games(), [])

    def test_clean_install_records_migration_without_repeated_lookup(self):
        empty = self.tmp / "no-legacy-data"
        empty.mkdir()
        self.assertEqual(migrate_installed_ports(self.store, [empty]), 0)
        self.assertEqual(migrate_installed_ports(self.store, [self.source]), 0)
        self.assertEqual(self.store.games(), [])


if __name__ == "__main__":
    unittest.main()


class DescriptorStartArgs(LegacyPortMigration):
    def descriptor(self, args):
        (self.port / "recomplauncher.json").write_text(json.dumps({"start": {"program": ["x.AppImage"], "args": args}}))

    def test_start_args_expand_install_and_reject_other_placeholders(self):
        self.descriptor(["--play", "{install}/Longshot"])
        self.assertEqual(start_args(self.port), ["--play", f"{self.port}/Longshot"])
        self.descriptor(["--prepare", "{game}"])
        self.assertEqual(start_args(self.port), [])

    def test_migration_and_repair_add_args_once(self):
        self.descriptor(["--play", "{install}/Longshot"])
        self.write_manifest({"longshot": {"id": "longshot", "name": "Longshot", "path": str(self.port)}})
        migrate_installed_ports(self.store, [self.source])
        expected = [str(self.apprun.resolve()), "--play", f"{self.port.resolve()}/Longshot"]
        self.assertEqual(self.store.games()[0]["ports"][0]["launch"], expected)
        self.assertEqual(repair_launch_args(self.store), 0)

    def test_repair_fixes_bare_apprun(self):
        self.descriptor(["--game"])
        self.store.set_games([{"id": "g", "name": "G", "ports": [{"id": "g-main", "launch": [str(self.apprun)]}]}])
        self.assertEqual(repair_launch_args(self.store), 1)
        self.assertEqual(self.store.games()[0]["ports"][0]["launch"], [str(self.apprun), "--game"])
        self.assertEqual(repair_launch_args(self.store), 0)
