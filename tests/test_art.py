import io
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import art


class Resp(io.BytesIO):
    def __init__(self, body: bytes, ctype="application/json"):
        super().__init__(body)
        self.headers = {"Content-Type": ctype}

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()


class FakeNet:
    """SteamGridDB simulado. Registra cada petición (url, ¿con Authorization?)."""

    def __init__(self, png=b"\x89PNG-fake"):
        self.calls, self.png = [], png

    def __call__(self, req, timeout=0):
        url = req.full_url
        self.calls.append((url, req.get_header("Authorization")))
        if "/grids/steam/10" in url:
            return Resp(json.dumps({"data": [{"url": "https://cdn2.steamgriddb.com/grid/a.png"}]}).encode())
        if "/heroes/steam/10" in url:
            return Resp(json.dumps({"data": [{"url": "https://cdn2.steamgriddb.com/hero/b.png"}]}).encode())
        if "/search/autocomplete/" in url:
            return Resp(json.dumps({"data": [{"id": 77}]}).encode())
        if "/grids/game/77" in url:
            return Resp(json.dumps({"data": [{"url": "https://evil.example.com/x.png"}, {"url": "https://cdn2.steamgriddb.com/grid/c.png"}]}).encode())
        if url.endswith((".png",)):
            return Resp(self.png, "image/png")
        return Resp(b"{}")


class Arte(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.net = FakeNet()
        self.cli = art.Client("CLAVE-SECRETA", opener=self.net)

    def test_juego_de_steam_baja_portada_y_fondo(self):
        g = {"id": "steam-10", "name": "Uno", "art": {"slug": "steam-10"}}
        got = art.fetch_game(self.cli, g, base=self.tmp)
        self.assertEqual(sorted(got), ["fondo", "portada"])
        self.assertTrue(Path(got["portada"]).is_file())
        self.assertEqual(art.cached("steam-10", "portada", self.tmp), got["portada"])

    def test_clave_solo_va_a_la_api_no_al_cdn(self):
        art.fetch_game(self.cli, {"id": "steam-10", "name": "Uno", "art": {"slug": "s"}}, base=self.tmp)
        for url, auth in self.net.calls:
            if "/api/v2/" in url:
                self.assertEqual(auth, "Bearer CLAVE-SECRETA")
            else:
                self.assertIsNone(auth, "la clave no debe enviarse al CDN: " + url)

    def test_no_vuelve_a_descargar_lo_cacheado(self):
        g = {"id": "steam-10", "name": "Uno", "art": {"slug": "s"}}
        art.fetch_game(self.cli, g, base=self.tmp)
        n = len(self.net.calls)
        self.assertEqual(art.fetch_game(self.cli, g, base=self.tmp), {})
        self.assertEqual(len(self.net.calls), n)

    def test_fuera_de_steam_busca_por_nombre_y_salta_hosts_ajenos(self):
        g = {"id": "heroic-gog-1", "name": "Otro", "art": {"slug": "h1", "sgdb": "Otro"}}
        got = art.fetch_game(self.cli, g, kinds=("portada",), base=self.tmp)
        self.assertTrue(got["portada"].endswith(".png"))
        self.assertFalse(any("evil.example.com" in u for u, _ in self.net.calls))   # nunca se pidió al host ajeno

    def test_urls_permitidas(self):
        self.assertTrue(art.url_allowed("https://cdn2.steamgriddb.com/x.png"))
        self.assertTrue(art.url_allowed("https://www.steamgriddb.com/api/v2/grids"))
        for bad in ("http://cdn2.steamgriddb.com/x.png", "https://steamgriddb.com.evil.com/x.png",
                    "https://evilsteamgriddb.com/x", "file:///etc/passwd", "https://localhost/x", "ftp://cdn2.steamgriddb.com/x"):
            self.assertFalse(art.url_allowed(bad), bad)

    def test_rechaza_tipo_y_tamano(self):
        with self.assertRaises(art.ArtError):
            art.Client("k", opener=lambda r, timeout=0: Resp(b"<html>", "text/html")).download("https://cdn2.steamgriddb.com/a", self.tmp)
        with mock.patch.object(art, "MAX_BYTES", 10), self.assertRaises(art.ArtError):
            art.Client("k", opener=lambda r, timeout=0: Resp(b"x" * 50, "image/png")).download("https://cdn2.steamgriddb.com/a.png", self.tmp)

    def test_slug_no_escapa_de_la_carpeta(self):
        d = art.art_dir("../../etc/passwd", "portada", self.tmp)
        self.assertTrue(str(d).startswith(str(self.tmp)))
        self.assertNotIn("..", d.relative_to(self.tmp).parts)

    def test_clave_y_permisos(self):
        k = self.tmp / "k"
        self.assertEqual(art.load_key(k), "")
        k.write_text("abc\n")
        os.chmod(k, 0o600)
        self.assertEqual(art.load_key(k), "abc")
        self.assertTrue(art.key_permissions_ok(k))
        os.chmod(k, 0o644)
        self.assertFalse(art.key_permissions_ok(k))

    def test_error_de_red_no_tumba(self):
        def roto(req, timeout=0):
            raise OSError("sin red")
        with self.assertRaises(art.ArtError):
            art.Client("k", opener=roto).candidates({"id": "steam-10", "name": "x"}, "portada")

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


class Ediciones(unittest.TestCase):
    """Ocarina of Time tiene dos ediciones con el mismo nombre en SteamGridDB: la de 1998 y la de Switch 2 (2026)."""
    EDS = ({"id": 21202, "name": "The Legend of Zelda: Ocarina of Time", "year": 1998},
           {"id": 5532594, "name": "The Legend of Zelda: Ocarina of Time", "year": 2026},
           {"id": 36271, "name": "The Legend of Zelda: Ocarina of Time 3D", "year": 2011})

    def juego(self, platform, **art_extra):
        return {"name": "Ocarina of Time · Longshot", "platform": platform,
                "art": {"sgdb": "The Legend of Zelda: Ocarina of Time", **art_extra}}

    def test_switch_2_toma_la_mas_reciente(self):
        self.assertEqual(art.pick_edition(self.EDS, self.juego("sw2")), 5532594)

    def test_n64_toma_la_original(self):
        self.assertEqual(art.pick_edition(self.EDS, self.juego("n64")), 21202)

    def test_el_ano_guardado_manda(self):
        self.assertEqual(art.pick_edition(self.EDS, self.juego("n64", year=2026)), 5532594)
        self.assertEqual(art.pick_edition(self.EDS, self.juego("sw2", year=1998)), 21202)

    def test_no_elige_3d_ni_variantes_si_hay_coincidencia_exacta(self):
        self.assertNotEqual(art.pick_edition(self.EDS, self.juego("pc")), 36271)

    def test_sin_coincidencia_exacta_usa_la_primera(self):
        eds = [{"id": 7, "name": "Otro juego", "year": 2020}, {"id": 8, "name": "Y otro", "year": 2024}]
        self.assertEqual(art.pick_edition(eds, {"name": "Nada que ver", "platform": "sw2"}), 7)


if __name__ == "__main__":
    unittest.main()
