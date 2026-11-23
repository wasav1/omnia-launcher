import shutil
import tempfile
import unittest
from pathlib import Path

from omnia import roms


class NupDetectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def make(self, name: str, size: int = 4096) -> str:
        path = self.tmp / name
        path.write_bytes(b"\x00" * size)
        return str(path)

    def test_nup_with_a_switch2_title_id_is_a_base_game(self):
        path = self.make("The Legend of Zelda Ocarina of Time [0400486024dec000][v131072].nup")
        item = roms.inspect_file(path, [str(self.tmp)], include_emulators=False)
        self.assertEqual((item["system"], item["internalId"], item["internalIdType"]), ("switch", "0400486024DEC000", "switch2"))
        self.assertEqual(roms.platform_for(item["system"], item["internalIdType"]), "sw2")

    def test_nup_without_an_id_is_taken_for_switch2(self):
        item = roms.inspect_file(self.make("Mario Kart World.nup"), [str(self.tmp)], include_emulators=False)
        self.assertEqual((item["internalId"], item["internalIdType"], item["confidence"]), ("", "switch2", "extension"))

    def test_nup_of_an_update_or_dlc_is_not_a_game(self):
        self.assertIsNone(roms.inspect_file(self.make("Juego [0400486024dec800].nup"), [str(self.tmp)], include_emulators=False))

    def test_a_switch1_title_id_in_a_nup_stays_switch1(self):
        item = roms.inspect_file(self.make("Juego [01007ef00011e000].nup"), [str(self.tmp)], include_emulators=False)
        self.assertEqual((item["internalId"], item["internalIdType"]), ("01007EF00011E000", "switch"))

    def test_scan_lists_nups_and_ignores_files_outside_the_roots(self):
        self.make("Mario Kart World.nup")
        found = roms.scan(str(self.tmp), [str(self.tmp)])
        self.assertEqual([i["fileName"] for i in found["items"]], ["Mario Kart World.nup"])
        with self.assertRaises(roms.RomScanError):
            roms.scan(str(self.tmp), ["/nonexistent-root"])


if __name__ == "__main__":
    unittest.main()
