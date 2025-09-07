"""
Game Event Coordinator for Recall Game

This module handles all WebSocket event coordination for the Recall game,
including event registration, routing, and handling.
"""

from typing import Dict, Any, Optional, List
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
            
            # Get the WebSocket event listeners from the WebSocket manager
            event_listeners = self.websocket_manager.event_listeners
            if not event_listeners:
                return False
            
            # Define all game events
            game_events = [
                'start_match',
                'draw_card', 
                'play_card',
                'discard_card',
                'take_from_discard',
                'call_recall',
                'same_rank_play'
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
            return True
            
        except Exception as e:
            return False
    
    def handle_game_event(self, session_id: str, event_name: str, data: dict) -> bool:
        """Handle incoming game events and route to appropriate handlers"""
        try:
            
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
            elif event_name == 'same_rank_play':
                # Add action type to data payload for same_rank_play events
                data_with_action = {**data, 'action': 'same_rank_play'}
                return self._handle_player_action_through_round(session_id, data_with_action)
            else:
                return False
                
        except Exception as e:
            return False
    
    def _handle_player_action_through_round(self, session_id: str, data: dict) -> bool:
        """Handle player actions through the game round"""
        try:
            game_id = data.get('game_id') or data.get('room_id')
            if not game_id:
                return False
            
            # Get the game from the game state manager
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return False
            
            # Get the game round handler
            game_round = game.get_round()
            if not game_round:
                return False
            
            # Handle the player action through the game round and store the result
            action_result = game_round.on_player_action(session_id, data)
            
            # Return the action result
            return action_result
            
        except Exception as e:
            return False
    
    # ========= COMMUNICATION METHODS =========
    
    def _send_error(self, session_id: str, message: str):
        """Send error message to session"""
        if self.websocket_manager:
            self.websocket_manager.send_to_session(session_id, 'recall_error', {'message': message})

    def _broadcast_event(self, room_id: str, payload: Dict[str, Any]):
        """Broadcast event to room"""
        try:
            event_type = payload.get('event_type')
            if event_type and self.websocket_manager:
                event_payload = {k: v for k, v in payload.items() if k != 'event_type'}
                self.websocket_manager.socketio.emit(event_type, event_payload, room=room_id)
        except Exception as e:
            pass

    def _send_to_player(self, game_id: str, player_id: str, event: str, data: dict) -> bool:
        """Send event to specific player"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return False
            session_id = game.get_player_session(player_id)
            if not session_id:
                return False
            self.websocket_manager.send_to_session(session_id, event, data)
            return True
        except Exception as e:
            return False

    def _send_to_all_players(self, game_id: str, event: str, data: dict) -> bool:
        """Send event to all players in game using direct room broadcast"""
        try:
            # Use direct room broadcast instead of looping through players
            self.websocket_manager.broadcast_to_room(game_id, event, data)
            return True
        except Exception as e:
            return False

    def _send_action_result(self, game_id: str, player_id: str, result: Dict[str, Any]):
        """Send action result to player"""
        data = {'event_type': 'action_result', 'game_id': game_id, 'action_result': result}
        self._send_to_player(game_id, player_id, 'action_result', data)

    def _broadcast_game_action(self, game_id: str, action_type: str, action_data: Dict[str, Any], exclude_player_id: str = None):
        """Broadcast game action to other players using direct room broadcast"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return
            data = {
                'event_type': 'game_action',
                'game_id': game_id,
                'action_type': action_type,
                'action_data': action_data,
                'game_state': self.game_state_manager._to_flutter_game_data(game),
                'exclude_player_id': exclude_player_id,  # Include exclude info for client-side filtering
            }
            # Use direct room broadcast instead of looping through players
            self.websocket_manager.broadcast_to_room(game_id, 'game_action', data)
        except Exception as e:
            pass

    def _send_game_state_update(self, game_id: str):
        """Send complete game state update to all players"""
        game = self.game_state_manager.get_game(game_id)
        if game:
            payload = {
                'event_type': 'game_state_updated',
                'game_id': game_id,
                'game_state': self.game_state_manager._to_flutter_game_data(game),
            }
            self._send_to_all_players(game_id, 'game_state_updated', payload)
    
    def _send_game_state_partial_update(self, game_id: str, changed_properties: List[str]):
        """Send partial game state update with only changed properties to all players"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return
            
            # Get full game state in Flutter format
            full_game_state = self.game_state_manager._to_flutter_game_data(game)
            
            # Extract only the changed properties
            partial_state = {}
            property_mapping = {
                'phase': 'phase',
                'current_player_id': 'currentPlayer',
                'recall_called_by': 'recallCalledBy',
                'game_ended': 'gameEnded',
                'winner': 'winner',
                'discard_pile': 'discardPile',
                'draw_pile': 'drawPile',
                'last_action_time': 'lastActivityTime',
                'players': 'players',  # Special case - includes all players
            }
            
            for prop in changed_properties:
                flutter_key = property_mapping.get(prop)
                if flutter_key and flutter_key in full_game_state:
                    partial_state[flutter_key] = full_game_state[flutter_key]
            
            # Always include core identifiers
            partial_state['gameId'] = game_id
            partial_state['timestamp'] = datetime.now().isoformat()
            
            payload = {
                'event_type': 'game_state_partial_update',
                'game_id': game_id,
                'changed_properties': changed_properties,
                'partial_state': partial_state,
            }
            
            self._send_to_all_players(game_id, 'game_state_partial_update', payload)
            
        except Exception as e:
            pass
    
    def _send_player_state_update(self, game_id: str, player_id: str):
        """Send player state update including hand to the specific player"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return
            
            if player_id not in game.players:
                return
            
            player = game.players[player_id]
            
            # Get player session ID
            session_id = game.player_sessions.get(player_id)
            if not session_id:
                # Computer players don't have session IDs, but their status should still be updated in game state
                if player_id.startswith('computer_'):
                    return
                else:
                    return
            
            # Convert player to Flutter format using GameStateManager
            player_data = self.game_state_manager._to_flutter_player_data(
                player, 
                is_current=(game.current_player_id == player_id)
            )
            
            # Create player state update payload
            payload = {
                'event_type': 'player_state_updated',
                'game_id': game_id,
                'player_id': player_id,
                'player_data': player_data,
                'timestamp': datetime.now().isoformat()
            }
            
            # Send to the specific player
            self.websocket_manager.send_to_session(session_id, 'player_state_updated', payload)
            
        except Exception as e:
            pass
    
    def _send_player_state_update_to_all(self, game_id: str):
        """Send player state update to all players in the game"""
        try:
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return
            
            # Send player state update to each player
            for player_id, session_id in game.player_sessions.items():
                if player_id in game.players:
                    player = game.players[player_id]
                    
                    # Convert player to Flutter format using GameStateManager
                    player_data = self.game_state_manager._to_flutter_player_data(
                        player, 
                        is_current=(game.current_player_id == player_id)
                    )
                    
                    # Create player state update payload
                    payload = {
                        'event_type': 'player_state_updated',
                        'game_id': game_id,
                        'player_id': player_id,
                        'player_data': player_data,
                        'timestamp': datetime.now().isoformat()
                    }
                    
                    # Send to the specific player
                    self.websocket_manager.send_to_session(session_id, 'player_state_updated', payload)
            
        except Exception as e:
            pass
    
    def _send_round_completion_event(self, game_id: str, round_result: Dict[str, Any]):
        """Send round completion event to all players using direct room broadcast"""
        try:
            payload = {
                'event_type': 'round_completed',
                'game_id': game_id,
                'round_number': round_result.get('round_number'),
                'round_duration': round_result.get('round_duration'),
                'winner': round_result.get('winner'),
                'final_action': round_result.get('final_action'),
                'game_phase': round_result.get('game_phase'),
                'timestamp': datetime.now().isoformat()
            }
            # Use direct room broadcast instead of looping through players
            self.websocket_manager.broadcast_to_room(game_id, 'round_completed', payload)
        except Exception as e:
            pass

    def _send_recall_player_joined_events(self, room_id: str, user_id: str, session_id: str, game):
        """Send recall-specific events when a player joins a room"""
        try:
            
            # Convert game to Flutter format using GameStateManager (which has the proper conversion method)
            game_state = self.game_state_manager._to_flutter_game_data(game)
            
            # 1. Send new_player_joined event to the room
            # Get the owner_id for this room from the WebSocket manager
            owner_id = self.websocket_manager.get_room_creator(room_id)
            
            room_payload = {
                'event_type': 'recall_new_player_joined',
                'room_id': room_id,
                'owner_id': owner_id,  # Include owner_id for ownership determination
                'joined_player': {
                    'user_id': user_id,
                    'session_id': session_id,
                    'name': f"Player_{user_id[:8]}",
                    'joined_at': datetime.now().isoformat()
                },
                'game_state': game_state,
                'timestamp': datetime.now().isoformat()
            }
            
            # Send as direct event to the room
            self.websocket_manager.socketio.emit('recall_new_player_joined', room_payload, room=room_id)
            user_games = []
            for game_id, user_game in self.game_state_manager.active_games.items():
                # Check if user is in this game
                if user_id in user_game.players:
                    # Use GameStateManager for data conversion
                    user_game_state = self.game_state_manager._to_flutter_game_data(user_game)
                    
                    # Get the owner_id for this room from the WebSocket manager
                    owner_id = self.websocket_manager.get_room_creator(game_id)
                    
                    user_games.append({
                        'game_id': game_id,
                        'room_id': game_id,  # Game ID is the same as room ID
                        'owner_id': owner_id,  # Include owner_id for ownership determination
                        'game_state': user_game_state,
                        'joined_at': datetime.now().isoformat()
                    })
                else:
                    pass
            
            user_payload = {
                'event_type': 'recall_joined_games',
                'user_id': user_id,
                'session_id': session_id,
                'games': user_games,
                'total_games': len(user_games),
                'timestamp': datetime.now().isoformat()
            }
            
            # Send as direct event to the specific user's session
            self.websocket_manager.send_to_session(session_id, 'recall_joined_games', user_payload)
            
        except Exception as e:
            import traceback
    

    
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
