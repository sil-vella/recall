"""
Game Logic Engine for Recall Game

This module provides the core game logic engine that processes declarative rules
from YAML files to handle game actions and state transitions.
"""

from typing import Dict, Any, Optional, List
from .yaml_loader import YAMLLoader
from ..models.game_state import GameState
from ..models.player import Player


class GameLogicEngine:
    """Main game logic engine that processes declarative rules"""
    
    def __init__(self):
        self.yaml_loader = YAMLLoader()
        self.action_rules = self._load_action_rules()
        self.card_rules = self._load_card_rules()
        self.special_power_rules = self._load_special_power_rules()
    
    def _load_action_rules(self) -> Dict[str, Any]:
        """Load action rules from YAML files"""
        return self.yaml_loader.load_action_rules()
    
    def _load_card_rules(self) -> Dict[str, Any]:
        """Load card-specific rules from YAML files"""
        return self.yaml_loader.load_card_rules()
    
    def _load_special_power_rules(self) -> Dict[str, Any]:
        """Load special power card rules from YAML files"""
        return self.yaml_loader.load_special_power_rules()
    
    def process_player_action(self, game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process player action through declarative rules"""
        action_type = action_data.get('action_type')
        
        # Find matching rule
        rule = self._find_matching_rule(action_type, game_state, action_data)
        if rule:
            return self._execute_rule(rule, game_state, action_data)
        
        return {'error': 'Invalid action', 'action_type': action_type}
    
    def _find_matching_rule(self, action_type: str, game_state: GameState, action_data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Find a matching rule for the given action"""
        if action_type not in self.action_rules:
            return None
        
        rule = self.action_rules[action_type]
        
        # Check if rule applies to current game state
        if self._rule_applies(rule, game_state, action_data):
            return rule
        
        return None
    
    def _rule_applies(self, rule: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> bool:
        """Check if a rule applies to the current game state"""
        triggers = rule.get('triggers', [])
        
        for trigger in triggers:
            if self._trigger_matches(trigger, game_state, action_data):
                return True
        
        return False
    
    def _trigger_matches(self, trigger: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> bool:
        """Check if a trigger matches the current state"""
        condition = trigger.get('condition')
        required_game_state = trigger.get('game_state')
        out_of_turn = trigger.get('out_of_turn', False)
        
        # Check game state
        if required_game_state and game_state.phase.value != required_game_state:
            return False
        
        # Check out-of-turn condition
        if out_of_turn and game_state.current_player_id == action_data.get('player_id'):
            return False
        
        # Check specific conditions
        if condition == "is_player_turn":
            return game_state.current_player_id == action_data.get('player_id')
        elif condition == "same_rank_card":
            return self._has_same_rank_card(game_state, action_data)
        elif condition == "recall_called":
            return game_state.phase.value == "recall_called"
        
        return True
    
    def _has_same_rank_card(self, game_state: GameState, action_data: Dict[str, Any]) -> bool:
        """Check if player has a card of the same rank as the last played card"""
        if not game_state.last_played_card:
            return False
        
        player_id = action_data.get('player_id')
        player = game_state.players.get(player_id)
        if not player:
            return False
        
        matching_cards = player.can_play_out_of_turn(game_state.last_played_card)
        return len(matching_cards) > 0
    
    def _execute_rule(self, rule: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a rule and return the result"""
        result = {
            'success': True,
            'action_type': action_data.get('action_type'),
            'player_id': action_data.get('player_id'),
            'effects': [],
            'notifications': []
        }
        
        # Validate action
        validation_result = self._validate_action(rule, game_state, action_data)
        if not validation_result['valid']:
            return {
                'error': 'Validation failed',
                'validation_errors': validation_result['errors']
            }
        
        # Execute effects
        effects = rule.get('effects', [])
        for effect in effects:
            effect_result = self._execute_effect(effect, game_state, action_data)
            result['effects'].append(effect_result)
        
        # Generate notifications
        notifications = rule.get('notifications', [])
        for notification in notifications:
            notification_data = self._generate_notification(notification, game_state, action_data)
            result['notifications'].append(notification_data)
        
        return result
    
    def _validate_action(self, rule: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Validate an action according to the rule"""
        validation_rules = rule.get('validation', [])
        errors = []
        
        for validation in validation_rules:
            check_type = validation.get('check')
            
            if check_type == "player_has_card":
                card_id = validation.get('card_id')
                if not self._player_has_card(game_state, action_data.get('player_id'), card_id):
                    errors.append(f"Player does not have card {card_id}")
            
            elif check_type == "card_is_playable":
                card_rank = validation.get('card_rank')
                if not self._card_is_playable(game_state, action_data.get('player_id'), card_rank):
                    errors.append(f"Card {card_rank} is not playable")
            
            elif check_type == "is_player_turn":
                if game_state.current_player_id != action_data.get('player_id'):
                    errors.append("Not player's turn")
        
        return {
            'valid': len(errors) == 0,
            'errors': errors
        }
    
    def _player_has_card(self, game_state: GameState, player_id: str, card_id: str) -> bool:
        """Check if player has a specific card"""
        player = game_state.players.get(player_id)
        if not player:
            return False
        
        for card in player.hand:
            if card.card_id == card_id:
                return True
        
        return False
    
    def _card_is_playable(self, game_state: GameState, player_id: str, card_rank: str) -> bool:
        """Check if a card is playable"""
        player = game_state.players.get(player_id)
        if not player:
            return False
        
        # Check if player has a card of this rank
        for card in player.hand:
            if card.rank == card_rank:
                return True
        
        return False
    
    def _execute_effect(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a single effect"""
        effect_type = effect.get('type')
        
        if effect_type == "move_card_to_discard":
            return self._effect_move_card_to_discard(effect, game_state, action_data)
        elif effect_type == "replace_card_in_hand":
            return self._effect_replace_card_in_hand(effect, game_state, action_data)
        elif effect_type == "check_special_power":
            return self._effect_check_special_power(effect, game_state, action_data)
        elif effect_type == "check_recall_opportunity":
            return self._effect_check_recall_opportunity(effect, game_state, action_data)
        elif effect_type == "next_player":
            return self._effect_next_player(effect, game_state, action_data)
        elif effect_type == "draw_from_deck":
            return game_state.draw_from_deck(action_data.get('player_id'))
        elif effect_type == "take_from_discard":
            return game_state.take_from_discard(action_data.get('player_id'))
        elif effect_type == "place_drawn_card_replace":
            return game_state.place_drawn_card_replace(action_data.get('player_id'), effect.get('replace_card_id') or action_data.get('replace_card_id'))
        elif effect_type == "place_drawn_card_play":
            return game_state.place_drawn_card_play(action_data.get('player_id'))
        elif effect_type == "play_card":
            return game_state.play_card(action_data.get('player_id'), action_data.get('card_id'))
        
        return {'type': effect_type, 'status': 'unknown_effect'}
    
    def _effect_move_card_to_discard(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Move card from player hand to discard pile"""
        card_id = effect.get('card_id', action_data.get('card_id'))
        player_id = action_data.get('player_id')
        
        player = game_state.players.get(player_id)
        if not player:
            return {'error': 'Player not found'}
        
        card = player.remove_card_from_hand(card_id)
        if not card:
            return {'error': 'Card not found'}
        
        game_state.discard_pile.append(card)
        game_state.last_played_card = card
        
        return {
            'type': 'move_card_to_discard',
            'card_id': card_id,
            'success': True
        }
    
    def _effect_replace_card_in_hand(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Replace card in player's hand"""
        player_id = action_data.get('player_id')
        new_card = effect.get('new_card')
        
        player = game_state.players.get(player_id)
        if not player:
            return {'error': 'Player not found'}
        
        # Draw a new card from draw pile
        if game_state.draw_pile:
            new_card = game_state.draw_pile.pop(0)
            player.add_card_to_hand(new_card)
        
        return {
            'type': 'replace_card_in_hand',
            'success': True
        }
    
    def _effect_check_special_power(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Check for special power activation"""
        card_rank = effect.get('card_rank')
        if_power = effect.get('if_power')
        
        # Find the played card
        card_id = action_data.get('card_id')
        player_id = action_data.get('player_id')
        player = game_state.players.get(player_id)
        
        if not player:
            return {'error': 'Player not found'}
        
        # Check if the played card has a special power
        for card in player.hand:
            if card.card_id == card_id and card.has_special_power():
                return {
                    'type': 'check_special_power',
                    'has_power': True,
                    'power_type': card.special_power,
                    'trigger': if_power
                }
        
        return {
            'type': 'check_special_power',
            'has_power': False
        }
    
    def _effect_check_recall_opportunity(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Check if player can call Recall"""
        player_id = action_data.get('player_id')
        player = game_state.players.get(player_id)
        
        if not player:
            return {'error': 'Player not found'}
        
        can_call = not player.has_called_recall and game_state.phase.value != "recall_called"
        
        return {
            'type': 'check_recall_opportunity',
            'can_call': can_call
        }
    
    def _effect_next_player(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Move to next player"""
        game_state.next_player()
        
        return {
            'type': 'next_player',
            'next_player_id': game_state.current_player_id
        }
    
    def _generate_notification(self, notification: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Generate a notification based on the notification template"""
        notification_type = notification.get('type')
        event = notification.get('event')
        data_template = notification.get('data', {})
        
        # Replace placeholders in data template
        data = self._replace_placeholders(data_template, game_state, action_data)
        
        return {
            'type': notification_type,
            'event': event,
            'data': data
        }
    
    def _replace_placeholders(self, template: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Replace placeholders in a template with actual values"""
        result = {}
        
        for key, value in template.items():
            if isinstance(value, str) and value.startswith('{') and value.endswith('}'):
                placeholder = value[1:-1]
                result[key] = self._get_placeholder_value(placeholder, game_state, action_data)
            else:
                result[key] = value
        
        return result
    
    def _get_placeholder_value(self, placeholder: str, game_state: GameState, action_data: Dict[str, Any]) -> Any:
        """Get the value for a placeholder"""
        if placeholder == "player_id":
            return action_data.get('player_id')
        elif placeholder == "card_id":
            return action_data.get('card_id')
        elif placeholder == "card_rank":
            return action_data.get('card_rank')
        elif placeholder == "out_of_turn":
            return action_data.get('out_of_turn', False)
        elif placeholder == "card_data":
            # Return basic card info
            return {
                'card_id': action_data.get('card_id'),
                'rank': action_data.get('card_rank')
            }
        
        return placeholder 