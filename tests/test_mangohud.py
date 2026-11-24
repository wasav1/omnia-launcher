import tempfile
import unittest
from pathlib import Path

from omnia import mangohud


class MangoHudStyleTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(self.dir, True))

    def test_writes_a_single_centered_horizontal_line_with_the_omnia_palette(self):
        text = mangohud.render("/f/Rajdhani-SemiBold.ttf")
        for line in ("horizontal", "horizontal_stretch=0", "position=top-center", "font_file=/f/Rajdhani-SemiBold.ttf",
                     "background_color=0B0F14", "text_color=F3EFE3", "gpu_color=5B9BE0"):
            self.assertIn(line + "\n", text)
        self.assertTrue(text.startswith(mangohud.MARKER))

    def test_the_pill_has_dot_separators_side_padding_concave_corners_and_a_translucent_background(self):
        text = mangohud.render("")
        for line in ("horizontal_separator_dot", "window_padding_x=24", "concave_top_corners=14", "background_alpha=0.55"):
            self.assertIn(line + "\n", text)
        self.assertNotIn("custom_text", text)                        # el relleno ya no se simula con elementos en blanco (daban divisores en los extremos)

    def test_an_older_omnia_file_is_updated(self):
        path = self.dir / "MangoHud.conf"
        path.write_text("# omnia-generado v1\nfps\n", encoding="utf-8")
        mangohud.ensure(self.dir)
        self.assertTrue(path.read_text(encoding="utf-8").startswith(mangohud.MARKER))

    def test_without_the_font_the_file_still_works(self):
        self.assertNotIn("font_file", mangohud.render(""))

    def test_ensure_creates_updates_and_respects_manual_edits(self):
        path = mangohud.ensure(self.dir)
        self.assertTrue(path.read_text().startswith(mangohud.MARKER))
        path.write_text(mangohud.MARKER + "\nfps\n")              # diseño viejo con marca: se actualiza
        mangohud.ensure(self.dir)
        self.assertIn("position=top-center", path.read_text())
        path.write_text("fps\nposition=bottom-left\n")             # sin marca: es del usuario
        mangohud.ensure(self.dir)
        self.assertEqual(path.read_text(), "fps\nposition=bottom-left\n")

    def test_a_symlink_is_never_overwritten(self):
        target = self.dir / "otro"
        target.write_text("mio")
        (self.dir / "MangoHud.conf").symlink_to(target)
        mangohud.ensure(self.dir)
        self.assertEqual(target.read_text(), "mio")


if __name__ == "__main__":
    unittest.main()
