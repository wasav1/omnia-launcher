import unittest
from unittest import mock

from omnia import online_catalog
from omnia.service import art_priority


class ArtPriorityTests(unittest.TestCase):
    def test_manual_pc_games_without_cover_are_prioritized(self):
        games = [{"id": "existing"}, {"id": "manual-limbo", "name": "Limbo", "src": "Manual", "platform": "pc"}]
        with mock.patch("omnia.service.Api._art", return_value={}):
            self.assertEqual([g["id"] for g in art_priority(games, {})], ["manual-limbo", "existing"])

    def test_manual_store_link_preserves_only_verified_pc_editions(self):
        game = {"name": "Limbo", "src": "Manual", "platform": "pc", "store_id": {"store": "epic", "id": "Hazelnut"}}
        self.assertEqual(online_catalog.manual_steam_appid(game), "48000")
        self.assertEqual(online_catalog.manual_steam_appid({**game, "store_id": {"store": "epic", "id": "OtraEdicion"}}), "")

    def test_unchecked_catalog_games_go_first_and_order_is_otherwise_stable(self):
        games = [{"id": "a", "catalogSlug": "old"}, {"id": "b"}, {"id": "c", "catalogSlug": "new"}, {"id": "d", "catalogSlug": "old2"}]
        state = {"catalog_art_checked": {"old": 100, "old2": 5}}
        self.assertEqual([g["id"] for g in art_priority(games, state)], ["c", "a", "b", "d"])

    def test_without_state_every_linked_game_is_unchecked(self):
        games = [{"id": "a"}, {"id": "b", "catalogSlug": "x"}]
        self.assertEqual([g["id"] for g in art_priority(games, {})], ["b", "a"])

    def test_steam_games_without_cached_art_go_before_the_rest(self):
        games = [{"id": "a", "catalogSlug": "old"}, {"id": "steam-1"}, {"id": "steam-2"}, {"id": "b", "catalogSlug": "old2"}]
        state = {"catalog_art_checked": {"old": 100, "old2": 5}}
        cached = lambda url: "/x.jpg" if "/apps/2/" in url else None         # el 2 ya tiene su arte, el 1 no
        with mock.patch("omnia.service.online_catalog.cached_artwork_path", side_effect=cached):
            self.assertEqual([g["id"] for g in art_priority(games, state)], ["steam-1", "a", "steam-2", "b"])


if __name__ == "__main__":
    unittest.main()
