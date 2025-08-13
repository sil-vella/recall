"""
Deterministic Deck Factory for Recall Game

Builds a per-game shuffled deck with deterministic, human-readable card_ids.

This keeps gameplay reproducible (seeded) and avoids mixed id/object
representations by assigning stable ids up front.
"""

from typing import List, Optional
import random

from ..models.card import Card, CardDeck


class DeckFactory:
    """Creates a deterministic deck for a given game_id.

    - Assigns deterministic card_id: "<gid>-<idx>-<rank>-<suit>"
    - Shuffles with a provided seed (or derived from game_id)
    """

    def __init__(self, game_id: str, seed: Optional[int] = None):
        self.game_id = game_id
        # Derive a simple, stable seed from game_id if none provided
        self.seed = seed if seed is not None else (abs(hash(game_id)) % (2**32))
        self._rng = random.Random(self.seed)

    def build_deck(
        self,
        include_jokers: bool = True,
        include_special_powers: bool = True,
    ) -> List[Card]:
        deck = CardDeck(
            include_jokers=include_jokers,
            include_special_powers=include_special_powers,
        )

        # Assign deterministic ids before shuffling
        gid = self.game_id[:6]
        for index, card in enumerate(deck.cards):
            card.card_id = f"{gid}-{index:02d}-{card.rank}-{card.suit}"

        # Deterministic shuffle using local RNG
        self._rng.shuffle(deck.cards)
        return deck.cards


