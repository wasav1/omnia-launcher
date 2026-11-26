import unittest

from omnia import online_catalog as oc


class Resp:
    def __init__(self, payload):
        import json, io
        self._b = io.BytesIO(json.dumps(payload).encode())
        self.headers = {"Content-Type": "application/json"}

    def read(self, n=-1):
        return self._b.read(n)

    def geturl(self):
        return oc.BASE_URL

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class PlatformMatch(unittest.TestCase):
    def test_same_platform_matches(self):
        self.assertTrue(oc.platform_compatible("n64", ["n64"]))
        self.assertTrue(oc.platform_compatible("sw2", ["switch2"]))
        self.assertTrue(oc.platform_compatible("gcwii", ["wii"]))

    def test_other_console_does_not_match(self):
        # el Ocarina de N64 no describe el remake de Switch 2
        self.assertFalse(oc.platform_compatible("sw2", ["n64"]))
        self.assertFalse(oc.platform_compatible("sw1", ["switch2"]))

    def test_incomplete_data_is_not_blocked(self):
        self.assertTrue(oc.platform_compatible("sw2", []))
        self.assertTrue(oc.platform_compatible("", ["n64"]))
        self.assertTrue(oc.platform_compatible("desconocida", ["n64"]))

    def test_fetch_entry_returns_platforms_and_artwork(self):
        art = "/api/v1/artwork/e56123de-6143-49e4-a288-297095f77ab1/image"
        body = {"ok": True, "data": {"slug": "zelda", "platforms": [{"slug": "N64"}],
                                      "artwork": [{"type": "grid", "mimeType": "image/png", "imageUrl": art},
                                                  {"type": "grid", "imageUrl": "https://evil.example/x"}]}}
        entry = oc.fetch_entry("zelda", opener=lambda req, timeout=0: Resp(body))
        self.assertEqual(entry["platforms"], ["n64"])
        self.assertEqual([a["url"] for a in entry["artwork"]], [oc.PUBLIC_ORIGIN + art])


if __name__ == "__main__":
    unittest.main()


class ApiPlatformMatch(unittest.TestCase):
    URL = oc.PUBLIC_ORIGIN + "/api/v1/artwork/e56123de-6143-49e4-a288-297095f77ab1/image"

    def _api(self, platform, catalog_platforms):
        import shutil, tempfile
        from pathlib import Path
        from omnia.api import Api
        from omnia.store import Store
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        from unittest import mock
        # aislado: ni red ni la caché real del usuario
        env = mock.patch.dict("os.environ", {"XDG_CACHE_HOME": str(tmp / "cache")})
        env.start(); self.addCleanup(env.stop)
        pre = mock.patch.object(oc, "prefetch_artwork")
        pre.start(); self.addCleanup(pre.stop)
        st = Store(tmp / "cfg")
        st.set_games([{"id": "g1", "name": "Ocarina", "platform": platform, "catalogSlug": "ocarina",
                       "ports": [{"id": "p", "name": "P", "launch": ["x"], "check": str(tmp)}]}])
        st.state["catalog_art"] = {"ocarina": {"grid": self.URL}}
        st.state["catalog_platforms"] = {"ocarina": catalog_platforms}
        api = Api(st, "t", [], scan_fn=list)
        self.addCleanup(api.httpd.server_close)
        return api, st

    def test_art_only_from_a_ficha_of_the_same_platform(self):
        api, _ = self._api("sw2", ["n64"])
        self.assertNotIn("portada", api.library({})["games"][0])
        api, _ = self._api("n64", ["n64"])
        self.assertEqual(api.library({})["games"][0]["portada"], self.URL)

    def test_link_to_other_platform_is_rejected(self):
        from unittest import mock
        from omnia.api import ApiError
        api, _ = self._api("sw2", ["n64"])
        detail = {"data": {"slug": "ocarina-n64", "platforms": [{"slug": "n64", "name": "Nintendo 64"}]}}
        with mock.patch.object(oc, "game_detail", return_value=detail):
            with self.assertRaises(ApiError) as ctx:
                api.game_catalog_link({"_body": {"id": "g1", "slug": "ocarina-n64"}})
        self.assertEqual(ctx.exception.code, 409)


class AutoLink(unittest.TestCase):
    ITEMS = [
        {"slug": "ocarina-n64", "name": "The Legend of Zelda: Ocarina of Time", "platforms": [{"slug": "n64"}]},
        {"slug": "ocarina-sw2", "name": "The Legend of Zelda: Ocarina of Time", "platforms": [{"slug": "switch2"}]},
        {"slug": "botw", "name": "The Legend of Zelda: Breath of the Wild", "platforms": [{"slug": "switch"}]},
        {"slug": "dup-a", "name": "Doble", "platforms": [{"slug": "switch"}]},
        {"slug": "dup-b", "name": "Doble", "platforms": [{"slug": "switch"}]},
    ]

    def test_matches_name_and_platform(self):
        self.assertEqual(oc.match_local_game({"name": "The Legend of Zelda: Ocarina of Time", "platform": "sw2"}, self.ITEMS), "ocarina-sw2")
        self.assertEqual(oc.match_local_game({"name": "The Legend of Zelda: Ocarina of Time", "platform": "n64"}, self.ITEMS), "ocarina-n64")
        self.assertEqual(oc.match_local_game({"name": "the legend of zelda breath of the wild", "platform": "sw1"}, self.ITEMS), "botw")

    def test_does_not_guess(self):
        self.assertEqual(oc.match_local_game({"name": "Doble", "platform": "sw1"}, self.ITEMS), "")       # ambigua
        self.assertEqual(oc.match_local_game({"name": "BioShock Infinite", "platform": "pc"}, self.ITEMS), "")
        self.assertEqual(oc.match_local_game({"name": "The Legend of Zelda: Breath of the Wild", "platform": "sw2"}, self.ITEMS), "")
        self.assertEqual(oc.match_local_game({"name": "The Legend of Zelda: Breath of the Wild"}, self.ITEMS), "")

    def test_service_links_only_games_without_a_valid_ficha(self):
        import shutil, tempfile
        from pathlib import Path
        from omnia import service
        from omnia.store import Store
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        st = Store(tmp)
        st.set_games([
            {"id": "a", "name": "The Legend of Zelda: Ocarina of Time", "platform": "sw2", "catalogSlug": "ocarina-n64", "ports": []},
            {"id": "b", "name": "The Legend of Zelda: Breath of the Wild", "platform": "sw1", "ports": []},
            {"id": "c", "name": "The Legend of Zelda: Breath of the Wild", "platform": "sw1", "catalogSlug": "mi-eleccion", "ports": []},
        ])
        st.state["catalog_platforms"] = {"ocarina-n64": ["n64"], "mi-eleccion": ["switch"]}
        self.assertEqual(service.auto_link_catalog(st, self.ITEMS), 2)
        links = {g["id"]: g.get("catalogSlug") for g in st.games()}
        self.assertEqual(links, {"a": "ocarina-sw2", "b": "botw", "c": "mi-eleccion"})
        self.assertEqual(service.auto_link_catalog(st, self.ITEMS), 0)       # idempotente


class ArtCache(unittest.TestCase):
    URL = oc.PUBLIC_ORIGIN + "/api/v1/artwork/e56123de-6143-49e4-a288-297095f77ab1/image"

    class Img:
        def __init__(self, final, mime="image/png", body=b"\x89PNG-data"):
            import io
            self._b, self._final = io.BytesIO(body), final
            self.headers = {"Content-Type": mime}

        def read(self, n=-1):
            return self._b.read(n)

        def geturl(self):
            return self._final

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    def _tmp(self):
        import shutil, tempfile
        from pathlib import Path
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        return tmp

    def test_redirect_to_steamgriddb_cdn_is_stored_once(self):
        tmp, calls = self._tmp(), []
        def opener(req, timeout=0):
            calls.append(1)
            return self.Img("https://cdn2.steamgriddb.com/grid/x.png")
        path = oc.store_artwork(self.URL, base=tmp, opener=opener)
        self.assertTrue(path.is_file() and path.suffix == ".png")
        self.assertEqual(oc.store_artwork(self.URL, base=tmp, opener=opener), path)
        self.assertEqual(len(calls), 1)                                  # la segunda vez sale de la caché
        self.assertEqual(oc.cached_artwork_path(self.URL, tmp), path)

    def test_redirect_to_any_other_host_is_rejected(self):
        tmp = self._tmp()
        for final in ("https://evil.example/x.png", "http://cdn2.steamgriddb.com/x.png", "https://steamgriddb.com.evil.example/x.png"):
            with self.assertRaises(oc.CatalogError):
                oc.store_artwork(self.URL, base=tmp, opener=lambda req, timeout=0, f=final: self.Img(f))
        self.assertIsNone(oc.cached_artwork_path(self.URL, tmp))

    def test_non_image_is_rejected(self):
        tmp = self._tmp()
        with self.assertRaises(oc.CatalogError):
            oc.store_artwork(self.URL, base=tmp, opener=lambda req, timeout=0: self.Img(self.URL, mime="text/html"))

    def test_add_local_art_uses_file_url_only_when_cached(self):
        from unittest import mock
        tmp = self._tmp()
        item = {"artwork": [{"imageUrl": "/api/v1/artwork/e56123de-6143-49e4-a288-297095f77ab1/image"}]}
        with mock.patch.object(oc, "art_cache_dir", return_value=tmp / "catalog-art"), \
                mock.patch.object(oc, "prefetch_artwork") as queued:
            oc.add_local_art([item])
            self.assertNotIn("localUrl", item["artwork"][0])           # aún no está: se encola
            queued.assert_called()
            oc.store_artwork(self.URL, base=tmp, opener=lambda req, timeout=0: self.Img("https://cdn2.steamgriddb.com/x.png"))
            oc.add_local_art([item])
            self.assertTrue(item["artwork"][0]["localUrl"].startswith("file://"))
