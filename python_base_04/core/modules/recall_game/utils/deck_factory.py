"""
Random Deck Factory for Recall Game

Builds a per-game shuffled deck with completely random card_ids.

Each game gets unique, unpredictable card IDs to ensure no patterns
can be exploited across different games.
"""

from typing import List, Optional
import random

from ..models.card import Card, CardDeck

# Testing switch - set to True for testing deck with more special cards
TESTING_SWITCH = True


class DeckFactory:
    """Creates a deck with completely random card IDs for a given game_id.

    - Assigns random card_id: Unique random string for each card
    - Shuffles deck randomly
    - No deterministic patterns or reproducible seeds
    """

    def __init__(self, game_id: str, seed: Optional[int] = None):
        self.game_id = game_id
        # Use completely random generation - no deterministic seeds
        # seed parameter is ignored to ensure complete randomness
        
    def _generate_random_card_id(self) -> str:
        """Generate a completely random card ID"""
        import uuid
        import string
        
        # Generate a random 12-character alphanumeric string
        chars = string.ascii_letters + string.digits
        random_part = ''.join(random.choice(chars) for _ in range(12))
        
        # Add a timestamp component for additional uniqueness
        import time
        timestamp_part = str(int(time.time() * 1000000))[-8:]  # Last 8 digits of microsecond timestamp
        
        return f"card_{random_part}_{timestamp_part}"

    def build_deck(
        self,
        include_jokers: bool = True,
    ) -> List[Card]:
        deck = CardDeck(
            include_jokers=include_jokers,
        )

        # Assign completely random IDs to each card
        for card in deck.cards:
            card.card_id = self._generate_random_card_id()

        # Random shuffle using system random (no seed)
        random.shuffle(deck.cards)
        return deck.cards


class TestingDeckFactory:
    """Creates a testing deck with more Queens and Jacks for easier special card testing.
    
    This factory generates a deck with:
    - More Queens and Jacks (special cards)
    - Fewer numbered cards (2-10)
    - Same Kings and Aces as normal deck
    - Same Jokers as normal deck
    """

    def __init__(self, game_id: str, seed: Optional[int] = None):
        self.game_id = game_id
        # Use completely random generation - no deterministic seeds
        # seed parameter is ignored to ensure complete randomness
        
    def _generate_random_card_id(self) -> str:
        """Generate a completely random card ID"""
        import uuid
        import string
        
        # Generate a random 12-character alphanumeric string
        chars = string.ascii_letters + string.digits
        random_part = ''.join(random.choice(chars) for _ in range(12))
        
        # Add a timestamp component for additional uniqueness
        import time
        timestamp_part = str(int(time.time() * 1000000))[-8:]  # Last 8 digits of microsecond timestamp
        
        return f"card_{random_part}_{timestamp_part}"

    def build_deck(
        self,
        include_jokers: bool = True,
    ) -> List[Card]:
        """Build a testing deck with more special cards (Queens and Jacks)"""
        cards = []
        
        # Standard suits
        suits = ['hearts', 'diamonds', 'clubs', 'spades']
        
        # Testing deck composition:
        # - More Queens and Jacks (4 of each suit = 16 total)
        # - Fewer numbered cards (only 3-5 of each suit = 12 total)
        # - Same Kings and Aces (4 of each suit = 8 total)
        # - Same Jokers (2 total)
        
        for suit in suits:
            # Add more Queens (4 per suit)
            for _ in range(4):
                card = Card(self._generate_random_card_id(), 'queen', suit, 10, 'queen_peek')
                cards.append(card)
            
            # Add more Jacks (4 per suit)
            for _ in range(4):
                card = Card(self._generate_random_card_id(), 'jack', suit, 10, 'jack_swap')
                cards.append(card)
            
            # Add fewer numbered cards (only 3, 4, 5)
            for rank in ['3', '4', '5']:
                points = int(rank)
                card = Card(self._generate_random_card_id(), rank, suit, points, None)
                cards.append(card)
            
            # Add Kings (4 per suit)
            card = Card(self._generate_random_card_id(), 'king', suit, 10, None)
            cards.append(card)
            
            # Add Aces (4 per suit)
            card = Card(self._generate_random_card_id(), 'ace', suit, 1, None)
            cards.append(card)
        
        # Add Jokers if requested
        if include_jokers:
            for _ in range(2):
                card = Card(self._generate_random_card_id(), 'joker', 'none', 0, None)
                cards.append(card)
        
        # Random shuffle using system random (no seed)
        random.shuffle(cards)
        return cards


def get_deck_factory(game_id: str, seed: Optional[int] = None):
    """Factory function that returns the appropriate deck factory based on TESTING_SWITCH"""
    if TESTING_SWITCH:
        return TestingDeckFactory(game_id, seed)
    else:
        return DeckFactory(game_id, seed)


