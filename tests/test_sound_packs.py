import unittest
import wave
from pathlib import Path

from omnia import sounds

ROOT = Path(__file__).resolve().parents[1] / "ui" / "qml" / "sounds"
NAMES = ["move", "confirm", "back", "menu", "page", "error", "done", "pad-on", "pad-off", "toggle", "open", "close"]   # los que pide OmniaSounds.qml


class ShippedSoundPackTests(unittest.TestCase):
    def test_every_pack_has_all_the_sounds_the_interface_asks_for(self):
        packs = [d for d in ROOT.iterdir() if d.is_dir()]
        self.assertGreaterEqual(len(packs), 2)
        for pack in packs:
            for name in NAMES:
                path = pack / f"{name}.wav"
                self.assertTrue(path.is_file(), f"{pack.name}/{name}.wav")
                with wave.open(str(path)) as w:                                        # WAV de 16 bits y corto
                    self.assertEqual(w.getsampwidth(), 2, path.name)
                    self.assertLess(w.getnframes() / w.getframerate(), 1.2, path.name)

    def test_the_cc0_pack_ships_its_license(self):
        self.assertIn("Creative Commons Zero", (ROOT / "kenney" / "LICENSE-Kenney-CC0.txt").read_text(errors="replace"))

    def test_the_core_lists_both_shipped_packs(self):
        ids = [p["id"] for p in sounds.packs([ROOT])]
        self.assertEqual(ids[0], "omnia")
        self.assertIn("kenney", ids)


if __name__ == "__main__":
    unittest.main()
