import shutil
import tempfile
import unittest
from pathlib import Path

from omnia import security
from omnia.api import Api
from omnia.store import Store


class NupCopyMergeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.nup = self.tmp / "Zelda [0400486024dec000].nup"
        self.nup.write_bytes(b"\x00" * 64)
        self.rom = self.tmp / "Juego.z64"
        self.rom.write_bytes(b"\x00" * 64)
        self.store = Store(self.tmp / "cfg")
        self.api = Api(self.store, security.new_token(self.tmp / "run"), [], scan_fn=list, fs_roots=[self.tmp])
        self.api.serve()
        self.addCleanup(self.api.stop)

    def games(self, *extra):
        port_dir = self.tmp / "port"
        port_dir.mkdir(exist_ok=True)
        port_game = {"id": "recomp-longshot", "name": "Zelda: Ocarina of Time", "platform": "sw2", "catalogSlug": "zelda-sw2",
                     "ports": [{"id": "p", "name": "Longshot", "launch": ["x"], "check": str(port_dir)}]}
        self.store.set_games([port_game, *extra])
        self.store.state["catalog_platforms"] = {"zelda-sw2": ["switch2"]}
        return self.api.library({})["games"]

    def rom_game(self, path, gid, slug="zelda-sw2", platform="sw2"):
        return {"id": gid, "name": "Zelda ROM", "platform": platform, "catalogSlug": slug, "auto": "roms",
                "ports": [{"id": gid + "-main", "name": "Emulador por elegir", "launch": [], "check": str(path),
                           "rom": {"path": str(path), "system": "switch"}}]}

    def test_nup_is_merged_into_the_port_of_the_same_ficha(self):
        listed = self.games(self.rom_game(self.nup, "rom-1"))
        self.assertEqual([g["id"] for g in listed], ["recomp-longshot"])
        self.assertEqual(listed[0]["romCopy"]["id"], "rom-1")
        self.assertEqual(listed[0]["romCopy"]["path"], str(self.nup))

    def test_nup_stays_when_there_is_no_port(self):
        self.store.set_games([self.rom_game(self.nup, "rom-1")])
        listed = self.api.library({})["games"]
        self.assertEqual([g["id"] for g in listed], ["rom-1"])
        self.assertIsNone(listed[0]["romCopy"])

    def test_a_rom_an_emulator_can_run_is_kept_as_its_own_entry(self):
        listed = self.games(self.rom_game(self.rom, "rom-2"))
        self.assertEqual({g["id"] for g in listed}, {"recomp-longshot", "rom-2"})

    def test_port_available_when_the_ficha_has_a_package_and_no_port_is_installed(self):
        self.store.set_games([self.rom_game(self.nup, "rom-1", slug="mario-kart-world")])
        self.store.state["catalog_platforms"] = {"mario-kart-world": ["switch2"]}
        self.assertIsNone(self.api.library({})["games"][0]["portAvailable"])                  # aún sin paquetes conocidos
        self.store.state["catalog_packages"] = {"mario-kart-world": [{"id": "0" * 36, "title": "mkw-recomp", "version": "v1", "sizeBytes": 5,
                                                                      "licenseName": "MIT", "sourceName": "GitHub: a/b"}]}
        offer = self.api.library({})["games"][0]["portAvailable"]
        self.assertEqual((offer["slug"], offer["packageId"], offer["licenseName"], offer["count"]), ("mario-kart-world", "0" * 36, "MIT", 1))
        self.store.set_games([self.rom_game(self.nup, "rom-1", slug="mario-kart-world"),
                              {"id": "inst", "name": "MKW", "platform": "sw2", "catalogSlug": "mario-kart-world", "installPackageId": "x", "ports": []}])
        listed = {g["id"]: g for g in self.api.library({})["games"]}
        self.assertIsNone(listed["rom-1"]["portAvailable"])                                   # ya instalado: no se vuelve a ofrecer

    def test_launch_is_refused_while_the_port_is_missing(self):
        from omnia.api import ApiError
        self.store.set_games([self.rom_game(self.nup, "rom-1", slug="mario-kart-world")])
        self.store.state["catalog_platforms"] = {"mario-kart-world": ["switch2"]}
        self.store.state["catalog_packages"] = {"mario-kart-world": [{"id": "0" * 36, "title": "mkw", "version": "v1"}]}
        with self.assertRaises(ApiError) as caught:
            self.api.launch({"id": "rom-1", "port": "rom-1-main"})
        self.assertEqual(caught.exception.code, 409)
        self.assertIn("Instalar port", str(caught.exception))

    def test_other_fichas_are_not_merged(self):
        listed = self.games(self.rom_game(self.nup, "rom-3", slug="otra-ficha"))
        self.assertEqual({g["id"] for g in listed}, {"recomp-longshot", "rom-3"})


if __name__ == "__main__":
    unittest.main()
