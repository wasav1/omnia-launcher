import io
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import online_catalog as oc
from omnia import service


class FakeResponse(io.BytesIO):
    def __init__(self, data, url, mime="image/jpeg"):
        super().__init__(data)
        self._url = url
        self.headers = {"Content-Type": mime}

    def geturl(self):
        return self._url

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class SteamArtTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_urls_only_for_steam_games(self):
        urls = oc.steam_art_urls({"id": "steam-8870"})
        self.assertEqual(set(urls), {"portada", "fondo", "logo"})
        self.assertTrue(all(oc._is_steam_art_url(u) for u in urls.values()))
        self.assertEqual(oc.steam_art_urls({"id": "manual-1"}), {})
        self.assertEqual(oc.steam_art_urls({"id": "steam-abc"}), {})

    def test_rejects_other_hosts_and_paths(self):
        for bad in ("https://evil.example/steam/apps/1/logo.png", "http://cdn.cloudflare.steamstatic.com/steam/apps/1/logo.png",
                    "https://cdn.cloudflare.steamstatic.com/steam/apps/1/../x.png", "https://cdn.cloudflare.steamstatic.com/steam/apps/1/other.jpg"):
            self.assertFalse(oc._is_steam_art_url(bad), bad)
            with self.assertRaises(oc.CatalogError):
                oc.download_artwork(bad, opener=lambda *a, **k: self.fail("no debe pedirse"))

    def test_download_and_cache(self):
        url = oc.steam_art_urls({"id": "steam-8870"})["portada"]
        opener = mock.Mock(return_value=FakeResponse(b"\xff\xd8jpeg", url))
        path = oc.store_artwork(url, base=self.tmp, opener=opener)
        self.assertEqual(path.read_bytes(), b"\xff\xd8jpeg")
        self.assertEqual(oc.cached_artwork_path(url, self.tmp), path)

    def test_redirect_to_another_host_is_refused(self):
        url = oc.steam_art_urls({"id": "steam-8870"})["logo"]
        opener = mock.Mock(return_value=FakeResponse(b"x", "https://steamgriddb.com/x.png", "image/png"))
        with self.assertRaises(oc.CatalogError):
            oc.download_artwork(url, opener=opener)

    def test_sync_steam_art_retries_failures_later(self):
        retry = {}
        with mock.patch.object(oc, "cached_artwork_path", return_value=None), \
                mock.patch.object(oc, "store_artwork", side_effect=oc.CatalogError("404")) as store:
            self.assertFalse(service.sync_steam_art({"id": "steam-8870"}, retry))
            self.assertEqual(store.call_count, 3)
            self.assertFalse(service.sync_steam_art({"id": "steam-8870"}, retry))
            self.assertEqual(store.call_count, 3)                       # en espera de 24 h
        with mock.patch.object(oc, "cached_artwork_path", return_value=None), mock.patch.object(oc, "store_artwork") as store:
            self.assertTrue(service.sync_steam_art({"id": "steam-1"}, {}))
            self.assertEqual(store.call_count, 3)


if __name__ == "__main__":
    unittest.main()
