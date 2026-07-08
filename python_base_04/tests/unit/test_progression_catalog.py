"""Unit tests for declarative progression catalog."""

import unittest

from core.modules.dutch_game import progression_catalog as pc
from core.modules.dutch_game.wins_level_rank_matcher import WinsLevelRankMatcher


class TestProgressionCatalog(unittest.TestCase):
    def test_rank_hierarchy_length(self):
        self.assertGreaterEqual(len(pc.RANK_HIERARCHY), 1)

    def test_revision_is_hex(self):
        self.assertEqual(len(pc.PROGRESSION_CONFIG_REVISION), 64)

    def test_wins_to_level_default_step(self):
        self.assertEqual(WinsLevelRankMatcher.wins_to_user_level(0), 1)
        self.assertEqual(WinsLevelRankMatcher.wins_to_user_level(9), 1)
        self.assertEqual(WinsLevelRankMatcher.wins_to_user_level(10), 2)
        self.assertEqual(WinsLevelRankMatcher.wins_to_user_level(90), 10)
        self.assertEqual(WinsLevelRankMatcher.wins_to_user_level(1999), 54)
        self.assertEqual(WinsLevelRankMatcher.wins_to_user_level(2000), 55)

    def test_accelerating_wins_steps_sum_to_max(self):
        self.assertEqual(len(pc.WINS_PER_LEVEL_STEPS), 54)
        self.assertEqual(sum(pc.WINS_PER_LEVEL_STEPS), 2000)
        self.assertEqual(pc.CUMULATIVE_WINS_FOR_USER_LEVEL[-1], 2000)

    def test_user_level_to_rank_index(self):
        self.assertEqual(WinsLevelRankMatcher.user_level_to_rank_index(1), 0)
        self.assertEqual(WinsLevelRankMatcher.user_level_to_rank_index(5), 0)
        self.assertEqual(WinsLevelRankMatcher.user_level_to_rank_index(6), 1)
        self.assertEqual(
            WinsLevelRankMatcher.user_level_to_rank(6),
            pc.RANK_HIERARCHY[1],
        )

    def test_levels_per_rank_map(self):
        self.assertEqual(len(pc.LEVELS_PER_RANK_BY_RANK), len(pc.RANK_HIERARCHY))
        self.assertEqual(pc.levels_per_rank_for("beginner"), 5)

    def test_client_payload_has_schema(self):
        doc = pc.build_client_progression_payload()
        self.assertIn("rank_hierarchy", doc)
        self.assertIn("progression", doc)


if __name__ == "__main__":
    unittest.main()
