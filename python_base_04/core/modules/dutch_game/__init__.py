"""
Dutch Game Module

This module provides the core functionality for the Dutch card game,
including game logic, player management, and WebSocket communication.
"""

from .dutch_game_main import DutchGameMain
from .wins_level_rank_matcher import WinsLevelRankMatcher

__all__ = [
    'DutchGameMain',  # Main module class for auto-discovery
    'WinsLevelRankMatcher',
] 