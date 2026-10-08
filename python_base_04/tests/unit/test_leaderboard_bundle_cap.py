"""Public leaderboard bundle cap and cache key stay compatible with older callers."""

import unittest

from bson import ObjectId

from core.modules.dutch_game.api_endpoints import (
    LEADERBOARD_BUNDLE_ABS_MAX,
    LEADERBOARD_BUNDLE_DEFAULT_MAX,
    _leaderboard_bundle_cache_key,
    _period_wins_match_filter,
)


class TestLeaderboardBundleCap(unittest.TestCase):
    def test_default_cap_is_100_and_explicit_cap_still_allowed(self):
        self.assertEqual(LEADERBOARD_BUNDLE_DEFAULT_MAX, 100)
        self.assertGreaterEqual(LEADERBOARD_BUNDLE_ABS_MAX, 2500)

    def test_cache_key_separates_game_type_history_and_size(self):
        plain = _leaderboard_bundle_cache_key(500, None, 0, 0)
        classic = _leaderboard_bundle_cache_key(500, "classic", 0, 0)
        history = _leaderboard_bundle_cache_key(80, None, 24, 5)
        self.assertEqual(plain, "leaderboard_bundle:all:500:hm0:hy0")
        self.assertNotEqual(plain, classic)
        self.assertNotEqual(plain, history)

    def test_user_filter_can_be_added_without_dropping_the_window(self):
        oid = ObjectId()
        only_user = _period_wins_match_filter(None, user_id=oid)
        self.assertEqual(only_user, {"user_id": oid})
        classic = _period_wins_match_filter("classic", user_id=oid)
        self.assertIn("$and", classic)
        self.assertIn({"user_id": oid}, classic["$and"])


if __name__ == "__main__":
    unittest.main()
