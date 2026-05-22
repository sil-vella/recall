"""Unit tests for period-wins leaderboard tie-break ordering (mirrors Mongo $sort)."""

import unittest


def _period_win_summary_sort_key(doc):
    """Same ordering as _period_wins_group_and_sort_stages $sort stage."""
    wins = int(doc.get("wins") or 0)
    period_points = int(doc.get("period_points") or 0)
    avg_ws = doc.get("avg_win_seconds")
    if avg_ws is None:
        pws = int(doc.get("period_win_seconds") or 0)
        avg_ws = (float(pws) / float(wins)) if wins > 0 else 999999999
    return (-wins, period_points, float(avg_ws), str(doc.get("_id", "")))


class TestPeriodWinsLeaderboardSort(unittest.TestCase):
    def test_more_wins_ranks_higher(self):
        rows = [
            {"_id": "a", "wins": 5, "period_points": 1, "avg_win_seconds": 1},
            {"_id": "b", "wins": 10, "period_points": 99, "avg_win_seconds": 99},
        ]
        ordered = sorted(rows, key=_period_win_summary_sort_key)
        self.assertEqual(ordered[0]["_id"], "b")

    def test_same_wins_lower_period_points_ranks_higher(self):
        rows = [
            {"_id": "high_pts", "wins": 10, "period_points": 20, "avg_win_seconds": 10},
            {"_id": "low_pts", "wins": 10, "period_points": 5, "avg_win_seconds": 10},
        ]
        ordered = sorted(rows, key=_period_win_summary_sort_key)
        self.assertEqual(ordered[0]["_id"], "low_pts")

    def test_same_wins_and_points_lower_avg_win_seconds_ranks_higher(self):
        rows = [
            {"_id": "slow", "wins": 10, "period_points": 5, "avg_win_seconds": 200},
            {"_id": "fast", "wins": 10, "period_points": 5, "avg_win_seconds": 50},
        ]
        ordered = sorted(rows, key=_period_win_summary_sort_key)
        self.assertEqual(ordered[0]["_id"], "fast")

    def test_derives_avg_from_period_win_seconds(self):
        rows = [
            {
                "_id": "b",
                "wins": 2,
                "period_points": 4,
                "period_win_seconds": 400,
            },
            {
                "_id": "a",
                "wins": 2,
                "period_points": 4,
                "period_win_seconds": 100,
            },
        ]
        ordered = sorted(rows, key=_period_win_summary_sort_key)
        self.assertEqual(ordered[0]["_id"], "a")


if __name__ == "__main__":
    unittest.main()
