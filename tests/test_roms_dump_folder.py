import shutil
import struct
import tempfile
import unittest
from pathlib import Path

from omnia import roms
from omnia.games.rom_folders import RomFolderDetector


def npdm(program_id: int) -> bytes:
    data = bytearray(0x200)
    data[:4] = b"META"
    struct.pack_into("<II", data, 0x70, 0x100, 0x40)
    data[0x100:0x104] = b"ACI0"
    struct.pack_into("<Q", data, 0x110, program_id)
    return bytes(data)


def nso(build_id: bytes) -> bytes:
    data = bytearray(0x100)
    data[:4] = b"NSO0"
    data[0x40:0x40 + len(build_id)] = build_id
    return bytes(data)


class DumpFolderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def dump(self, where="Zelda Ocarina of Time/Juego", program_id=0x0400486024DEC000, build=bytes(range(1, 21))):
        folder = self.tmp / where
        (folder / "exefs").mkdir(parents=True)
        (folder / "romfs/data").mkdir(parents=True)
        (folder / "exefs/main").write_bytes(nso(build))
        (folder / "exefs/main.npdm").write_bytes(npdm(program_id))
        return folder

    def test_reads_title_id_and_build_id_from_a_switch2_dump(self):
        item = roms.inspect_dump_folder(str(self.dump()), [str(self.tmp)])
        self.assertEqual((item["system"], item["format"], item["internalId"], item["internalIdType"]), ("switch", "folder", "0400486024DEC000", "switch2"))
        self.assertEqual(item["buildId"], bytes(range(1, 21)).hex())
        self.assertEqual(roms.platform_for(item["system"], item["internalIdType"]), "sw2")

    def test_switch1_dump_and_update_or_dlc_titles(self):
        self.assertEqual(roms.inspect_dump_folder(str(self.dump("a", 0x0100F2C0115B6000)), [str(self.tmp)])["internalIdType"], "switch")
        self.assertIsNone(roms.inspect_dump_folder(str(self.dump("b", 0x0400486024DEC800)), [str(self.tmp)]))

    def test_rejects_incomplete_or_foreign_folders(self):
        folder = self.dump()
        shutil.rmtree(folder / "romfs")
        self.assertIsNone(roms.inspect_dump_folder(str(folder), [str(self.tmp)]))
        folder = self.dump("otro")
        (folder / "exefs/main").write_bytes(b"\x00" * 0x100)
        self.assertIsNone(roms.inspect_dump_folder(str(folder), [str(self.tmp)]))
        self.assertIsNone(roms.inspect_dump_folder(str(self.dump("c")), ["/nonexistent-root"]))

    def test_symlinked_exefs_is_not_followed(self):
        folder = self.dump("d")
        real = self.tmp / "elsewhere"
        (folder / "exefs").rename(real)
        (folder / "exefs").symlink_to(real)
        self.assertIsNone(roms.inspect_dump_folder(str(folder), [str(self.tmp)]))

    def test_scan_lists_the_folder_once_without_descending(self):
        self.dump()
        found = roms.scan(str(self.tmp), [str(self.tmp)])
        self.assertEqual([(i["format"], i["fileName"]) for i in found["items"]], [("folder", "Juego")])

    def test_library_game_is_named_after_the_parent_when_the_folder_is_generic(self):
        self.dump()
        detector = RomFolderDetector(folders_fn=lambda: [str(self.tmp)], scan_fn=lambda folder, roots: roms.scan(folder, [str(self.tmp)]))
        (game,) = detector.detect()
        self.assertEqual((game["name"], game["platform"]), ("Zelda Ocarina of Time", "sw2"))
        rom = game["ports"][0]["rom"]
        self.assertEqual((rom["internalId"], rom["buildId"]), ("0400486024DEC000", bytes(range(1, 21)).hex()))
        self.assertTrue(detector.is_installed(game, game["ports"][0]))

    def test_switch1_dump_folders_are_not_listed_as_games(self):
        self.dump("S1/Juego", 0x0100F2C0115B6000)
        detector = RomFolderDetector(folders_fn=lambda: [str(self.tmp)], scan_fn=lambda folder, roots: roms.scan(folder, [str(self.tmp)]))
        self.assertEqual(detector.detect(), [])


if __name__ == "__main__":
    unittest.main()
