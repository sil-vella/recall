"""
Game Actions for Recall Game

This module handles all game actions and logic during gameplay,
including card playing, drawing, special powers, and turn management.
"""

from typing import List, Dict, Any, Optional
from datetime import datetime
import time
from ..models.card import Card
from ..models.player import Player, PlayerStatus
from .game_state import GameState, GamePhase
from tools.logger.custom_logging import custom_log


class GameActions:
    """Handles all game actions and logic during gameplay"""
    
    def __init__(self, game_state: GameState):
        self.game_state = game_state
    
    def end_game(self) -> Dict[str, Any]:
        """End the game and determine winner"""
        # Allow scoring at recall or immediate end
        if self.game_state.phase not in (GamePhase.RECALL_CALLED, GamePhase.GAME_ENDED, GamePhase.PLAYER_TURN, GamePhase.OUT_OF_TURN_PLAY):
            return {"error": "Invalid phase for ending game"}
        return self._end_game_with_scoring()

    # Note: start_game method logic moved to GameStateManager.on_start_match()
    # as part of consolidating the start match flow

    # ========= Private Helper Methods =========
    
    # Note: _deal_cards and _setup_piles methods moved to GameStateManager
    # as part of consolidating the start match flow
    
