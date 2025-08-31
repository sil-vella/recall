"""
Game Event Coordinator for Recall Game

This module handles all WebSocket event coordination for the Recall game,
including event registration, routing, and handling.
"""

from typing import Dict, Any, Optional
from tools.logger.custom_logging import custom_log
from datetime import datetime


class GameEventCoordinator:
    """Coordinates all WebSocket events for the Recall game"""
    
    def __init__(self, game_state_manager, websocket_manager):
        self.game_state_manager = game_state_manager
        self.websocket_manager = websocket_manager
        self.registered_events = []
        
    def register_game_event_listeners(self):
        """Register WebSocket event listeners for Recall game events"""
        try:
            custom_log("🎮 Registering Recall game WebSocket event listeners...")
            
            # Get the WebSocket event listeners from the WebSocket manager
            event_listeners = self.websocket_manager.event_listeners
            if not event_listeners:
                custom_log("❌ WebSocket event listeners not available", level="ERROR")
                return False
            
            # Define all game events
            game_events = [
                'start_match',
                'draw_card', 
                'play_card',
                'discard_card',
                'take_from_discard',
                'call_recall'
            ]
            
            # Register each event listener
            for event_name in game_events:
                # Create a wrapper function that captures the event name
                def create_event_handler(event_name):
                    def event_handler(session_id, data):
                        return self.handle_game_event(session_id, event_name, data)
                    return event_handler
                
                event_listeners.register_custom_listener(event_name, create_event_handler(event_name))
                self.registered_events.append(event_name)
                custom_log(f"✅ Registered game event listener: {event_name}")
            
            custom_log(f"✅ Registered {len(game_events)} Recall game event listeners")
            return True
            
        except Exception as e:
            custom_log(f"❌ Error registering Recall game WebSocket listeners: {e}", level="ERROR")
            return False
    
    def handle_game_event(self, session_id: str, event_name: str, data: dict) -> bool:
        """Handle incoming game events and route to appropriate handlers"""
        try:
            custom_log(f"🎮 [RECALL-GAME] Handling game event: '{event_name}' for session: {session_id}")
            custom_log(f"🎮 [RECALL-GAME] Event data: {data}")
            
            # Route to appropriate game state manager method
            if event_name == 'start_match':
                return self.game_state_manager.on_start_match(session_id, data)
            elif event_name == 'draw_card':
                # Add action type to data payload for draw_card events
                data_with_action = {**data, 'action': 'draw_from_deck'}
                return self._handle_player_action_through_round(session_id, data_with_action)
            elif event_name == 'play_card':
                # Add action type to data payload for play_card events
                data_with_action = {**data, 'action': 'play_card'}
                return self._handle_player_action_through_round(session_id, data_with_action)
            elif event_name == 'discard_card':
                # Add action type to data payload for discard_card events
                data_with_action = {**data, 'action': 'discard_card'}
                return self._handle_player_action_through_round(session_id, data_with_action)
            elif event_name == 'take_from_discard':
                # Add action type to data payload for take_from_discard events
                data_with_action = {**data, 'action': 'take_from_discard'}
                return self._handle_player_action_through_round(session_id, data_with_action)
            elif event_name == 'call_recall':
                # Add action type to data payload for call_recall events
                data_with_action = {**data, 'action': 'call_recall'}
                return self._handle_player_action_through_round(session_id, data_with_action)
            else:
                custom_log(f"⚠️ [RECALL-GAME] Unknown game event: '{event_name}'")
                return False
                
        except Exception as e:
            custom_log(f"❌ [RECALL-GAME] Error handling game event: {e}", level="ERROR")
            return False
    
    def _handle_player_action_through_round(self, session_id: str, data: dict) -> bool:
        """Handle player actions through the game round"""
        try:
            game_id = data.get('game_id') or data.get('room_id')
            if not game_id:
                custom_log(f"❌ [RECALL-GAME] Missing game_id in player action data: {data}")
                return False
            
            # Get the game from the game state manager
            game = self.game_state_manager.get_game(game_id)
            if not game:
                custom_log(f"❌ [RECALL-GAME] Game not found: {game_id}")
                return False
            
            # Get the game round handler
            game_round = game.get_round()
            if not game_round:
                custom_log(f"❌ [RECALL-GAME] Game round not found for game: {game_id}")
                return False
            
            # Handle the player action through the game round and store the result
            action_result = game_round.on_player_action(session_id, data)
            
            # Call complete_round with the action result
            game_round.complete_round(action_result)
            
            # Return the action result
            return action_result
            
        except Exception as e:
            custom_log(f"❌ [RECALL-GAME] Error handling player action through round: {e}", level="ERROR")
            return False
    
    def get_registered_events(self) -> list:
        """Get list of registered event names"""
        return self.registered_events.copy()
    
    def is_event_registered(self, event_name: str) -> bool:
        """Check if a specific event is registered"""
        return event_name in self.registered_events
    
    def health_check(self) -> dict:
        """Perform health check on event coordinator"""
        try:
            return {
                'status': 'healthy',
                'component': 'game_event_coordinator',
                'details': {
                    'registered_events': len(self.registered_events),
                    'event_list': self.registered_events,
                    'game_state_manager_available': self.game_state_manager is not None,
                    'websocket_manager_available': self.websocket_manager is not None
                }
            }
        except Exception as e:
            return {
                'status': 'unhealthy',
                'component': 'game_event_coordinator',
                'details': f'Health check failed: {str(e)}'
            }
    
    # ========= CONSOLIDATED GAME STATE COMMUNICATION METHODS =========
    
    def send_game_state_update(self, game_id: str, event_type: str = 'game_state_updated'):
        """Send game state update to all players in a game"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                custom_log(f"⚠️ Game not found for state update: {game_id}")
                return False
            
            # Convert to Flutter format using our own conversion methods
            flutter_state = self._to_flutter_game_state(game)
            
            # Create payload
            payload = {
                'event_type': event_type,
                'game_id': game_id,
                'game_state': flutter_state,
                'timestamp': self._get_timestamp()
            }
            
            # Send to all players
            self._send_to_all_players(game_id, event_type, payload)
            custom_log(f"📡 Game state update sent to all players in game {game_id}")
            return True
            
        except Exception as e:
            custom_log(f"❌ Error sending game state update: {e}", level="ERROR")
            return False
    
    def send_event_with_game_state(self, game_id: str, event_type: str, additional_data: Dict[str, Any] = None):
        """Send an event with game state AND additional data to all players"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                custom_log(f"⚠️ Game not found for event: {game_id}")
                return False
            
            # Convert to Flutter format using our own conversion methods
            flutter_state = self._to_flutter_game_state(game)
            
            # Create payload with game state and additional data
            payload = {
                'event_type': event_type,
                'game_id': game_id,
                'game_state': flutter_state,
                'timestamp': self._get_timestamp()
            }
            
            # Add additional data if provided
            if additional_data:
                payload.update(additional_data)
            
            # Send to all players
            self._send_to_all_players(game_id, event_type, payload)
            custom_log(f"📡 Event '{event_type}' with game state sent to all players in game {game_id}")
            return True
            
        except Exception as e:
            custom_log(f"❌ Error sending event with game state: {e}", level="ERROR")
            return False
    
    def _send_to_all_players(self, game_id: str, event: str, data: dict) -> bool:
        """Send event to all players in a game using room broadcasting"""
        try:
            # Use the dedicated broadcast manager for proper room broadcasting
            # Game ID is the same as room ID in our system
            if hasattr(self.websocket_manager, 'broadcast_manager') and self.websocket_manager.broadcast_manager:
                return self.websocket_manager.broadcast_manager.broadcast_to_room(game_id, event, data)
            else:
                # Fallback to direct socketio emit if broadcast manager not available
                self.websocket_manager.socketio.emit(event, data, room=game_id)
                custom_log(f"📡 Event '{event}' broadcasted to room {game_id} (fallback)")
                return True
        except Exception as e:
            custom_log(f"❌ Error broadcasting to room: {e}")
            return False
    
    def _get_timestamp(self) -> str:
        """Get current timestamp in ISO format"""
        from datetime import datetime
        return datetime.now().isoformat()
    
    # ========= PUBLIC INTERFACE FOR GAME STATE =========
    
    def send_game_state_update_from_game_state(self, game_id: str, event_type: str = 'game_state_updated'):
        """Public method for game state to request sending updates"""
        return self.send_game_state_update(game_id, event_type)
    
    def send_event_with_game_state_from_game_state(self, game_id: str, event_type: str, additional_data: Dict[str, Any] = None):
        """Public method for game state to request sending events with game state"""
        return self.send_event_with_game_state(game_id, event_type, additional_data)
    
    # ========= FLUTTER CONVERSION METHODS =========
    
    def _to_flutter_card(self, card) -> Dict[str, Any]:
        """Convert card to Flutter format"""
        rank_mapping = {
            '2': 'two', '3': 'three', '4': 'four', '5': 'five',
            '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten'
        }
        return {
            'cardId': card.card_id,
            'suit': card.suit,
            'rank': rank_mapping.get(card.rank, card.rank),
            'points': card.points,
            'displayName': str(card),
            'color': 'red' if card.suit in ['hearts', 'diamonds'] else 'black',
        }

    def _to_flutter_player(self, player, is_current: bool = False) -> Dict[str, Any]:
        """Convert player to Flutter format"""
        return {
            'id': player.player_id,
            'name': player.name,
            'type': 'human' if player.player_type.value == 'human' else 'computer',
            'hand': [self._to_flutter_card(c) for c in player.hand],
            'visibleCards': [self._to_flutter_card(c) for c in player.visible_cards],
            'score': int(player.calculate_points()),
            'status': player.status.value,  # Use the player's actual status
            'isCurrentPlayer': is_current,
            'hasCalledRecall': bool(player.has_called_recall),
        }

    def _to_flutter_game_state(self, game) -> Dict[str, Any]:
        """Convert game state to Flutter format"""
        from datetime import datetime
        
        phase_mapping = {
            'waiting_for_players': 'waiting',
            'dealing_cards': 'setup',
            'player_turn': 'playing',
            'out_of_turn_play': 'out_of_turn',
            'recall_called': 'recall',
            'game_ended': 'finished',
        }
        
        current_player = None
        if game.current_player_id and game.current_player_id in game.players:
            current_player = self._to_flutter_player(game.players[game.current_player_id], True)

        return {
            'gameId': game.game_id,
            'gameName': f"Recall Game {game.game_id}",
            'players': [self._to_flutter_player(player, pid == game.current_player_id) for pid, player in game.players.items()],
            'currentPlayer': current_player,
            'phase': phase_mapping.get(game.phase.value, 'waiting'),
            'status': 'active' if game.phase.value in ['player_turn', 'out_of_turn_play', 'recall_called'] else 'inactive',
            'drawPile': [self._to_flutter_card(card) for card in game.draw_pile],
            'discardPile': [self._to_flutter_card(card) for card in game.discard_pile],
            'gameStartTime': datetime.fromtimestamp(game.game_start_time).isoformat() if game.game_start_time else None,
            'lastActivityTime': datetime.fromtimestamp(game.last_action_time).isoformat() if game.last_action_time else None,
            'winner': game.winner,
            'playerCount': len(game.players),
            'maxPlayers': game.max_players,
            'minPlayers': game.min_players,
            'activePlayerCount': len([p for p in game.players.values() if p.is_active]),
            'permission': game.permission,  # Include room permission
        }
