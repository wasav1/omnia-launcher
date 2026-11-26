import tempfile
import unittest
from pathlib import Path

from omnia import mangohud


def fake_system(root: Path, gpus, cpu="Intel(R) Core(TM) i5-10300H CPU @ 2.50GHz", nvidia_model=None):
    pci = root / "pci"
    for addr, vendor, boot in gpus:
        d = pci / addr
        d.mkdir(parents=True)
        (d / "class").write_text("0x030000\n")
        (d / "vendor").write_text(vendor + "\n")
        (d / "boot_vga").write_text(("1" if boot else "0") + "\n")
    (root / "pci" / "0000:00:1f.3").mkdir(parents=True, exist_ok=True)
    (root / "pci" / "0000:00:1f.3" / "class").write_text("0x040300\n")       # una tarjeta de sonido no cuenta
    (root / "cpuinfo").write_text("processor\t: 0\nmodel name\t: " + cpu + "\n")
    nv = root / "nvidia"
    if nvidia_model:
        (nv / "0000:01:00.0").mkdir(parents=True)
        (nv / "0000:01:00.0" / "information").write_text("Model: \t\t " + nvidia_model + "\nIRQ: 1\n")
    return dict(pci=pci, cpuinfo=root / "cpuinfo", nvidia=nv)


class HardwareNameTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(self.root, True))

    def test_short_names(self):
        self.assertEqual([mangohud.short_cpu(x) for x in ("Intel(R) Core(TM) i5-10300H CPU @ 2.50GHz", "AMD Ryzen 7 5800H with Radeon Graphics",
                                                           "12th Gen Intel(R) Core(TM) i7-12700K", "Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz")],
                         ["i5-10300H", "Ryzen 7 5800H", "i7-12700K", "E5-2680 v4"])
        self.assertEqual([mangohud.short_gpu(x) for x in ("NVIDIA GeForce GTX 1650 Ti", "GeForce RTX 4070 Laptop GPU", "Radeon RX 6800 XT")],
                         ["GTX 1650 Ti", "RTX 4070", "RX 6800 XT"])
        self.assertEqual(mangohud.short_gpu("Evil;rm -rf #name"), "Evilrm -rf name")                  # solo caracteres seguros

    def test_laptop_with_two_gpus_picks_the_dedicated_one_by_pci_address(self):
        paths = fake_system(self.root, [("0000:00:02.0", "0x8086", True), ("0000:01:00.0", "0x10de", False)], nvidia_model="NVIDIA GeForce GTX 1650 Ti")
        self.assertEqual(mangohud.detect_hardware(**paths), {"cpu": "i5-10300H", "gpu": "GTX 1650 Ti", "pci": "0000:01:00.0"})

    def test_a_single_gpu_needs_no_pci_selection(self):
        paths = fake_system(self.root, [("0000:03:00.0", "0x1002", True)])
        info = mangohud.detect_hardware(name_of=lambda addr: "Navi 21 [Radeon RX 6800 XT]", **paths)
        self.assertEqual((info["gpu"], info["pci"]), ("RX 6800 XT", ""))

    def test_nothing_detected_leaves_the_default_labels(self):
        text = mangohud.render("", {"cpu": "", "gpu": "", "pci": ""})
        self.assertNotIn("gpu_text", text)
        self.assertNotIn("cpu_text", text)
        self.assertNotIn("pci_dev", text)

    def test_the_names_replace_the_gpu_and_cpu_labels(self):
        text = mangohud.render("", {"cpu": "i5-10300H", "gpu": "GTX 1650 Ti", "pci": "0000:01:00.0"})
        for line in ("gpu_text=GTX 1650 Ti", "cpu_text=i5-10300H", "pci_dev=0000:01:00.0"):
            self.assertIn(line + "\n", text)
        self.assertNotIn("gpu_list", text)


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
        lines = text.splitlines()
        self.assertEqual(lines[-2:], ["frame_timing", "frametime_color=5B9BE0"])               # la gráfica de tiempos de fotograma va al final de la fila
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
