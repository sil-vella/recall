"""
Computer Player Logic for Recall Game

This module provides AI decision making for computer players in the Recall game.
"""

from typing import Dict, Any, List, Optional
from .yaml_loader import YAMLLoader
from ..models.card import Card
from ..managers.game_state import GameState


class ComputerPlayerLogic:
    """AI decision making for computer players"""
    
    def __init__(self, difficulty: str = "medium"):
        self.difficulty = difficulty
        self.yaml_loader = YAMLLoader()
        self.decision_rules = self._load_decision_rules()
    
    def _load_decision_rules(self) -> Dict[str, Any]:
        """Load AI decision rules from YAML"""
        return self.yaml_loader.load_ai_rules(self.difficulty)
    
    def make_decision(self, game_state: GameState, player_state: Dict[str, Any]) -> Dict[str, Any]:
        """Make AI decision based on game state"""
        decision_type = self._determine_decision_type(game_state, player_state)
        rule = self._find_decision_rule(decision_type)
        
        if rule:
            return self._execute_decision(rule, game_state, player_state)
        else:
            return self._make_default_decision(game_state, player_state)
    
    def _determine_decision_type(self, game_state: GameState, player_state: Dict[str, Any]) -> str:
        """Determine what type of decision the AI needs to make"""
        player_id = player_state.get('player_id')
        
        # Check if it's the player's turn
        if game_state.current_player_id == player_id:
            return "play_card"
        
        # Check for out-of-turn opportunities
        if game_state.last_played_card:
            player = game_state.players.get(player_id)
            if player and player.can_play_out_of_turn(game_state.last_played_card):
                return "play_out_of_turn"
        
        # Check for Recall opportunity
        if game_state.phase.value == "player_turn" and game_state.current_player_id == player_id:
            return "call_recall"
        
        return "wait"
    
    def _find_decision_rule(self, decision_type: str) -> Optional[Dict[str, Any]]:
        """Find a decision rule for the given decision type"""
        return self.decision_rules.get(decision_type)
    
    def _execute_decision(self, rule: Dict[str, Any], game_state: GameState, player_state: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a decision based on the rule"""
        decision_logic = rule.get('decision_logic', [])
        
        for logic_step in decision_logic:
            condition = logic_step.get('if')
            action = logic_step.get('then')
            
            if self._evaluate_condition(condition, game_state, player_state):
                return self._execute_action(action, game_state, player_state)
        
        # Default action if no conditions match
        default_action = rule.get('default_action', 'play_safest_card')
        return self._execute_action(default_action, game_state, player_state)
    
    def _evaluate_condition(self, condition: str, game_state: GameState, player_state: Dict[str, Any]) -> bool:
        """Evaluate a condition for AI decision making"""
        if condition == "has_low_point_card":
            return self._has_low_point_card(player_state)
        elif condition == "has_special_power_card":
            return self._has_special_power_card(player_state)
        elif condition == "power_is_useful":
            return self._power_is_useful(game_state, player_state)
        elif condition == "can_call_recall":
            return self._can_call_recall(game_state, player_state)
        elif condition == "advantageous_position":
            return self._is_in_advantageous_position(game_state, player_state)
        elif condition == "recall_called":
            return game_state.phase.value == "recall_called"
        
        return False
    
    def _has_low_point_card(self, player_state: Dict[str, Any]) -> bool:
        """Check if player has low point cards"""
        hand = player_state.get('hand', [])
        low_point_threshold = 3
        
        for card in hand:
            if card.get('points', 0) <= low_point_threshold:
                return True
        
        return False
    
    def _has_special_power_card(self, player_state: Dict[str, Any]) -> bool:
        """Check if player has special power cards"""
        hand = player_state.get('hand', [])
        
        for card in hand:
            if card.get('special_power'):
                return True
        
        return False
    
    def _power_is_useful(self, game_state: GameState, player_state: Dict[str, Any]) -> bool:
        """Check if a special power would be useful in current situation"""
        # Simple heuristic - powers are generally useful
        return True
    
    def _can_call_recall(self, game_state: GameState, player_state: Dict[str, Any]) -> bool:
        """Check if player can call Recall"""
        return not player_state.get('has_called_recall', False)
    
    def _is_in_advantageous_position(self, game_state: GameState, player_state: Dict[str, Any]) -> bool:
        """Check if player is in an advantageous position to call Recall"""
        total_points = sum(card.get('points', 0) for card in player_state.get('hand', []))
        cards_remaining = len(player_state.get('hand', []))
        
        # Advantageous if few cards and low points
        if cards_remaining <= 1 and total_points <= 5:
            return True
        
        if cards_remaining <= 2 and total_points <= 3:
            return True
        
        return False
    
    def _execute_action(self, action: str, game_state: GameState, player_state: Dict[str, Any]) -> Dict[str, Any]:
        """Execute an AI action"""
        if action == "play_lowest_point_card":
            return self._action_play_lowest_point_card(game_state, player_state)
        elif action == "play_special_power_card":
            return self._action_play_special_power_card(game_state, player_state)
        elif action == "call_recall":
            return self._action_call_recall(game_state, player_state)
        elif action == "play_safest_card":
            return self._action_play_safest_card(game_state, player_state)
        elif action == "play_out_of_turn":
            return self._action_play_out_of_turn(game_state, player_state)
        
        return {"error": "Unknown action", "action": action}
    
    def _action_play_lowest_point_card(self, game_state: GameState, player_state: Dict[str, Any]) -> Dict[str, Any]:
        """Action: Play the card with the lowest point value"""
        hand = player_state.get('hand', [])
        
        if not hand:
            return {"error": "No cards in hand"}
        
        # Find card with lowest points
        lowest_card = min(hand, key=lambda card: card.get('points', 0))
        
        return {
            "action_type": "play_card",
            "card_id": lowest_card.get('card_id'),
            "reason": "lowest_point_card"
        }
    
    def _action_play_special_power_card(self, game_state: GameState, player_state: Dict[str, Any]) -> Dict[str, Any]:
        """Action: Play a special power card"""
        hand = player_state.get('hand', [])
        
        # Find special power cards
        power_cards = [card for card in hand if card.get('special_power')]
        
        if not power_cards:
            return {"error": "No special power cards"}
        
        # Choose the first power card (could be improved with better selection logic)
        chosen_card = power_cards[0]
        
        return {
            "action_type": "play_card",
            "card_id": chosen_card.get('card_id'),
            "reason": "special_power_card"
        }
    
    def _action_call_recall(self, game_state: GameState, player_state: Dict[str, Any]) -> Dict[str, Any]:
        """Action: Call Recall to end the game"""
        return {
            "action_type": "call_recall",
            "reason": "advantageous_position"
        }
    
    def _action_play_safest_card(self, game_state: GameState, player_state: Dict[str, Any]) -> Dict[str, Any]:
        """Action: Play the safest card (lowest points, no special power)"""
        hand = player_state.get('hand', [])
        
        if not hand:
            return {"error": "No cards in hand"}
        
        # Find cards without special powers
        regular_cards = [card for card in hand if not card.get('special_power')]
        
        if regular_cards:
            # Choose the lowest point regular card
            safest_card = min(regular_cards, key=lambda card: card.get('points', 0))
        else:
            # If all cards have special powers, choose the lowest point one
            safest_card = min(hand, key=lambda card: card.get('points', 0))
        
        return {
            "action_type": "play_card",
            "card_id": safest_card.get('card_id'),
            "reason": "safest_card"
        }
    
    def _action_play_out_of_turn(self, game_state: GameState, player_state: Dict[str, Any]) -> Dict[str, Any]:
        """Action: Play a card out of turn"""
        player_id = player_state.get('player_id')
        player = game_state.players.get(player_id)
        
        if not player or not game_state.last_played_card:
            return {"error": "Cannot play out of turn"}
        
        # Find matching cards
        matching_cards = player.can_play_out_of_turn(game_state.last_played_card)
        
        if not matching_cards:
            return {"error": "No matching cards"}
        
        # Choose the lowest point matching card
        chosen_card = min(matching_cards, key=lambda card: card.points)
        
        return {
            "action_type": "play_out_of_turn",
            "card_id": chosen_card.card_id,
            "reason": "out_of_turn_match"
        }
    
    def _make_default_decision(self, game_state: GameState, player_state: Dict[str, Any]) -> Dict[str, Any]:
        """Make a default decision when no specific rule applies"""
        return {
            "action_type": "wait",
            "reason": "no_action_available"
        }
    
    def evaluate_card_value(self, card: Card, game_state: GameState) -> float:
        """Evaluate the value of a card in the current game state"""
        base_value = card.points
        
        # Factor in special powers
        if card.has_special_power():
            base_value -= 2  # Prefer special power cards
        
        # Factor in game progression
        if game_state.phase.value == "recall_called":
            # In final round, minimize points
            return -base_value
        else:
            # During normal play, balance points and utility
            return -base_value * 0.7 + (10 if card.has_special_power() else 0)
    
    def select_best_card(self, game_state: GameState, player_state: Dict[str, Any]) -> Optional[str]:
        """Select the best card to play"""
        hand = player_state.get('hand', [])
        
        if not hand:
            return None
        
        # Convert hand to Card objects for evaluation
        cards = []
        for card_data in hand:
            # This is a simplified conversion - in practice, you'd want proper Card objects
            card = Card(
                rank=card_data.get('rank', ''),
                suit=card_data.get('suit', ''),
                points=card_data.get('points', 0),
                special_power=card_data.get('special_power'),
                card_id=card_data.get('card_id', '')
            )
            cards.append(card)
        
        # Evaluate all cards
        card_values = []
        for card in cards:
            value = self.evaluate_card_value(card, game_state)
            card_values.append((card, value))
        
        # Sort by value (best first)
        card_values.sort(key=lambda x: x[1], reverse=True)
        
        return card_values[0][0].card_id if card_values else None 