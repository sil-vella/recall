"""
Base Power Card Class

This module defines the base class for all power cards in the Recall game.
Each power card extends this class and implements its own special logic.
"""

from abc import ABC, abstractmethod
from typing import Dict, Any, Optional
from ...game_logic.game_state import GameState
from ..player import Player


class BasePowerCard(ABC):
    """Base class for all power cards"""
    
    def __init__(self, game_state: GameState):
        self.game_state = game_state
        self.card_name = self.__class__.__name__.lower()

    def update_decks(self) -> Dict[str, Any]:
        """Update the draw and discard piles"""

    
    def update_computer_players(self) -> Dict[str, Any]:
        """Update computer player information"""
        # purpose is to update the computer players' data like hand/known from other players/points etc etc by calling the player class methods