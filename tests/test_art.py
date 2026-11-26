import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import art


class Arte(unittest.TestCase):
    """Caché local de imágenes. La descarga y la clave de proveedores viven en omnia-backend, no en el cliente."""
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_slug_no_escapa_de_la_carpeta(self):
        d = art.art_dir("../../etc/passwd", "portada", self.tmp)
        self.assertTrue(str(d).startswith(str(self.tmp)))
        self.assertNotIn("..", d.relative_to(self.tmp).parts)

    def test_indice_se_invalida_cuando_cambia_el_directorio(self):
        folder = art.art_dir("game", "portada", self.tmp)
        folder.mkdir(parents=True)
        (folder / "1.png").write_bytes(b"one")
        self.assertEqual([p.name for p in art.cached_files("game", "portada", self.tmp)], ["1.png"])
        (folder / "2.png").write_bytes(b"two")
        self.assertEqual([p.name for p in art.cached_files("game", "portada", self.tmp)], ["1.png", "2.png"])


class ConApi(unittest.TestCase):
    def test_library_incluye_el_arte_cacheado(self):
        from omnia.api import Api
        from omnia.store import Store
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        with mock.patch.dict(os.environ, {"XDG_DATA_HOME": str(tmp / "data")}):
            d = art.art_dir("steam-10", "portada")
            d.mkdir(parents=True)
            (d / "1.png").write_bytes(b"x")
            st = Store(tmp / "cfg")
            st.set_games([{"id": "steam-10", "name": "Uno", "art": {"slug": "steam-10"},
                           "ports": [{"id": "p", "name": "S", "launch": ["x"], "check": str(tmp)}]}])
            api = Api(st, "t", [], scan_fn=list)
            self.addCleanup(api.httpd.server_close)
            g = api.library({})["games"][0]
            self.assertTrue(g["portada"].startswith("file://") and g["portada"].endswith("1.png"))
            self.assertNotIn("fondo", g)
