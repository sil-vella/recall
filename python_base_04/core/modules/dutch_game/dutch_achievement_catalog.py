"""
Backward-compat re-exports for Dutch achievements.

Canonical implementation and JSON SSOT: achievements_catalog.py + config/achievements_config.json
"""

from __future__ import annotations

from .achievements_catalog import (
    ACHIEVEMENTS_CONFIG_DOCUMENT,
    ACHIEVEMENTS_CONFIG_REVISION,
    achievement_by_id,
    achievements_unlocked_ids_sorted,
    build_client_achievements_payload,
    compute_new_unlocks,
    next_win_streak,
    parse_stored_streak,
    unlocked_achievement_ids_from_dutch_game,
)

__all__ = [
    "ACHIEVEMENTS_CONFIG_DOCUMENT",
    "ACHIEVEMENTS_CONFIG_REVISION",
    "achievement_by_id",
    "achievements_unlocked_ids_sorted",
    "build_client_achievements_payload",
    "compute_new_unlocks",
    "next_win_streak",
    "parse_stored_streak",
    "unlocked_achievement_ids_from_dutch_game",
]
