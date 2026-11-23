import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import online_catalog, service
from omnia.store import Store


class SearchCandidatesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.store = Store(self.tmp)
        self.store.set_games([
            {"id": "a", "name": "Banjo-Kazooie", "platform": "n64", "ports": []},
            {"id": "b", "name": "Ya enlazada", "platform": "n64", "catalogSlug": "ya", "ports": []},
        ])
        self.store.state["catalog_platforms"] = {"ya": ["n64"]}

    def test_finds_catalog_entries_outside_the_first_pages(self):
        found = {"items": [{"slug": "banjo-kazooie", "name": "Banjo-Kazooie", "platforms": [{"slug": "n64"}]}]}
        with mock.patch.object(online_catalog, "list_games", return_value=found) as listing:
            items = service.search_candidates(self.store, [{"slug": "otra", "name": "Otra"}])
        self.assertEqual({i["slug"] for i in items}, {"otra", "banjo-kazooie"})
        listing.assert_called_once()                                   # solo el juego sin ficha válida se busca
        self.assertEqual(listing.call_args.args[0]["q"], "Banjo-Kazooie")
        self.assertEqual(service.auto_link_catalog(self.store, items), 1)
        self.assertEqual({g["id"]: g.get("catalogSlug") for g in self.store.games()}, {"a": "banjo-kazooie", "b": "ya"})

    def test_finds_a_title_whose_official_name_has_a_colon(self):
        self.store.set_games([{"id": "n", "name": "The Legend of Zelda Ocarina of Time", "platform": "sw2", "ports": []}])
        catalog = {"items": [{"slug": "ocarina-sw2", "name": "The Legend of Zelda: Ocarina of Time", "platforms": [{"slug": "switch2"}]}]}

        def listing(query):
            return catalog if query["q"] == "Ocarina of Time" else {"items": []}      # la frase completa no existe en el catálogo
        with mock.patch.object(online_catalog, "list_games", side_effect=listing) as called:
            items = service.search_candidates(self.store, [])
        self.assertIn("ocarina-sw2", {i["slug"] for i in items})
        queries = [c.args[0]["q"] for c in called.call_args_list]
        self.assertEqual(queries[0], "The Legend of Zelda Ocarina of Time")            # primero el nombre completo
        self.assertIn("Ocarina of Time", queries)
        self.assertEqual(service.auto_link_catalog(self.store, items), 1)
        self.assertEqual(self.store.games()[0]["catalogSlug"], "ocarina-sw2")

    def test_survives_a_catalog_error(self):
        with mock.patch.object(online_catalog, "list_games", side_effect=online_catalog.CatalogError("sin red")):
            items = service.search_candidates(self.store, [{"slug": "otra"}])
        self.assertEqual(items, [{"slug": "otra"}])


if __name__ == "__main__":
    unittest.main()
