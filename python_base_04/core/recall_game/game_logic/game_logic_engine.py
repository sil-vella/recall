"""
Game Logic Engine for Recall Game

This module provides the core game logic engine that processes declarative rules
from YAML files to handle game actions and state transitions.
"""

from typing import Dict, Any, Optional, List
from datetime import datetime
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
            
            elif check_type == "is_room_owner":
                if not self._is_room_owner(game_state, action_data.get('player_id')):
                    errors.append("Only room owner can start the game")
            
            elif check_type == "game_not_started":
                game_phase = validation.get('game_phase')
                if game_state.phase.value != game_phase:
                    errors.append(f"Game is not in {game_phase} phase")
            
            elif check_type == "minimum_players":
                min_players = validation.get('min_players', 2)
                if len(game_state.players) < min_players:
                    errors.append(f"Need at least {min_players} players to start")
        
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
    
    def _is_room_owner(self, game_state: GameState, player_id: str) -> bool:
        """Check if player is the room owner"""
        # For now, assume the first player is the room owner
        # This could be enhanced to check actual room ownership
        if not game_state.players:
            return False
        
        first_player_id = list(game_state.players.keys())[0]
        return first_player_id == player_id
    
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
        elif effect_type == "add_computer_player_if_needed":
            return self._effect_add_computer_player_if_needed(effect, game_state, action_data)
        elif effect_type == "start_game_dealing":
            return self._effect_start_game_dealing(effect, game_state, action_data)
        elif effect_type == "set_game_phase":
            return self._effect_set_game_phase(effect, game_state, action_data)
        elif effect_type == "set_first_player":
            return self._effect_set_first_player(effect, game_state, action_data)
        elif effect_type == "record_game_start":
            return self._effect_record_game_start(effect, game_state, action_data)
        
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
        elif placeholder == "game_state":
            # Return serialized game state for notifications
            return self._serialize_game_state_for_notification(game_state)
        elif placeholder == "players":
            # Return player information
            return [{'player_id': pid, 'name': player.name, 'is_computer': hasattr(player, 'is_computer') and player.is_computer} 
                   for pid, player in game_state.players.items()]
        elif placeholder == "current_time":
            import time
            return time.time()
        elif placeholder == "current_player_id":
            return game_state.current_player_id
        elif placeholder == "game_id":
            return game_state.game_id
        
        return placeholder
    
    def _serialize_game_state_for_notification(self, game_state: GameState) -> Dict[str, Any]:
        """Serialize game state for notifications (similar to _to_flutter_game_state)"""
        
        # Map backend phases to Flutter phases
        def _to_flutter_phase(phase: str) -> str:
            mapping = {
                'waiting_for_players': 'waiting',
                'dealing_cards': 'setup',
                'player_turn': 'playing',
                'out_of_turn_play': 'playing',
                'recall_called': 'recall',
                'game_ended': 'finished',
            }
            return mapping.get(phase, 'waiting')
        
        # Convert players to frontend format
        def _to_flutter_player(player_id: str, player) -> Dict[str, Any]:
            return {
                'id': player.player_id,
                'name': player.name,
                'type': 'human' if player.player_type.value == 'human' else 'computer',
                'hand': [self._to_flutter_card(c) for c in player.hand],
                'visibleCards': [self._to_flutter_card(c) for c in player.visible_cards],
                'score': int(player.calculate_points()),  # Use calculate_points() method
                'status': 'playing' if player_id == game_state.current_player_id else 'ready',
                'isCurrentPlayer': player_id == game_state.current_player_id,
                'hasCalledRecall': bool(player.has_called_recall),
            }
        
        # Get current player data
        current_player = None
        if game_state.current_player_id and game_state.current_player_id in game_state.players:
            current_player = _to_flutter_player(
                game_state.current_player_id, 
                game_state.players[game_state.current_player_id]
            )
        
        return {
            'gameId': game_state.game_id,
            'gameName': f"Recall Game {game_state.game_id}",
            'players': [_to_flutter_player(pid, player) for pid, player in game_state.players.items()],
            'currentPlayer': current_player,
            'phase': _to_flutter_phase(game_state.phase.value),
            'status': 'active' if game_state.phase.value in ['player_turn', 'out_of_turn_play', 'recall_called'] else 'inactive' if game_state.phase.value == 'waiting_for_players' else 'ended',
            'drawPile': [self._to_flutter_card(card) for card in game_state.draw_pile],
            'discardPile': [self._to_flutter_card(card) for card in game_state.discard_pile],
            'centerPile': [],  # TODO: Implement if needed
            'turnNumber': 0,  # TODO: Track this
            'roundNumber': 1,  # TODO: Track this
            'gameStartTime': datetime.fromtimestamp(game_state.game_start_time).isoformat() if game_state.game_start_time else None,
            'lastActivityTime': datetime.fromtimestamp(game_state.last_action_time).isoformat() if game_state.last_action_time else None,
            'gameSettings': {},
            'winner': game_state.winner,
            'errorMessage': None,
            'playerCount': len(game_state.players),
            'activePlayerCount': len([p for p in game_state.players.values() if p.is_active]),
            'gameDuration': 'N/A',  # TODO: Calculate this
        }
    
    def _to_flutter_card(self, card) -> Dict[str, Any]:
        """Convert backend card to Flutter format"""
        suit = card.suit
        rank = card.rank
        
        # Convert numeric ranks to word format for frontend compatibility
        def _convert_rank_to_word(rank_str: str) -> str:
            rank_mapping = {
                '2': 'two', '3': 'three', '4': 'four', '5': 'five',
                '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten'
            }
            return rank_mapping.get(rank_str, rank_str)
        
        return {
            'suit': suit,
            'rank': _convert_rank_to_word(rank),
            'points': card.points,
            'displayName': str(card),  # Use __str__ method instead of display_name attribute
            'color': 'red' if suit in ['hearts', 'diamonds'] else 'black',
        }

    # ========= Start Match Effect Methods =========
    
    def _effect_add_computer_player_if_needed(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Add computer player if less than 2 players"""
        condition = effect.get('condition')
        bot_name = effect.get('bot_name', 'Computer')
        
        if condition == "less_than_two_players" and len(game_state.players) < 2:
            from ..models.player import ComputerPlayer
            bot_id = f"bot_{game_state.game_id[:6]}"
            
            if bot_id not in game_state.players:
                computer_player = ComputerPlayer(bot_id, bot_name)
                game_state.add_player(computer_player)
                
                return {
                    'type': 'add_computer_player_if_needed',
                    'success': True,
                    'bot_id': bot_id,
                    'bot_name': bot_name
                }
        
        return {
            'type': 'add_computer_player_if_needed',
            'success': False,
            'reason': 'condition_not_met'
        }
    
    def _effect_start_game_dealing(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Start game and deal cards"""
        import time
        from ..utils.deck_factory import DeckFactory
        
        # Set game phase to dealing
        from ..models.game_state import GamePhase
        game_state.phase = GamePhase.DEALING_CARDS
        game_state.game_start_time = time.time()
        
        # Build deterministic deck from factory
        factory = DeckFactory(game_state.game_id)
        game_state.deck.cards = factory.build_deck(
            include_jokers=True,
            include_special_powers=True,
        )
        
        # Deal cards to players
        cards_per_player = effect.get('cards_per_player', 4)
        for player in game_state.players.values():
            for _ in range(cards_per_player):
                card = game_state.deck.draw_card()
                if card:
                    player.add_card_to_hand(card)
        
        # Setup draw and discard piles
        if effect.get('setup_draw_pile', True):
            game_state.draw_pile = game_state.deck.cards.copy()
            game_state.deck.cards = []
        
        if effect.get('setup_discard_pile', True) and game_state.draw_pile:
            first_card = game_state.draw_pile.pop(0)
            game_state.discard_pile.append(first_card)
        
        return {
            'type': 'start_game_dealing',
            'success': True,
            'cards_dealt': cards_per_player * len(game_state.players),
            'draw_pile_size': len(game_state.draw_pile),
            'discard_pile_size': len(game_state.discard_pile)
        }
    
    def _effect_set_game_phase(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Set game phase"""
        from ..models.game_state import GamePhase
        
        phase_name = effect.get('phase')
        then_phase = effect.get('then')
        
        if phase_name:
            try:
                game_state.phase = GamePhase(phase_name)
                
                # If there's a 'then' phase, set it after a brief moment
                if then_phase:
                    game_state.phase = GamePhase(then_phase)
                
                return {
                    'type': 'set_game_phase',
                    'success': True,
                    'phase': game_state.phase.value
                }
            except ValueError:
                return {
                    'type': 'set_game_phase',
                    'success': False,
                    'error': f'Invalid phase: {phase_name}'
                }
        
        return {
            'type': 'set_game_phase',
            'success': False,
            'error': 'No phase specified'
        }
    
    def _effect_set_first_player(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Set the first player"""
        selection = effect.get('selection', 'first_player')
        
        if selection == "first_human_player":
            # Find first human player (non-computer)
            for player_id, player in game_state.players.items():
                if not hasattr(player, 'is_computer') or not player.is_computer:
                    game_state.current_player_id = player_id
                    break
        elif selection == "first_player":
            # Set first player in the list
            if game_state.players:
                game_state.current_player_id = list(game_state.players.keys())[0]
        
        return {
            'type': 'set_first_player',
            'success': True,
            'current_player_id': game_state.current_player_id
        }
    
    def _effect_record_game_start(self, effect: Dict[str, Any], game_state: GameState, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Effect: Record game start timestamp and details"""
        import time
        
        timestamp = time.time()
        game_state.last_action_time = timestamp
        
        # Add to game history
        history_entry = {
            'action': 'game_started',
            'timestamp': timestamp,
            'player_id': action_data.get('player_id'),
            'players': list(game_state.players.keys()),
            'player_count': len(game_state.players)
        }
        game_state.game_history.append(history_entry)
        
        return {
            'type': 'record_game_start',
            'success': True,
            'timestamp': timestamp,
            'history_entry': history_entry
        } 