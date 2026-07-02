"""Unit tests for leaderboard placement achievement processor."""

import unittest
from unittest.mock import MagicMock, patch

from core.modules.dutch_game import achievements_catalog as ac
from core.modules.dutch_game import leaderboard_achievement_processor as lb


class TestPlacementForRank(unittest.TestCase):
    def test_boundaries(self):
        self.assertEqual(ac.placement_for_rank(1), "first")
        self.assertEqual(ac.placement_for_rank(3), "third")
        self.assertEqual(ac.placement_for_rank(4), "top_10")
        self.assertEqual(ac.placement_for_rank(10), "top_10")
        self.assertEqual(ac.placement_for_rank(11), "top_50")
        self.assertEqual(ac.placement_for_rank(50), "top_50")
        self.assertEqual(ac.placement_for_rank(51), "top_100")
        self.assertEqual(ac.placement_for_rank(100), "top_100")
        self.assertIsNone(ac.placement_for_rank(101))


class TestAchievementIdForPlacement(unittest.TestCase):
    def test_monthly_tiered(self):
        aid = ac.achievement_id_for_leaderboard_placement(
            period="monthly",
            game_type="classic",
            placement="first",
            rank_tier="novice",
        )
        self.assertEqual(aid, "lb_monthly_classic_novice_first")

    def test_alltime_global(self):
        aid = ac.achievement_id_for_leaderboard_placement(
            period="all_time",
            game_type="clear_and_collect",
            placement="top_50",
        )
        self.assertEqual(aid, "lb_alltime_cc_top_50")


class TestFormatPeriodLabel(unittest.TestCase):
    def test_monthly_label(self):
        self.assertEqual(ac.format_leaderboard_period_label("monthly", "2025-06"), "June 2025")


class TestLeaderboardCatalogNormalization(unittest.TestCase):
    def test_leaderboard_entries_loaded(self):
        doc = ac.build_client_achievements_payload()
        lb = [
            a
            for a in doc.get("achievements", [])
            if (a.get("unlock") or {}).get("type") == "leaderboard_placement"
        ]
        self.assertGreaterEqual(len(lb), 252)

    def test_alltime_not_repeatable(self):
        entry = ac.achievement_by_id("lb_alltime_classic_first")
        self.assertIsNotNone(entry)
        unlock = entry.get("unlock") or {}
        self.assertEqual(unlock.get("period"), "all_time")
        self.assertFalse(unlock.get("repeatable"))


class TestProcessScopeIdempotency(unittest.TestCase):
    @patch.object(lb, "_is_scope_processed", return_value=True)
    def test_skips_processed_scope(self, _mock):
        app = MagicMock()
        db = MagicMock()
        n = lb.process_period_scope(
            app,
            db,
            period="monthly",
            period_key="2025-01",
            start=MagicMock(),
            end=MagicMock(),
            game_type="classic",
            rank_tier="novice",
        )
        self.assertEqual(n, 0)


if __name__ == "__main__":
    unittest.main()
