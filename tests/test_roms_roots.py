import unittest



class RootsAsPaths(unittest.TestCase):
    """fsbrowse.allowed_roots() devuelve objetos Path; el escáner debe aceptarlos igual que texto."""
    def test_scan_accepts_path_roots(self):
        import tempfile, shutil
        from pathlib import Path
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        rom = bytearray(0x1000)
        rom[0:4] = b"\x80\x37\x12\x40"
        rom[0x20:0x34] = b"TEST GAME".ljust(20, b" ")
        rom[0x3B:0x3F] = b"NTSE"
        (tmp / "game.z64").write_bytes(bytes(rom))
        from omnia import roms
        for roots in ([tmp], [str(tmp)]):
            found = roms.scan(str(tmp), roots)
            self.assertEqual([i["fileName"] for i in found["items"]], ["game.z64"])
            self.assertEqual(found["items"][0]["internalId"], "NTSE")
