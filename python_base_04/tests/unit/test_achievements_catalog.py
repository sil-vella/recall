"""Unit tests for declarative achievements catalog."""

import unittest

from core.modules.dutch_game import achievements_catalog as ac


class TestAchievementsCatalog(unittest.TestCase):
    def test_revision_is_hex(self):
        self.assertEqual(len(ac.ACHIEVEMENTS_CONFIG_REVISION), 64)

    def test_client_payload_has_achievements(self):
        doc = ac.build_client_achievements_payload()
        self.assertIn("achievements", doc)
        self.assertIsInstance(doc["achievements"], list)
        self.assertGreaterEqual(len(doc["achievements"]), 1)

    def test_streak_unlock_threshold(self):
        # Default shipped JSON includes win_streak_2 at min 2
        new_ids = ac.compute_new_unlocks(2, set(), is_winner=True)
        self.assertIn("win_streak_2", new_ids)
        new_again = ac.compute_new_unlocks(3, {"win_streak_2"}, is_winner=True)
        self.assertNotIn("win_streak_2", new_again)

    def test_event_win_only_when_winner_and_event_matches(self):
        new_ids = ac.compute_new_unlocks(
            0,
            set(),
            is_winner=True,
            special_event_id="winter_duels",
        )
        self.assertIn("winter_duels_winner", new_ids)
        nope = ac.compute_new_unlocks(
            0,
            set(),
            is_winner=False,
            special_event_id="winter_duels",
        )
        self.assertNotIn("winter_duels_winner", nope)


if __name__ == "__main__":
    unittest.main()
