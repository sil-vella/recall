"""Unit tests for premium subscriber coin bonus."""
import unittest

from utils.dutch_game_credits import effective_coin_grant


class TestSubscriberCoinBonus(unittest.TestCase):
    def test_premium_eleven_percent(self):
        self.assertEqual(effective_coin_grant(700, "premium", 11), 777)

    def test_regular_no_bonus(self):
        self.assertEqual(effective_coin_grant(700, "regular", 11), 700)

    def test_promotional_no_bonus(self):
        self.assertEqual(effective_coin_grant(100, "promotional", 11), 100)

    def test_zero_bonus_percent(self):
        self.assertEqual(effective_coin_grant(500, "premium", 0), 500)


if __name__ == "__main__":
    unittest.main()
