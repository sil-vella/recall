"""
Random Deck Factory for Recall Game

Builds a per-game shuffled deck with completely random card_ids.

Each game gets unique, unpredictable card IDs to ensure no patterns
can be exploited across different games.
"""

from typing import List, Optional
import random

from ..models.card import Card, CardDeck


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


