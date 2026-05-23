"""Unit tests for special-event match economics helpers."""

import unittest

from core.modules.dutch_game import table_tiers_catalog as tt


class TestSpecialEventEconomics(unittest.TestCase):
    def test_cards_night_fee_and_reward(self):
        self.assertEqual(tt.special_event_coin_fee("cards_night"), 25)
        self.assertEqual(tt.special_event_reward_coins("cards_night"), 50)
        self.assertEqual(tt.special_event_min_user_level("cards_night"), 1)

    def test_the_challenger_fee(self):
        self.assertEqual(tt.special_event_coin_fee("the_challenger"), 30)
        self.assertEqual(tt.special_event_reward_coins("the_challenger"), 60)

    def test_compute_match_pot_includes_reward_bonus(self):
        pot = tt.compute_match_pot(
            coin_cost_per_player=25,
            active_player_count=4,
            reward_coins_bonus=50,
        )
        self.assertEqual(pot, 150)


if __name__ == "__main__":
    unittest.main()
