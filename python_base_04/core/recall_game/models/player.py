"""
Player Models for Recall Game

This module defines the player system for the Recall card game,
including human players and computer players with AI logic.
"""

from typing import List, Dict, Any, Optional
from enum import Enum
from .card import Card


class PlayerType(Enum):
    """Player types"""
    HUMAN = "human"
    COMPUTER = "computer"


class Player:
    """Base player class for the Recall game"""
    
    def __init__(self, player_id: str, player_type: PlayerType, name: str):
        self.player_id = player_id
        self.player_type = player_type
        self.name = name
        self.hand = []  # 4 cards face down
        self.visible_cards = []  # Cards player has looked at
        self.points = 0
        self.cards_remaining = 4
        self.is_active = True
        self.has_called_recall = False
        self.last_action_time = None
    
    def add_card_to_hand(self, card: Card):
        """Add a card to the player's hand"""
        card.owner_id = self.player_id
        self.hand.append(card)
        self.cards_remaining = len(self.hand)
    
    def remove_card_from_hand(self, card_id: str) -> Optional[Card]:
        """Remove a card from the player's hand"""
        for i, card in enumerate(self.hand):
            if card.card_id == card_id:
                removed_card = self.hand.pop(i)
                self.cards_remaining = len(self.hand)
                return removed_card
        return None
    
    def look_at_card(self, card_id: str) -> Optional[Card]:
        """Look at a specific card in hand"""
        for card in self.hand:
            if card.card_id == card_id:
                card.is_visible = True
                if card not in self.visible_cards:
                    self.visible_cards.append(card)
                return card
        return None
    
    def get_visible_cards(self) -> List[Card]:
        """Get cards that the player has looked at"""
        return [card for card in self.hand if card.is_visible]
    
    def get_hidden_cards(self) -> List[Card]:
        """Get cards that the player hasn't looked at"""
        return [card for card in self.hand if not card.is_visible]
    
    def calculate_points(self) -> int:
        """Calculate total points from cards in hand"""
        return sum(card.points for card in self.hand)
    
    def call_recall(self):
        """Player calls Recall to end the game"""
        self.has_called_recall = True
    
    def can_play_out_of_turn(self, played_card: Card) -> List[Card]:
        """Get cards that can be played out of turn"""
        return [card for card in self.hand if card.can_play_out_of_turn(played_card)]
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert player to dictionary representation"""
        return {
            "player_id": self.player_id,
            "player_type": self.player_type.value,
            "name": self.name,
            "hand": [card.to_dict() for card in self.hand],
            "visible_cards": [card.to_dict() for card in self.visible_cards],
            "points": self.points,
            "cards_remaining": self.cards_remaining,
            "is_active": self.is_active,
            "has_called_recall": self.has_called_recall
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Player':
        """Create player from dictionary"""
        player_type = PlayerType(data["player_type"])
        player = cls(data["player_id"], player_type, data["name"])
        
        # Restore hand
        for card_data in data.get("hand", []):
            card = Card.from_dict(card_data)
            player.add_card_to_hand(card)
        
        # Restore visible cards
        for card_data in data.get("visible_cards", []):
            card = Card.from_dict(card_data)
            player.visible_cards.append(card)
        
        player.points = data.get("points", 0)
        player.cards_remaining = data.get("cards_remaining", 4)
        player.is_active = data.get("is_active", True)
        player.has_called_recall = data.get("has_called_recall", False)
        
        return player


class HumanPlayer(Player):
    """Human player class"""
    
    def __init__(self, player_id: str, name: str):
        super().__init__(player_id, PlayerType.HUMAN, name)
    
    def make_decision(self, game_state: Dict[str, Any]) -> Dict[str, Any]:
        """Human players make decisions through WebSocket events"""
        # This will be handled by WebSocket events from the frontend
        return {
            "player_id": self.player_id,
            "decision_type": "waiting_for_human_input",
            "available_actions": self._get_available_actions(game_state)
        }
    
    def _get_available_actions(self, game_state: Dict[str, Any]) -> List[str]:
        """Get available actions for the human player"""
        actions = []
        
        if game_state.get("current_player_id") == self.player_id:
            actions.append("play_card")
            actions.append("draw_from_discard")
            actions.append("call_recall")
        
        # Check for out-of-turn plays
        if game_state.get("last_played_card"):
            out_of_turn_cards = self.can_play_out_of_turn(
                game_state["last_played_card"]
            )
            if out_of_turn_cards:
                actions.append("play_out_of_turn")
        
        return actions


class ComputerPlayer(Player):
    """Computer player class with AI decision making"""
    
    def __init__(self, player_id: str, name: str, difficulty: str = "medium"):
        super().__init__(player_id, PlayerType.COMPUTER, name)
        self.difficulty = difficulty
        self.game_logic = self._load_game_logic()
    
    def _load_game_logic(self):
        """Load AI game logic based on difficulty"""
        # This will be implemented to load from YAML files
        from ..game_logic.computer_player_logic import ComputerPlayerLogic
        return ComputerPlayerLogic(self.difficulty)
    
    def make_decision(self, game_state: Dict[str, Any]) -> Dict[str, Any]:
        """Make AI decision based on game state"""
        return self.game_logic.make_decision(game_state, self.to_dict())
    
    def _evaluate_card_value(self, card: Card, game_state: Dict[str, Any]) -> float:
        """Evaluate the value of a card in the current game state"""
        base_value = card.points
        
        # Factor in special powers
        if card.has_special_power():
            base_value -= 2  # Prefer special power cards
        
        # Factor in game progression
        if game_state.get("recall_called"):
            # In final round, minimize points
            return -base_value
        else:
            # During normal play, balance points and utility
            return -base_value * 0.7 + (10 if card.has_special_power() else 0)
    
    def _select_best_card(self, game_state: Dict[str, Any]) -> Optional[Card]:
        """Select the best card to play"""
        if not self.hand:
            return None
        
        # Evaluate all cards
        card_values = []
        for card in self.hand:
            value = self._evaluate_card_value(card, game_state)
            card_values.append((card, value))
        
        # Sort by value (best first)
        card_values.sort(key=lambda x: x[1], reverse=True)
        
        return card_values[0][0] if card_values else None
    
    def _should_call_recall(self, game_state: Dict[str, Any]) -> bool:
        """Determine if the computer should call Recall"""
        if self.has_called_recall:
            return False
        
        # Calculate current position
        total_points = self.calculate_points()
        cards_remaining = len(self.hand)
        
        # Simple AI logic - call Recall if in good position
        if cards_remaining <= 1 and total_points <= 5:
            return True
        
        if cards_remaining <= 2 and total_points <= 3:
            return True
        
        return False 