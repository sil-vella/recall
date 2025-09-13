"""
Power Card Manager

This module manages all power cards in the Recall game.
It loads power card classes and provides access to them.
"""

from typing import Dict, Any, Optional, Type
from .base_power_card import BasePowerCard
from .queen_peek import QueenPeek
from ...game_logic.game_state import GameState


class PowerCardManager:
    """Manages all power cards in the game"""
    
    def __init__(self, game_state: GameState):
        self.game_state = game_state
        self.power_cards = {}
        self._register_power_cards()
    
    def _register_power_cards(self):
        """Register all available power cards"""
        self.power_cards = {
            "queen_peek": QueenPeek,
            # Add more power cards here as they are created
            # "jack_switch": JackSwitch,
            # "joker_wild": JokerWild,
            # etc.
        }
    