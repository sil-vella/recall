"""
Card Models for Recall Game

This module defines the card system for the Recall card game,
including standard cards, special power cards, and point calculations.
"""

from typing import Optional, List, Dict, Any
from enum import Enum
import random


class CardSuit(Enum):
    """Card suits"""
    HEARTS = "hearts"
    DIAMONDS = "diamonds"
    CLUBS = "clubs"
    SPADES = "spades"


class CardRank(Enum):
    """Card ranks with their point values"""
    JOKER = "joker"
    ACE = "ace"
    TWO = "2"
    THREE = "3"
    FOUR = "4"
    FIVE = "5"
    SIX = "6"
    SEVEN = "7"
    EIGHT = "8"
    NINE = "9"
    TEN = "10"
    JACK = "jack"
    QUEEN = "queen"
    KING = "king"


class SpecialPowerType(Enum):
    """Special power card types"""
    PEEK_AT_CARD = "peek_at_card"  # Queen
    SWITCH_CARDS = "switch_cards"   # Jack
    STEAL_CARD = "steal_card"       # Added power card
    DRAW_EXTRA = "draw_extra"       # Added power card
    PROTECT_CARD = "protect_card"   # Added power card


class Card:
    """Represents a single card in the Recall game"""
    
    def __init__(self, rank: str, suit: str, points: int, 
                 special_power: Optional[str] = None, card_id: Optional[str] = None):
        self.rank = rank
        self.suit = suit
        self.points = points
        self.special_power = special_power
        self.card_id = card_id or f"{rank}_{suit}_{random.randint(1000, 9999)}"
        self.is_visible = False  # Whether the card is face up
        self.owner_id = None     # Player who owns this card
    
    def __str__(self):
        if self.rank == "joker":
            return "Joker"
        return f"{self.rank.title()} of {self.suit.title()}"
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert card to dictionary representation"""
        return {
            "card_id": self.card_id,
            "rank": self.rank,
            "suit": self.suit,
            "points": self.points,
            "special_power": self.special_power,
            "is_visible": self.is_visible,
            "owner_id": self.owner_id
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Card':
        """Create card from dictionary"""
        card = cls(
            rank=data["rank"],
            suit=data["suit"],
            points=data["points"],
            special_power=data.get("special_power"),
            card_id=data.get("card_id")
        )
        card.is_visible = data.get("is_visible", False)
        card.owner_id = data.get("owner_id")
        return card
    
    def get_point_value(self) -> int:
        """Get the point value of this card"""
        return self.points
    
    def has_special_power(self) -> bool:
        """Check if this card has a special power"""
        return self.special_power is not None
    
    def can_play_out_of_turn(self, played_card: 'Card') -> bool:
        """Check if this card can be played out of turn"""
        return self.rank == played_card.rank


class CardDeck:
    """Represents a deck of cards for the Recall game"""
    
    def __init__(self, include_jokers: bool = True, include_special_powers: bool = True):
        self.cards = []
        self.include_jokers = include_jokers
        self.include_special_powers = include_special_powers
        self._initialize_deck()
    
    def _initialize_deck(self):
        """Initialize the deck with all cards"""
        # Standard 52-card deck
        suits = ["hearts", "diamonds", "clubs", "spades"]
        ranks = ["ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "jack", "queen", "king"]
        
        # Add standard cards
        for suit in suits:
            for rank in ranks:
                points = self._get_point_value(rank, suit)
                special_power = self._get_special_power(rank)
                card = Card(rank, suit, points, special_power)
                self.cards.append(card)
        
        # Add Jokers (0 points)
        if self.include_jokers:
            for i in range(2):  # 2 jokers
                card = Card("joker", "joker", 0, None)
                self.cards.append(card)
        
        # Add special power cards (if enabled)
        if self.include_special_powers:
            self._add_special_power_cards()
    
    def _get_point_value(self, rank: str, suit: str) -> int:
        """Get the point value for a card"""
        if rank == "joker":
            return 0
        elif rank == "ace":
            return 1
        elif rank in ["2", "3", "4", "5", "6", "7", "8", "9", "10"]:
            return int(rank)
        elif rank in ["jack", "queen"]:
            return 10
        elif rank == "king":
            # Red kings (hearts, diamonds) are 0 points
            if suit in ["hearts", "diamonds"]:
                return 0
            else:
                return 10
        else:
            return 0
    
    def _get_special_power(self, rank: str) -> Optional[str]:
        """Get special power for a card"""
        if rank == "queen":
            return "peek_at_card"
        elif rank == "jack":
            return "switch_cards"
        else:
            return None
    
    def _add_special_power_cards(self):
        """Add special power cards to the deck"""
        special_powers = [
            ("steal_card", 5),
            ("draw_extra", 3),
            ("protect_card", 4),
            ("skip_turn", 6),
            ("double_points", 8)
        ]
        
        for power, points in special_powers:
            # Create special power cards with unique suits
            for i in range(2):  # 2 of each special power
                card = Card(f"power_{power}", f"special_{i}", points, power)
                self.cards.append(card)
    
    def shuffle(self):
        """Shuffle the deck"""
        random.shuffle(self.cards)
    
    def draw_card(self) -> Optional[Card]:
        """Draw a card from the top of the deck"""
        if self.cards:
            return self.cards.pop()
        return None
    
    def add_card(self, card: Card):
        """Add a card to the deck"""
        self.cards.append(card)
    
    def get_remaining_count(self) -> int:
        """Get the number of cards remaining in the deck"""
        return len(self.cards)
    
    def is_empty(self) -> bool:
        """Check if the deck is empty"""
        return len(self.cards) == 0
    
    def reset(self):
        """Reset the deck to its original state"""
        self.cards = []
        self._initialize_deck() 