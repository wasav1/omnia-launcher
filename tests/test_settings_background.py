import shutil
import tempfile
import unittest
from pathlib import Path

from omnia import security
from omnia.api import Api, ApiError
from omnia.store import Store


class FondoAnimado(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.store = Store(self.tmp / "cfg")
        self.api = Api(self.store, security.new_token(self.tmp / "run"), [], scan_fn=lambda: [])

    def test_activado_por_defecto(self):
        self.assertTrue(self.api.settings({})["animated_background"])

    def test_se_guarda_y_se_lee(self):
        self.assertEqual(self.api.settings_animated_background({"_body": {"enabled": False}}),
                         {"ok": True, "animated_background": False})
        self.assertFalse(self.api.settings({})["animated_background"])
        self.api.settings_animated_background({"_body": {"enabled": True}})
        self.assertTrue(self.api.settings({})["animated_background"])

    def test_rechaza_valores_que_no_son_booleanos(self):
        for body in ({}, {"enabled": "no"}, {"enabled": 0}, None):
            with self.assertRaises(ApiError):
                self.api.settings_animated_background({"_body": body})

    def test_conserva_otros_ajustes(self):
        self.api.settings_language({"_body": {"language": "en"}})
        self.api.settings_animated_background({"_body": {"enabled": False}})
        cfg = self.api.settings({})
        self.assertEqual((cfg["language"], cfg["animated_background"]), ("en", False))


if __name__ == "__main__":
    unittest.main()
