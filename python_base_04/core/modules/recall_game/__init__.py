"""
Recall Game Module

This module provides the core functionality for the Recall card game,
including game logic, player management, and WebSocket communication.
"""

# Note: Python model classes will be imported here when they are created
# from .models.player import Player, HumanPlayer, ComputerPlayer
# from .models.card import Card, CardDeck
# from .game_logic.game_state import GameState, GameStateManager
from .recall_game_main import RecallGameMain

__all__ = [
    'RecallGameMain',  # Main module class for auto-discovery
] 