"""
Wins → user level → rank (Dutch module).

Rules loaded from progression_catalog (config/progression_config.json).
"""

from __future__ import annotations

from typing import Optional
from core.modules.user_management_module import tier_rank_level_matcher as matcher
from core.modules.dutch_game import progression_catalog as pc

# Game table tiers (room game_level / LevelMatcher) — eligibility only
TABLE_LEVEL_MIN: int = min(matcher.LEVEL_ORDER) if matcher.LEVEL_ORDER else 1
TABLE_LEVEL_MAX: int = max(matcher.LEVEL_ORDER) if matcher.LEVEL_ORDER else 4

USER_LEVEL_MIN: int = pc.USER_LEVEL_MIN
RANK_HIERARCHY = pc.RANK_HIERARCHY
DEFAULT_RANK: str = pc.DEFAULT_RANK


class WinsLevelRankMatcher:
    """
    User **level** is progression from wins (unbounded). **Rank** is derived from
    user level. **Game table** access uses user level vs room ``game_level`` (1–4).
    """

    WINS_PER_USER_LEVEL: int = pc.WINS_PER_USER_LEVEL
    LEVELS_PER_RANK: int = pc.LEVELS_PER_RANK

    @classmethod
    def wins_to_user_level(cls, wins: Optional[int]) -> int:
        """Lifetime wins → user level (1 + wins // step)."""
        w = 0 if wins is None else max(0, int(wins))
        step = max(1, cls.WINS_PER_USER_LEVEL)
        return max(USER_LEVEL_MIN, 1 + w // step)

    @classmethod
    def user_level_to_rank_index(cls, user_level: Optional[int]) -> int:
        """Index into RANK_HIERARCHY from user level; per-rank spans from progression catalog."""
        return pc.user_level_to_rank_index(user_level)

    @classmethod
    def user_level_to_rank(cls, user_level: Optional[int]) -> str:
        return pc.user_level_to_rank(user_level)

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
        if t not in matcher.LEVEL_TO_TITLE:
            return True
        ul = USER_LEVEL_MIN if user_level is None else max(USER_LEVEL_MIN, int(user_level))
        required = matcher.table_level_to_required_user_level(t, default_level=t)
        return ul >= required
