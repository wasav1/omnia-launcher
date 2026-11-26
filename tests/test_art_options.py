import io
import unittest
from unittest import mock

from omnia import online_catalog as oc


class Response(io.BytesIO):
    def __init__(self, data, url, mime="image/png"):
        super().__init__(data)
        self._url, self.headers = url, {"Content-Type": mime}

    def geturl(self):
        return self._url

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class ArtOptionsTests(unittest.TestCase):
    def test_options_are_filtered_to_the_steamgriddb_cdn(self):
        good = {"id": "1", "url": "https://cdn2.steamgriddb.com/grid/a.png", "thumb": "https://cdn2.steamgriddb.com/thumb/a.png", "width": 600, "height": 900}
        rows = [good, {"id": "2", "url": "http://cdn2.steamgriddb.com/a.png", "thumb": good["thumb"]},
                {"id": "3", "url": "https://evil.example.com/a.png", "thumb": good["thumb"]}, "no es un dict",
                {"id": "4", "url": "https://user@cdn2.steamgriddb.com/a.png", "thumb": good["thumb"]}]
        with mock.patch.object(oc, "_get", return_value={"data": {"linked": True, "hasMore": True, "items": rows}}) as get:
            out = oc.fetch_art_options("banjo-tooie", "portada", 2)
        self.assertEqual([i["id"] for i in out["items"]], ["1"])
        self.assertTrue(out["linked"] and out["hasMore"])
        self.assertEqual(get.call_args.args[1], {"type": "grid", "page": "2"})

    def test_invalid_arguments_are_rejected(self):
        for args in (("BAD SLUG", "portada", 0), ("juego", "icono", 0), ("juego", "fondo", 99), ("juego", "fondo", -1)):
            with self.assertRaises(oc.CatalogError, msg=str(args)):
                oc.fetch_art_options(*args)

    def test_download_accepts_only_the_cdn_images_within_the_limit(self):
        url = "https://cdn2.steamgriddb.com/hero/a.png"
        ok = lambda request, timeout=0: Response(b"\x89PNG....", url)
        self.assertEqual(oc.download_option_image(url, opener=ok), b"\x89PNG....")
        for bad_url in ("https://evil.example.com/a.png", "http://cdn2.steamgriddb.com/a.png"):
            with self.assertRaises(oc.CatalogError):
                oc.download_option_image(bad_url, opener=ok)
        redirected = lambda request, timeout=0: Response(b"x", "https://evil.example.com/a.png")
        with self.assertRaises(oc.CatalogError):
            oc.download_option_image(url, opener=redirected)
        html = lambda request, timeout=0: Response(b"<html>", url, "text/html")
        with self.assertRaises(oc.CatalogError):
            oc.download_option_image(url, opener=html)
        with self.assertRaises(oc.CatalogError):
            oc.download_option_image(url, opener=ok, limit=3)


if __name__ == "__main__":
    unittest.main()
