"""
Queen Peek Power Card

This module defines the Queen Peek power card which allows a player
to look at any one card from any player's hand.
"""

from typing import Dict, Any, Optional
from .base_power_card import BasePowerCard
from ..card import Card


class QueenPeek(BasePowerCard):
    """Queen Peek power card - look at any one card from any player's hand"""
    