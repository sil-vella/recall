"""
Dutch game achievements: catalog + evaluation (server-side).

Add new rows to ACHIEVEMENT_CATALOG; at match end [update_game_stats] scans the list
and persists unlocks under modules.dutch_game.achievements.unlocked.<id>.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Set, Tuple


@dataclass(frozen=True)
class AchievementDef:
    id: str
    min_win_streak: int


# Ordered catalog — scanned end-to-end each stats update.
ACHIEVEMENT_CATALOG: Tuple[AchievementDef, ...] = (
    AchievementDef(id="win_streak_2", min_win_streak=2),
    AchievementDef(id="win_streak_5", min_win_streak=5),
)


def unlocked_achievement_ids_from_dutch_game(dutch_game: Dict[str, Any]) -> Set[str]:
    ach = dutch_game.get("achievements") or {}
    if not isinstance(ach, dict):
        return set()
    raw = ach.get("unlocked") or {}
    if not isinstance(raw, dict):
        return set()
    return {str(k) for k in raw.keys()}


def compute_new_unlocks(win_streak_after: int, already_unlocked: Set[str]) -> List[str]:
    """Return achievement ids newly earned this match (subset of catalog, stable order)."""
    out: List[str] = []
    for entry in ACHIEVEMENT_CATALOG:
        if entry.id in already_unlocked:
            continue
        if win_streak_after >= entry.min_win_streak:
            out.append(entry.id)
    return out


def achievements_unlocked_ids_sorted(dutch_game: Dict[str, Any]) -> List[str]:
    """Sorted list of unlocked ids for API clients."""
    keys = sorted(unlocked_achievement_ids_from_dutch_game(dutch_game))
    return keys


def next_win_streak(current_streak: int, is_winner: bool) -> int:
    if is_winner:
        return max(0, int(current_streak)) + 1
    return 0


def parse_stored_streak(raw: Any) -> int:
    try:
        v = int(raw)
    except (TypeError, ValueError):
        return 0
    return max(0, v)
