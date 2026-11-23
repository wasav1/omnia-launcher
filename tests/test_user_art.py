import os
import shutil
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

from omnia import online_catalog, security
from omnia.api import Api, ApiError
from omnia.store import Store


def png(width: int, height: int) -> bytes:
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\x20\x40\x60" * width for _ in range(height))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


class UserArtTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        env = mock.patch.dict(os.environ, {"XDG_CACHE_HOME": str(self.tmp / "cache"), "XDG_DATA_HOME": str(self.tmp / "data"),
                                           "XDG_CONFIG_HOME": str(self.tmp / "cfg")})
        env.start()
        self.addCleanup(env.stop)
        self.store = Store(self.tmp / "cfg")
        self.api = Api(self.store, security.new_token(self.tmp / "run"), [], scan_fn=list, fs_roots=[self.tmp])
        self.api.serve()
        self.addCleanup(self.api.stop)
        self.store.set_games([{"id": "g1", "name": "Juego", "platform": "n64", "catalogSlug": "juego",
                               "ports": [{"id": "p", "name": "x", "launch": ["x"], "check": str(self.tmp)}]}])
        self.image = self.tmp / "mi-fondo.png"
        self.image.write_bytes(png(640, 360))

    def local(self, **body):
        return self.api.art_local({"_body": {"id": "g1", "kind": "fondo", "path": str(self.image), **body}})

    def test_a_valid_image_replaces_the_catalog_art_and_is_copied_to_the_cache(self):
        self.store.state["catalog_art"] = {"juego": {"hero": "https://example.test/x"}}
        self.assertEqual(self.local(), {"ok": True, "kind": "fondo"})
        shown = self.api.library({})["games"][0]["fondo"]
        self.assertTrue(shown.startswith("file://") and "user-art" in shown)
        self.assertNotEqual(shown, "file://" + str(self.image))            # es una copia: el original no se vuelve a leer
        self.assertTrue(os.path.isfile(shown[7:]))

    def test_replacing_removes_the_previous_copy(self):
        self.local()
        first = self.store.state["art_custom"]["g1"]["fondo"]["file"]
        self.image.write_bytes(png(800, 450))
        self.local()
        self.assertFalse(os.path.exists(first))

    def test_rejects_unsafe_or_invalid_files(self):
        outside = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, outside, True)
        evil = Path(outside) / "x.png"
        evil.write_bytes(png(640, 360))
        link = self.tmp / "enlace.png"
        link.symlink_to(self.image)
        notimg = self.tmp / "texto.png"
        notimg.write_text("hola")
        for body in ({"path": str(evil)}, {"path": str(link)}, {"path": str(notimg)}, {"path": str(self.tmp / "nada.png")},
                     {"kind": "icono"}, {"id": "zz"}):
            with self.assertRaises(ApiError, msg=str(body)):
                self.local(**body)

    def test_the_framed_image_left_in_the_tmp_folder_is_consumed(self):
        folder = Path(self.api.art_tmp({})["dir"])
        framed = folder / "enmarcada.png"
        framed.write_bytes(png(640, 360))
        with mock.patch.object(self.api, "_allowed", return_value=True):
            self.local(path=str(framed))
        self.assertFalse(framed.exists())

    def test_choosing_an_option_downloads_verifies_and_stores_it(self):
        url = "https://cdn2.steamgriddb.com/hero/abc.png"
        with mock.patch.object(online_catalog, "download_option_image", return_value=png(640, 360)) as dl:
            self.assertEqual(self.api.art_choose({"_body": {"id": "g1", "kind": "fondo", "url": url}}), {"ok": True, "kind": "fondo"})
        self.assertEqual(dl.call_args.args[0], url)
        self.assertTrue(self.api.library({})["games"][0]["fondo"].startswith("file://"))

    def test_choosing_rejects_bad_urls_images_and_kinds(self):
        for url in ("http://cdn2.steamgriddb.com/x.png", "https://evil.example.com/x.png", "https://user@cdn2.steamgriddb.com/x.png", ""):
            with self.assertRaises(ApiError, msg=url):
                self.api.art_choose({"_body": {"id": "g1", "kind": "fondo", "url": url}})
        with mock.patch.object(online_catalog, "download_option_image", return_value=b"no soy una imagen"), self.assertRaises(ApiError):
            self.api.art_choose({"_body": {"id": "g1", "kind": "fondo", "url": "https://cdn2.steamgriddb.com/x.png"}})
        with self.assertRaises(ApiError):
            self.api.art_choose({"_body": {"id": "g1", "kind": "icono", "url": "https://cdn2.steamgriddb.com/x.png"}})

    def test_browse_lists_the_current_image_then_the_steamgriddb_page(self):
        cur = "https://recompihub.example/api/v1/artwork/1/image"
        remote = [{"kind": "hero", "url": cur}]
        options = {"linked": True, "hasMore": True, "offline": False, "stale": False, "items": [
            {"id": "7", "url": "https://cdn2.steamgriddb.com/hero/a.png", "thumb": "https://cdn2.steamgriddb.com/thumb/a.png", "width": 1920, "height": 620, "author": "ana", "style": "alternate", "score": 5}]}
        with mock.patch.object(online_catalog, "fetch_artwork", return_value=remote), mock.patch.object(online_catalog, "fetch_art_options", return_value=options):
            first = self.api.art_browse({"id": "g1", "kind": "fondo", "page": "0"})
            more = self.api.art_browse({"id": "g1", "kind": "fondo", "page": "1"})
        self.assertEqual([(i["id"], i["cur"]) for i in first["items"]], [("actual", True), ("7", False)])
        self.assertTrue(first["more"])
        self.assertEqual([i["id"] for i in more["items"]], ["7"])                      # la imagen actual solo va en la página 0

    def test_browse_keeps_the_current_image_when_the_options_endpoint_fails(self):
        remote = [{"kind": "hero", "url": "https://recompihub.example/api/v1/artwork/1/image"}]
        with mock.patch.object(online_catalog, "fetch_artwork", return_value=remote), \
                mock.patch.object(online_catalog, "fetch_art_options", side_effect=online_catalog.CatalogError("sin red")):
            result = self.api.art_browse({"id": "g1", "kind": "fondo"})
        self.assertEqual(len(result["items"]), 1)
        self.assertEqual(result["warning"], "sin red")

    def test_reset_returns_to_the_catalog_and_removes_the_copy(self):
        self.local()
        copy = self.store.state["art_custom"]["g1"]["fondo"]["file"]
        self.store.state["catalog_art"] = {"juego": {"hero": "x"}}
        self.api.art_reset({"_body": {"id": "g1", "kind": "fondo"}})
        self.assertFalse(os.path.exists(copy))
        self.assertNotIn("fondo", self.store.state["art_custom"]["g1"])
        self.assertNotIn("hero", self.store.state["catalog_art"]["juego"])
        self.assertNotIn("juego", self.store.state.get("catalog_art_checked", {}))


if __name__ == "__main__":
    unittest.main()
