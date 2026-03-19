"""
Wins → progression level → rank (Dutch module).

Ranks are identical in order and spelling to Flutter `RankMatcher.rankHierarchy`
(`flutter_base_05/lib/modules/dutch_game/backend_core/utils/rank_matcher.dart`)
and to the duplicated ``RANK_HIERARCHY`` below (same as ``tier_rank_level_matcher``).

Progression levels are 1..N where N == len(RANK_HIERARCHY) (10). They are
**not** the same as game table levels (1–4 / LevelMatcher); they only drive
rank-from-wins math until interception logic is wired.

No I/O and no persistence — pure matcher for use after stats updates.
"""

from __future__ import annotations

from typing import Optional, Tuple

# Must stay identical to:
# - Flutter: lib/modules/dutch_game/backend_core/utils/rank_matcher.dart → rankHierarchy
# - Python: core/modules/user_management_module/tier_rank_level_matcher.py → RANK_HIERARCHY
# Duplicated here so this module does not import user_management (package __init__ loads DB stack).
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


PROGRESSION_LEVEL_MIN: int = 1
PROGRESSION_LEVEL_MAX: int = len(RANK_HIERARCHY)


class WinsLevelRankMatcher:
    """
    Map lifetime wins to a progression level, then to the rank string for that level.

    Default curve: each additional rank tier requires ``WINS_PER_PROGRESSION_LEVEL``
    more wins than the previous (level 1 from 0 wins).
    """

    #: Wins per tier step: level L requires at least ``(L - 1) * WINS_PER_PROGRESSION_LEVEL`` wins.
    WINS_PER_PROGRESSION_LEVEL: int = 5

    @classmethod
    def wins_to_progression_level(cls, wins: Optional[int]) -> int:
        """
        Map non-negative win count to progression level in ``PROGRESSION_LEVEL_MIN..PROGRESSION_LEVEL_MAX``.

        Negative ``wins`` is treated as 0.
        """
        w = 0 if wins is None else max(0, int(wins))
        step = max(1, cls.WINS_PER_PROGRESSION_LEVEL)
        # 0 wins -> level 1; each `step` wins bumps one level until cap.
        raw = w // step + 1
        return min(PROGRESSION_LEVEL_MAX, max(PROGRESSION_LEVEL_MIN, raw))

    @classmethod
    def progression_level_to_rank(cls, progression_level: Optional[int]) -> str:
        """
        Map progression level (1-based) to rank string from ``RANK_HIERARCHY``.

        Out-of-range values clamp to nearest valid rank; ``None`` -> ``DEFAULT_RANK``.
        """
        if progression_level is None:
            return DEFAULT_RANK
        try:
            lvl = int(progression_level)
        except (TypeError, ValueError):
            return DEFAULT_RANK
        idx = lvl - 1
        if idx < 0:
            return RANK_HIERARCHY[0]
        if idx >= len(RANK_HIERARCHY):
            return RANK_HIERARCHY[-1]
        return RANK_HIERARCHY[idx]

    @classmethod
    def wins_to_rank(cls, wins: Optional[int]) -> str:
        """Compose ``wins_to_progression_level`` then ``progression_level_to_rank``."""
        return cls.progression_level_to_rank(cls.wins_to_progression_level(wins))
