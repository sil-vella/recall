"""
Dutch Game Module

This module provides the core functionality for the Dutch card game,
including game logic, player management, and WebSocket communication.

``WinsLevelRankMatcher`` is loaded lazily (``__getattr__``) to avoid a circular
import with ``user_management_module.tier_rank_level_matcher`` (which imports
``table_tiers_catalog`` from this package).
"""

from .dutch_game_main import DutchGameMain

__all__ = [
    "DutchGameMain",  # Main module class for auto-discovery
    "WinsLevelRankMatcher",
]


def __getattr__(name: str):
    if name == "WinsLevelRankMatcher":
        from .wins_level_rank_matcher import WinsLevelRankMatcher as _WinsLevelRankMatcher

        return _WinsLevelRankMatcher
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")