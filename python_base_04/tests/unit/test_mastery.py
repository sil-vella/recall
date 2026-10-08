"""Unit tests for per-match mastery."""

import unittest

from core.modules.dutch_game.mastery import (
    estimated_mastery_from_wins_and_points,
    match_mastery_delta,
)


class TestMatchMasteryDelta(unittest.TestCase):
    def test_both_jokers_is_the_top_finish(self):
        self.assertEqual(match_mastery_delta(0, 2), 252)

    def test_empty_hand(self):
        self.assertEqual(match_mastery_delta(0, 0), 202)

    def test_one_joker(self):
        self.assertEqual(match_mastery_delta(0, 1), 201)

    def test_one_queen_or_ten(self):
        self.assertEqual(match_mastery_delta(10, 1), 151)

    def test_four_kings(self):
        self.assertEqual(match_mastery_delta(40, 4), 0)

    def test_points_dominate_cards(self):
        heavier_points = match_mastery_delta(1, 0)
        lighter_points_more_cards = match_mastery_delta(0, 3)
        self.assertGreater(lighter_points_more_cards, heavier_points)

    def test_caps_and_negatives(self):
        self.assertEqual(match_mastery_delta(50, 6), 0)
        self.assertEqual(match_mastery_delta(-3, -1), 202)


class TestEstimatedMasterySeed(unittest.TestCase):
    def test_no_wins(self):
        self.assertEqual(estimated_mastery_from_wins_and_points(0, 0), 0)

    def test_clean_win_matches_empty_hand(self):
        self.assertEqual(estimated_mastery_from_wins_and_points(1, 0), 202)

    def test_ten_points_counts_one_card(self):
        self.assertEqual(estimated_mastery_from_wins_and_points(1, 10), 151)

    def test_points_spread_across_wins_count_min_cards(self):
        # 24 points need at least 3 cards (10+10+4). Two empty-hand wins would be 404.
        self.assertEqual(estimated_mastery_from_wins_and_points(2, 24), 282)

    def test_zero_points_stays_empty_hands(self):
        self.assertEqual(estimated_mastery_from_wins_and_points(3, 0), 606)

    def test_heavy_points_clamp_at_zero(self):
        self.assertEqual(estimated_mastery_from_wins_and_points(1, 100), 0)
