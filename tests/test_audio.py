import array
import math
import unittest

from omnia import audio


def tone(freq, n=audio.CHUNK, rate=audio.RATE, amp=12000, offset=0):
    return array.array("h", [int(amp * math.sin(2 * math.pi * freq * (offset + i) / rate)) for i in range(n)])


class AnalyzerTests(unittest.TestCase):
    def run_tone(self, freq, chunks=40):
        a = audio.Analyzer()
        out = [0.0] * audio.BANDS
        for k in range(chunks):
            out = a.feed(tone(freq, offset=k * audio.CHUNK))
        return out

    def test_plan_has_all_bands_and_sane_windows(self):
        plan = audio.band_plan()
        self.assertEqual(len(plan), audio.BANDS)
        for coeff, n, win in plan:
            self.assertEqual(len(win), n)
            self.assertTrue(48 <= n <= audio.WINDOW)

    def test_silence_gives_zeros(self):
        a = audio.Analyzer()
        for _ in range(30):
            out = a.feed(array.array("h", [0] * audio.CHUNK))
        self.assertEqual(out, [0.0] * audio.BANDS)

    def test_bass_tone_peaks_left_and_treble_right(self):
        low, high = self.run_tone(110), self.run_tone(5000)
        self.assertLess(low.index(max(low)), audio.BANDS // 4)
        self.assertGreater(high.index(max(high)), audio.BANDS * 2 // 3)

    def test_values_are_normalized(self):
        out = self.run_tone(440)
        self.assertTrue(all(0.0 <= v <= 1.0 for v in out))
        self.assertGreater(max(out), 0.9)

    def test_snapshot_shape(self):
        s = audio.AudioSpectrum().snapshot()
        self.assertEqual(len(s["bands"]), audio.BANDS)
        self.assertFalse(s["available"])


if __name__ == "__main__":
    unittest.main()
