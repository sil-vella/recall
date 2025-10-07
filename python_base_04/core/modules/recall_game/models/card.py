"""
Card Models for Recall Game

This module defines the card system for the Recall card game,
including standard cards, special power cards, and point calculations.
"""

from typing import Optional, List, Dict, Any
from enum import Enum


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
    """Represents a single card in the Recall game
    
    Note: card_id is required and should be generated using DeckFactory
    for deterministic, game-specific IDs.
    """
    
    def __init__(self, card_id: str, rank: Optional[str] = None, suit: Optional[str] = None, 
                 points: Optional[int] = None, special_power: Optional[str] = None):
        if card_id is None:
            raise ValueError("card_id is required")
        self.card_id = card_id
        self.rank = rank
        self.suit = suit
        self.points = points
        self.special_power = special_power
        self.owner_id = None     # Player who owns this card
    
    def __str__(self):
        if self.rank is None or self.suit is None:
            return f"Card {self.card_id}"
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
            "owner_id": self.owner_id
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Card':
        """Create card from dictionary"""
        card = cls(
            card_id=data.get("card_id"),
            rank=data.get("rank"),
            suit=data.get("suit"),
            points=data.get("points"),
            special_power=data.get("special_power")
        )
        card.owner_id = data.get("owner_id")
        return card
    
    def get_point_value(self) -> int:
        """Get the point value of this card"""
        return self.points or 0
    
    def has_special_power(self) -> bool:
        """Check if this card has a special power"""
        return self.special_power is not None
    

class CardDeck:
    """Represents a deck of cards for the Recall game
    
    Note: This class creates cards with temporary IDs. Use DeckFactory
    to create properly shuffled decks with deterministic card IDs.
    """
    
    def __init__(self, include_jokers: bool = True):
        self.cards = []
        self.include_jokers = include_jokers
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
                # Temporary ID - will be replaced by DeckFactory
                card_id = f"temp-{rank}-{suit}"
                card = Card(card_id, rank, suit, points, special_power)
                self.cards.append(card)
        
        # Add Jokers (0 points)
        if self.include_jokers:
            for i in range(2):  # 2 jokers
                card_id = f"temp-joker-{i}"
                card = Card(card_id, "joker", "joker", 0, None)
                self.cards.append(card)
        

    
    def _get_point_value(self, rank: str, suit: str) -> int:
        """Get the point value for a card"""
        if rank == "joker":
            return 0
        elif rank == "ace":
            return 1
        elif rank in ["2", "3", "4", "5", "6", "7", "8", "9", "10"]:
            return int(rank)
        elif rank in ["jack", "queen", "king"]:
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
    

    
    def shuffle(self):
        """Shuffle the deck - Note: Use DeckFactory for deterministic shuffling"""
        import random
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