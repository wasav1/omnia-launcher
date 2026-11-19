import shutil
import tempfile
import unittest
from pathlib import Path

from omnia.games.gfn import GeForceNowDetector, desktop_dirs
from omnia.games.registry import default_detectors


def acceso(d, fname, name, exec_):
    p = Path(d, fname)
    p.write_text(f"[Desktop Entry]\nType=Application\nName={name}\nExec={exec_}\nIcon=x\n")
    return p


class GfnTests(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home, True)
        self.desk = self.home / "Escritorio"
        self.desk.mkdir()

    def det(self):
        return GeForceNowDetector(home=self.home)

    def test_detecta_acceso_de_juego_y_quita_el_sufijo(self):
        f = acceso(self.desk, "stalker.desktop", "S.T.A.L.K.E.R. 2 (GeForce NOW)",
                   'flatpak run com.nvidia.geforcenow "--url-route=#?cmsId=101909611&launchSource=External"')
        (g,) = self.det().detect()
        self.assertEqual(g["name"], "S.T.A.L.K.E.R. 2")
        self.assertEqual((g["platform"], g["src"], g["auto"]), ("pc", "GeForce NOW", "gfn"))
        self.assertEqual(g["id"], "gfn-s-t-a-l-k-e-r-2")
        self.assertEqual(g["ports"][0]["launch"], ["gio", "launch", str(f)])
        self.assertEqual(g["ports"][0]["proc"], "")                     # la app queda abierta: nunca «en ejecución»

    def test_el_launcher_no_es_un_juego(self):
        acceso(self.desk, "gfn.desktop", "GeForce NOW", "flatpak run com.nvidia.geforcenow")
        self.assertEqual(self.det().detect(), [])

    def test_ignora_accesos_ajenos(self):
        acceso(self.desk, "otro.desktop", "Dolphin", "dolphin")
        (self.desk / "nota.txt").write_text("geforcenow")
        self.assertEqual(self.det().detect(), [])

    def test_desaparece_al_borrar_el_acceso(self):
        f = acceso(self.desk, "a.desktop", "Juego (GeForce NOW)", "flatpak run com.nvidia.geforcenow x")
        d = self.det()
        (g,) = d.detect()
        self.assertTrue(d.is_installed(g, g["ports"][0]))
        f.unlink()
        self.assertFalse(d.is_installed(g, g["ports"][0]))
        self.assertEqual(d.detect(), [])

    def test_usa_el_escritorio_de_user_dirs(self):
        otro = self.home / "Mesa"
        otro.mkdir()
        (self.home / ".config").mkdir()
        (self.home / ".config/user-dirs.dirs").write_text('XDG_DESKTOP_DIR="$HOME/Mesa"\n')
        self.assertEqual(desktop_dirs(self.home)[0], otro)

    def test_esta_en_los_detectores_por_defecto(self):
        self.assertIn("gfn", [d.name for d in default_detectors()])


if __name__ == "__main__":
    unittest.main()
