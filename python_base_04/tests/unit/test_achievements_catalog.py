"""Unit tests for declarative achievements catalog."""

import unittest
from unittest.mock import patch

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
            special_event_id="cards_night",
            special_event_win_count_after=1,
        )
        self.assertIn("cards_night_winner", new_ids)
        nope = ac.compute_new_unlocks(
            0,
            set(),
            is_winner=False,
            special_event_id="cards_night",
            special_event_win_count_after=0,
        )
        self.assertNotIn("cards_night_winner", nope)

    def test_event_win_default_min_one(self):
        self.assertNotIn(
            "cards_night_winner",
            ac.compute_new_unlocks(
                0,
                set(),
                is_winner=True,
                special_event_id="cards_night",
                special_event_win_count_after=0,
            ),
        )
        self.assertIn(
            "cards_night_winner",
            ac.compute_new_unlocks(
                0,
                set(),
                is_winner=True,
                special_event_id="cards_night",
                special_event_win_count_after=1,
            ),
        )

    @patch.object(
        ac,
        "_ACHIEVEMENTS_ORDERED",
        (
            {
                "id": "lane_a_champion",
                "title": "Lane A",
                "description": "Win Lane A three times.",
                "unlock": {
                    "type": "event_win",
                    "special_event_id": "lane_a",
                    "min": 3,
                },
            },
        ),
    )
    def test_event_win_min_greater_than_one(self):
        self.assertNotIn(
            "lane_a_champion",
            ac.compute_new_unlocks(
                0,
                set(),
                is_winner=True,
                special_event_id="lane_a",
                special_event_win_count_after=2,
            ),
        )
        self.assertIn(
            "lane_a_champion",
            ac.compute_new_unlocks(
                0,
                set(),
                is_winner=True,
                special_event_id="lane_a",
                special_event_win_count_after=3,
            ),
        )

    def test_special_event_win_count_after_match(self):
        stored = {"home_game": 2}
        self.assertEqual(
            ac.special_event_win_count_after_match(
                stored, "home_game", is_winner=True
            ),
            3,
        )
        self.assertEqual(
            ac.special_event_win_count_after_match(
                stored, "home_game", is_winner=False
            ),
            2,
        )

    def test_total_wins_unlock(self):
        new_ids = ac.compute_new_unlocks(
            0,
            set(),
            is_winner=True,
            total_wins_after=1,
        )
        self.assertIn("first_blood", new_ids)
        self.assertNotIn("centurion", new_ids)
        cent = ac.compute_new_unlocks(
            0,
            set(),
            is_winner=True,
            total_wins_after=100,
        )
        self.assertIn("centurion", cent)

    def test_match_flag_empty_hand_from_win_type(self):
        flags = ac.match_flags_from_game_result_row(
            {"win_type": "empty_hand"},
            is_winner=True,
        )
        self.assertIn("empty_hand", flags)
        new_ids = ac.compute_new_unlocks(
            0,
            set(),
            is_winner=True,
            match_flags=flags,
        )
        self.assertIn("empty_hand", new_ids)

    def test_match_flag_dutch_called_requires_win(self):
        flags = ac.match_flags_from_game_result_row(
            {"dutch_called": True},
            is_winner=False,
        )
        self.assertIn("dutch_called", flags)
        no_win = ac.compute_new_unlocks(0, set(), is_winner=False, match_flags=flags)
        self.assertNotIn("called_dutch", no_win)
        with_win = ac.compute_new_unlocks(0, set(), is_winner=True, match_flags=flags)
        self.assertIn("called_dutch", with_win)

    def test_streak_three_and_ten(self):
        self.assertIn("win_streak_3", ac.compute_new_unlocks(3, set(), is_winner=True))
        self.assertIn("win_streak_10", ac.compute_new_unlocks(10, set(), is_winner=True))


if __name__ == "__main__":
    unittest.main()
