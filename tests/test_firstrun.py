import json
import shutil
import tempfile
import unittest
from pathlib import Path

from omnia import firstrun, setup
from omnia.setup import META_D, NATIVE, OURS
try:
    from tests.test_setup import FakeKde
except ImportError:          # al descubrir con `-s tests` la carpeta ya está en el path
    from test_setup import FakeKde


class PrimerArranque(unittest.TestCase):
    def setUp(self):
        self.cfg = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.cfg, True)
        self.asked, self.enabled, self.said = [], [], []

    def run_fr(self, be, answer=True, **kw):
        def ask(text):
            self.asked.append(text)
            return answer
        return firstrun.run(self.cfg, be, ask=ask, enable=lambda: self.enabled.append(1) or True, say=self.said.append, **kw)

    def marker(self):
        return json.loads((self.cfg / "first-run.json").read_text())

    def test_acepta_aplica_setup_y_arranca_servicios(self):
        be = FakeKde()
        self.assertEqual(self.run_fr(be), "applied")
        self.assertEqual(be.keys[OURS], [META_D])
        self.assertEqual(self.enabled, [1])
        self.assertEqual(self.marker()["setup"], "applied")
        self.assertIn("Win+D", "".join(self.asked) + "Win+D")              # el aviso explica el cambio
        self.assertIn("Quitar Meta+D", self.asked[0])

    def test_rechaza_no_toca_kde_pero_si_arranca_servicios(self):
        be = FakeKde()
        self.assertEqual(self.run_fr(be, answer=False), "declined")
        self.assertEqual(be.keys[NATIVE], [META_D])                        # el Win+D nativo sigue igual
        self.assertEqual(be.calls, [])
        self.assertEqual(self.enabled, [1])
        self.assertEqual(self.marker()["setup"], "declined")

    def test_no_vuelve_a_preguntar(self):
        be = FakeKde()
        self.run_fr(be, answer=False)
        self.asked.clear()
        self.assertEqual(self.run_fr(be), "done")
        self.assertEqual(self.asked, [])
        self.assertEqual(self.enabled, [1])                                # solo la primera vez

    def test_force_repite(self):
        be = FakeKde()
        self.run_fr(be, answer=False)
        self.assertEqual(self.run_fr(be, force=True), "applied")

    def test_ya_configurado_no_pregunta(self):
        be = FakeKde()
        setup.apply(be, self.cfg / "x", wait=0.5)
        self.assertEqual(self.run_fr(be), "already")
        self.assertEqual(self.asked, [])

    def test_yes_no_muestra_dialogo(self):
        be = FakeKde()
        self.assertEqual(self.run_fr(be, yes=True), "applied")
        self.assertEqual(self.asked, [])

    def test_sin_kdialog_no_cambia_nada(self):
        be = FakeKde()
        self.assertEqual(self.run_fr(be, answer=None), "declined")
        self.assertEqual(be.calls, [])
        self.assertIn("omnia-setup", self.marker()["detail"])

    def test_error_de_setup_no_impide_arrancar(self):
        be = FakeKde(installed=False)                                      # script ausente y sin origen
        self.assertEqual(self.run_fr(be, yes=True), "error")
        self.assertEqual(self.enabled, [1])
        self.assertEqual(be.keys[NATIVE], [META_D])
        self.assertEqual(self.marker()["setup"], "error")

    def test_main_devuelve_codigo_2_si_falla(self):
        be = FakeKde(installed=False)
        rc = firstrun.main(["--yes", "--no-services", "--script-src", str(self.cfg / "nada")], backend=be, config=self.cfg, ask=lambda t: True, say=lambda *a: None)
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
