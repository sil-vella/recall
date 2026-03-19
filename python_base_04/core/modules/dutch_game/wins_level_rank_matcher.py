"""
Wins → user level → rank (Dutch module).

Rules (product):
- Every ``WINS_PER_USER_LEVEL`` wins increases **user level** by 1 (level starts at 1).
- Every ``LEVELS_PER_RANK`` user levels increases **rank** by one step on ``RANK_HIERARCHY``.
- **Game table** tiers 1–4 (coin fee / room ``game_level``): table *T* requires
  ``user_level >= T`` (table 1 open to all levels ≥ 1).

Ranks match Flutter ``RankMatcher.rankHierarchy`` and
``tier_rank_level_matcher.RANK_HIERARCHY`` (duplicated below to avoid importing
user_management package __init__).
"""

from __future__ import annotations

from typing import Optional, Tuple

# Game table tiers (room game_level / LevelMatcher) — eligibility only
TABLE_LEVEL_MIN: int = 1
TABLE_LEVEL_MAX: int = 4

USER_LEVEL_MIN: int = 1

# Must stay identical to Flutter rank_matcher / tier_rank_level_matcher.
RANK_HIERARCHY: Tuple[str, ...] = (
    "beginner",
    "novice",
    "apprentice",
    "skilled",
    "advanced",
    "expert",
    "veteran",
    "master",
    "elite",
    "legend",
)

DEFAULT_RANK: str = "beginner"


class WinsLevelRankMatcher:
    """
    User **level** is progression from wins (unbounded). **Rank** is derived from
    user level. **Game table** access uses user level vs room ``game_level`` (1–4).
    """

    WINS_PER_USER_LEVEL: int = 10
    LEVELS_PER_RANK: int = 5

    @classmethod
    def wins_to_user_level(cls, wins: Optional[int]) -> int:
        """Lifetime wins → user level (1 + wins // step)."""
        w = 0 if wins is None else max(0, int(wins))
        step = max(1, cls.WINS_PER_USER_LEVEL)
        return max(USER_LEVEL_MIN, 1 + w // step)

    @classmethod
    def user_level_to_rank_index(cls, user_level: Optional[int]) -> int:
        """Index into RANK_HIERARCHY from user level; capped at legend."""
        if user_level is None:
            return 0
        try:
            lv = int(user_level)
        except (TypeError, ValueError):
            return 0
        lv = max(USER_LEVEL_MIN, lv)
        idx = (lv - 1) // max(1, cls.LEVELS_PER_RANK)
        return min(len(RANK_HIERARCHY) - 1, max(0, idx))

    @classmethod
    def user_level_to_rank(cls, user_level: Optional[int]) -> str:
        return RANK_HIERARCHY[cls.user_level_to_rank_index(user_level)]

    @classmethod
    def wins_to_rank(cls, wins: Optional[int]) -> str:
        return cls.user_level_to_rank(cls.wins_to_user_level(wins))

    @classmethod
    def user_may_join_game_table(cls, user_level: Optional[int], game_table_level: int) -> bool:
        """
        Table 1: any user with level ≥ 1.
        Table ``T`` in 2..4: requires ``user_level >= T``.
        Other ``game_table_level`` values: no gate (backward compatible).
        """
        try:
            t = int(game_table_level)
        except (TypeError, ValueError):
            return True
        if t < TABLE_LEVEL_MIN or t > TABLE_LEVEL_MAX:
            return True
        ul = USER_LEVEL_MIN if user_level is None else max(USER_LEVEL_MIN, int(user_level))
        return ul >= t
