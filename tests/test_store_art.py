import json
import shutil
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import online_catalog as oc
from omnia.games.heroic import HeroicDetector
from omnia.games.lutris import LutrisDetector, local_cover
from omnia.games.refresh import refresh
from omnia.service import art_priority
from omnia.store import Store

GOG = "https://images.gog.com/" + "a" * 64
EPIC = "https://cdn1.epicgames.com/salesEvent/salesEvent/c54f6d5f-2a48-41f9-9f36-38a441bdb535_1200x1600-8f81674351d5cbaa78be417ee078a80e"


class StoreArtUrlTests(unittest.TestCase):
    def test_only_exact_store_cdn_urls_are_accepted(self):
        good = {"art_square": GOG + ".jpg?namespace=gamesdb", "art_background": GOG + ".webp?namespace=gamesdb", "art_cover": EPIC}
        self.assertEqual(oc.store_art_from_heroic(good), {"portada": GOG + ".jpg?namespace=gamesdb", "fondo": GOG + ".webp?namespace=gamesdb"})
        self.assertEqual(oc.store_art_from_heroic({"art_square": EPIC, "art_cover": "https://cdn1.epicgames.com/x/16x9-abc"})["fondo"],
                         "https://cdn1.epicgames.com/x/16x9-abc")
        for bad in ("http://images.gog.com/" + "a" * 64, "https://evil.com/a.jpg", "https://images.gog.com.evil.com/" + "a" * 64,
                    "https://images.gog.com/x/../../a", "https://user@cdn1.epicgames.com/x", "file:///etc/passwd", "https://cdn1.epicgames.com/a b", None, 5):
            self.assertEqual(oc.store_art_from_heroic({"art_square": bad}), {}, bad)

    def test_download_accepts_store_art_but_not_other_hosts(self):
        class Resp:
            def __init__(self, url): self.url = url; self.headers = {"Content-Type": "image/jpeg"}
            def geturl(self): return self.url
            def read(self, n): return b"\xff\xd8x"
            def __enter__(self): return self
            def __exit__(self, *a): return False
        raw, mime = oc.download_artwork(EPIC, opener=lambda req, timeout=None: Resp(EPIC))
        self.assertEqual(mime, "image/jpeg")
        with self.assertRaises(oc.CatalogError):
            oc.download_artwork("https://evil.com/a.jpg", opener=lambda req, timeout=None: Resp("https://evil.com/a.jpg"))
        with self.assertRaises(oc.CatalogError):                       # redirección a otro host
            oc.download_artwork(EPIC, opener=lambda req, timeout=None: Resp("https://evil.com/a.jpg"))

    def test_game_art_urls_merges_steam_and_heroic_and_ignores_tampered_state(self):
        self.assertEqual(oc.game_art_urls({"id": "steam-1"}).keys(), {"portada", "fondo", "logo"})
        game = {"id": "heroic-gog-1", "art": {"remote": {"portada": GOG + ".jpg", "fondo": "https://evil.com/x", "logo": GOG}}}
        self.assertEqual(oc.game_art_urls(game), {"portada": GOG + ".jpg"})


class DetectorArtTests(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home, True)

    def test_heroic_games_carry_the_art_from_the_library_cache(self):
        cfg = self.home / ".config/heroic"
        (self.home / "g").mkdir()
        (cfg / "gog_store").mkdir(parents=True)
        (cfg / "store_cache").mkdir(parents=True)
        (cfg / "gog_store/installed.json").write_text(json.dumps({"installed": [{"appName": "1", "install_path": str(self.home / "g")}]}))
        (cfg / "store_cache/gog_library.json").write_text(json.dumps({"games": [
            {"app_name": "1", "title": "Dishonored 2", "art_square": GOG + ".jpg?namespace=gamesdb", "art_background": GOG + ".webp"}]}))
        game = HeroicDetector(self.home).detect()[0]
        self.assertEqual(game["art"]["remote"], {"portada": GOG + ".jpg?namespace=gamesdb", "fondo": GOG + ".webp"})
        self.assertEqual(game["art"]["sgdb"], "Dishonored 2")

    def test_lutris_uses_its_own_cover_but_never_a_symlink_or_a_weird_slug(self):
        root = self.home / ".local/share/lutris"
        (root / "coverart").mkdir(parents=True)
        (root / "coverart/doom.jpg").write_bytes(b"x")
        self.assertEqual(local_cover("doom", root), str(root / "coverart/doom.jpg"))
        (root / "coverart/link.jpg").symlink_to(root / "coverart/doom.jpg")
        self.assertEqual(local_cover("link", root), "")
        self.assertEqual(local_cover("../x", root), "")
        self.assertEqual(local_cover("nada", root), "")

    def test_lutris_detector_adds_the_cover_and_refresh_keeps_it_current(self):
        root = self.home / ".local/share/lutris"
        (root / "coverart").mkdir(parents=True)
        (root / "coverart/doom.jpg").write_bytes(b"x")
        (self.home / "doom").mkdir()
        con = sqlite3.connect(root / "pga.db")
        con.execute("CREATE TABLE games (id INTEGER, name TEXT, slug TEXT, runner TEXT, directory TEXT, installed INTEGER)")
        con.execute("INSERT INTO games VALUES (3,'Doom','doom','linux',?,1)", (str(self.home / "doom"),))
        con.commit(); con.close()
        det = LutrisDetector(db=root / "pga.db")
        self.assertEqual(det.detect()[0]["art"]["local"], {"portada": str(root / "coverart/doom.jpg")})
        store = Store(self.home / "cfg")
        refresh(store, [det])
        self.assertIn("local", store.games()[0]["art"])
        (root / "coverart/doom.jpg").unlink()                         # Lutris borró la carátula: Omnia deja de apuntarla
        refresh(store, [det])
        self.assertNotIn("local", store.games()[0]["art"])

    def test_heroic_games_without_cached_art_go_first(self):
        games = [{"id": "a", "catalogSlug": "x"}, {"id": "heroic-gog-1", "art": {"remote": {"portada": GOG + ".jpg"}}}]
        with mock.patch("omnia.service.online_catalog.cached_artwork_path", return_value=None):
            self.assertEqual(art_priority(games, {"catalog_art_checked": {"x": 5}})[0]["id"], "heroic-gog-1")


if __name__ == "__main__":
    unittest.main()
