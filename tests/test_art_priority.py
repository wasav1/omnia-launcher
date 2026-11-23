import unittest

from omnia.service import art_priority


class ArtPriorityTests(unittest.TestCase):
    def test_unchecked_catalog_games_go_first_and_order_is_otherwise_stable(self):
        games = [{"id": "a", "catalogSlug": "old"}, {"id": "b"}, {"id": "c", "catalogSlug": "new"}, {"id": "d", "catalogSlug": "old2"}]
        state = {"catalog_art_checked": {"old": 100, "old2": 5}}
        self.assertEqual([g["id"] for g in art_priority(games, state)], ["c", "a", "b", "d"])

    def test_without_state_every_linked_game_is_unchecked(self):
        games = [{"id": "a"}, {"id": "b", "catalogSlug": "x"}]
        self.assertEqual([g["id"] for g in art_priority(games, {})], ["b", "a"])


if __name__ == "__main__":
    unittest.main()
