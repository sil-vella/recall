"""
Game Event Coordinator for Recall Game

This module handles all WebSocket event coordination for the Recall game,
including event registration, routing, and handling.
"""

import os
from typing import Dict, Any, Optional, List
from tools.logger.custom_logging import custom_log
from datetime import datetime
from .dart_services.dart_subprocess_manager import dart_subprocess_manager

LOGGING_SWITCH = True


class GameEventCoordinator:
    """Coordinates all WebSocket events for the Recall game"""
    
    def __init__(self, game_state_manager, websocket_manager):
        self.game_state_manager = game_state_manager
        self.websocket_manager = websocket_manager
        self.registered_events = []
        
        # Initialize Dart subprocess manager
        self.dart_manager = dart_subprocess_manager
        self._initialize_dart_service()
        
        # Register hook callbacks for room events
        self._register_hook_callbacks()
    
    def _initialize_dart_service(self):
        """Initialize the Dart game service subprocess"""
        try:
            # Path to the Dart service script (relative to this file)
            current_dir = os.path.dirname(os.path.abspath(__file__))
            dart_service_path = os.path.join(current_dir, "dart_services", "dart_game_service.dart")
            
            if not self.dart_manager.start_dart_service(dart_service_path):
                custom_log("Failed to start Dart service, falling back to Python logic", isOn=LOGGING_SWITCH)
            else:
                custom_log("Dart service initialized successfully", isOn=LOGGING_SWITCH)
                
        except Exception as e:
            custom_log(f"Error initializing Dart service: {e}", isOn=LOGGING_SWITCH)
    
    def _register_hook_callbacks(self):
        """Register hook callbacks for room events to automatically create games"""
        try:
            custom_log("Registering hook callbacks for room events...", isOn=LOGGING_SWITCH)
            
            # Get app_manager from websocket_manager
            app_manager = None
            if self.websocket_manager and hasattr(self.websocket_manager, '_app_manager'):
                app_manager = self.websocket_manager._app_manager
            
            if app_manager and hasattr(app_manager, 'register_hook_callback'):
                # Register callback for room_created hook
                app_manager.register_hook_callback('room_created', self._on_room_created)
                custom_log("Registered room_created hook callback with app_manager", isOn=LOGGING_SWITCH)
                
                # Register callback for room_joined hook  
                app_manager.register_hook_callback('room_joined', self._on_room_joined)
                custom_log("Registered room_joined hook callback with app_manager", isOn=LOGGING_SWITCH)
                
            else:
                custom_log("WARNING: App manager not found or does not support hook callbacks", isOn=LOGGING_SWITCH)
                if self.websocket_manager:
                    custom_log(f"WebSocket manager has _app_manager: {hasattr(self.websocket_manager, '_app_manager')}", isOn=LOGGING_SWITCH)
                
        except Exception as e:
            custom_log(f"Error registering hook callbacks: {e}", isOn=LOGGING_SWITCH)
    
    def _on_room_created(self, room_data):
        """Callback for room_created hook - automatically create game via Dart service"""
        try:
            custom_log(f"Room created hook triggered: {room_data}", isOn=LOGGING_SWITCH)
            
            room_id = room_data.get('room_id')
            max_players = room_data.get('max_players', 4)
            min_players = room_data.get('min_players', 2)
            
            if room_id:
                # Create game via Dart service
                custom_log(f"Creating game for room {room_id} via Dart service...", isOn=LOGGING_SWITCH)
                
                # Create game in Dart service with individual parameters
                result = self.dart_manager.create_game(
                    game_id=room_id,
                    max_players=max_players,
                    min_players=min_players,
                    permission=room_data.get('permission', 'public')
                )
                if result:
                    custom_log(f"Game created successfully for room {room_id}", isOn=LOGGING_SWITCH)
                    
                    # 🎯 CUTOFF INTEGRATION: Send game state to frontend
                    self._send_dart_game_state_to_frontend(room_id)
                else:
                    custom_log(f"Failed to create game for room {room_id}: {result}", isOn=LOGGING_SWITCH)
            else:
                custom_log("ERROR: No room_id in room_created hook data", isOn=LOGGING_SWITCH)
                
        except Exception as e:
            custom_log(f"Error in room_created callback: {e}", isOn=LOGGING_SWITCH)
    
    def _on_room_joined(self, room_data):
        """Callback for room_joined hook - add player to game via Dart service"""
        try:
            custom_log(f"Room joined hook triggered: {room_data}", isOn=LOGGING_SWITCH)
            
            room_id = room_data.get('room_id')
            user_id = room_data.get('user_id')
            
            if room_id and user_id:
                # Add player to game via Dart service
                custom_log(f"Adding player {user_id} to game {room_id} via Dart service...", isOn=LOGGING_SWITCH)
                
                # Generate a player name from user_id (or get from session data if available)
                player_name = f"Player_{user_id[:8]}"  # Use first 8 chars of user_id as name
                
                result = self.dart_manager.join_game(
                    game_id=room_id,
                    player_id=user_id,
                    player_name=player_name,
                    player_type='human'
                )
                if result:
                    custom_log(f"Player {user_id} added to game {room_id} successfully", isOn=LOGGING_SWITCH)
                    
                    # 🎯 CUTOFF INTEGRATION: Send updated game state to frontend
                    self._send_dart_game_state_to_frontend(room_id)
                else:
                    custom_log(f"Failed to add player {user_id} to game {room_id}: {result}", isOn=LOGGING_SWITCH)
            else:
                custom_log("ERROR: Missing room_id or user_id in room_joined hook data", isOn=LOGGING_SWITCH)
                
        except Exception as e:
            custom_log(f"Error in room_joined callback: {e}", isOn=LOGGING_SWITCH)
    
    def _send_dart_game_state_to_frontend(self, game_id: str):
        """🎯 CUTOFF INTEGRATION: Get game state from Dart and send to frontend"""
        try:
            custom_log(f"Sending Dart game state to frontend for game {game_id}", isOn=LOGGING_SWITCH)
            
            # Get game state from Dart service
            dart_response = self.dart_manager.get_game_state(game_id)
            if not dart_response or not dart_response.get('success'):
                custom_log(f"Failed to get game state from Dart for game {game_id}", isOn=LOGGING_SWITCH)
                return
            
            game_state_data = dart_response.get('data', {}).get('game_state', {})
            if not game_state_data:
                custom_log(f"No game state data received from Dart for game {game_id}", isOn=LOGGING_SWITCH)
                return
            
            # Convert Dart game state to Flutter format (similar to old _to_flutter_game_data)
            flutter_game_data = self._convert_dart_to_flutter_format(game_state_data)
            
            # Send game state update to all players in the room
            payload = {
                'event_type': 'game_state_updated',
                'game_id': game_id,
                'game_state': flutter_game_data,
                'timestamp': datetime.now().isoformat()
            }
            
            # Use existing WebSocket broadcast method
            self._send_to_all_players(game_id, 'game_state_updated', payload)
            custom_log(f"Game state update sent to frontend for game {game_id}", isOn=LOGGING_SWITCH)
            
        except Exception as e:
            custom_log(f"Error sending Dart game state to frontend: {e}", isOn=LOGGING_SWITCH)
    
    def _convert_dart_to_flutter_format(self, dart_game_state: Dict[str, Any]) -> Dict[str, Any]:
        """Convert Dart game state format to Flutter expected format"""
        try:
            # Phase mapping from Dart camelCase to Flutter snake_case
            phase_mapping = {
                'waitingForPlayers': 'waiting_for_players',
                'dealingCards': 'dealing_cards',
                'playerTurn': 'player_turn',
                'sameRankWindow': 'same_rank_window',
                'specialPlayWindow': 'special_play_window',
                'queenPeekWindow': 'queen_peek_window',
                'turnPendingEvents': 'turn_pending_events',
                'endingRound': 'ending_round',
                'endingTurn': 'ending_turn',
                'recallCalled': 'recall_called',
                'gameEnded': 'game_ended',
                'waiting': 'waiting',
                'setup': 'setup',
                'playing': 'playing',
                'outOfTurn': 'out_of_turn',
                'recall': 'recall',
                'finished': 'finished'
            }
            
            # Extract players and convert to Flutter format
            players_data = []
            dart_players = dart_game_state.get('players', {})
            for player_id, player_data in dart_players.items():
                flutter_player = {
                    'playerId': player_id,
                    'name': player_data.get('name', f'Player_{player_id[:8]}'),
                    'playerType': player_data.get('player_type', 'human'),
                    'hand': player_data.get('hand', []),
                    'visibleCards': player_data.get('visible_cards', []),
                    'points': player_data.get('points', 0),
                    'cardsRemaining': player_data.get('cards_remaining', 4),
                    'isActive': player_data.get('is_active', True),
                    'status': player_data.get('status', 'waiting'),
                    'hasCalledRecall': player_data.get('has_called_recall', False)
                }
                players_data.append(flutter_player)
            
            # Build Flutter game data structure
            flutter_data = {
                'gameId': dart_game_state.get('game_id'),
                'gameName': f"Recall Game {dart_game_state.get('game_id')}",
                'players': players_data,
                'currentPlayer': None,  # Will be set based on current_player_id
                'playerCount': len(players_data),
                'maxPlayers': dart_game_state.get('max_players', 4),
                'minPlayers': dart_game_state.get('min_players', 2),
                'activePlayerCount': len([p for p in players_data if p.get('isActive', True)]),
                'phase': phase_mapping.get(dart_game_state.get('phase', 'waitingForPlayers'), 'waiting_for_players'),
                'status': 'active' if dart_game_state.get('phase') in ['player_turn', 'same_rank_window'] else 'inactive',
                'drawPile': dart_game_state.get('draw_pile', []),
                'discardPile': dart_game_state.get('discard_pile', []),
                'gameStartTime': dart_game_state.get('game_start_time'),
                'lastActivityTime': dart_game_state.get('last_action_time'),
                'winner': dart_game_state.get('winner'),
                'gameEnded': dart_game_state.get('game_ended', False),
                'permission': dart_game_state.get('permission', 'public')
            }
            
            # Set current player if available
            current_player_id = dart_game_state.get('current_player_id')
            if current_player_id and current_player_id in dart_players:
                flutter_data['currentPlayer'] = next(
                    (p for p in players_data if p['playerId'] == current_player_id), 
                    None
                )
            
            return flutter_data
            
        except Exception as e:
            custom_log(f"Error converting Dart to Flutter format: {e}", isOn=LOGGING_SWITCH)
            return {}
        
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
                'same_rank_play',
                'jack_swap',
                'queen_peek',
                'completed_initial_peek'
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
            custom_log("Handling game event event_name: " + event_name + " data: " + str(data), isOn=LOGGING_SWITCH)
            # Route to appropriate game state manager method
            if event_name == 'start_match':
                return self._handle_start_match(session_id, data)
            if event_name == 'completed_initial_peek':
                return self.game_state_manager.on_completed_initial_peek(session_id, data)
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
            elif event_name == 'jack_swap':
                # Add action type to data payload for jack_swap events
                data_with_action = {**data, 'action': 'jack_swap'}
                return self._handle_player_action_through_round(session_id, data_with_action)
            elif event_name == 'queen_peek':
                # Add action type to data payload for queen_peek events
                data_with_action = {**data, 'action': 'queen_peek'}
                return self._handle_player_action_through_round(session_id, data_with_action)
            else:
                return False
                
        except Exception as e:
            return False
    
    def _handle_player_action_through_round(self, session_id: str, data: dict) -> bool:
        """Handle player actions through the Dart service or fallback to Python"""
        try:
            game_id = data.get('game_id') or data.get('room_id')
            custom_log("Handling player action through round game_id: " + game_id + " data: " + str(data), isOn=LOGGING_SWITCH)
            if not game_id:
                return False
            
            # Try to use Dart service first
            if self.dart_manager.is_service_running():
                custom_log("Using Dart service for player action", isOn=LOGGING_SWITCH)
                action = data.get('action', '')
                
                # Send action to Dart service
                success = self.dart_manager.player_action(game_id, session_id, action, data)
                if success:
                    custom_log("Action sent to Dart service successfully", isOn=LOGGING_SWITCH)
                    return True
                else:
                    custom_log("Failed to send action to Dart service, falling back to Python", isOn=LOGGING_SWITCH)
            
            # Fallback to Python logic
            custom_log("Using Python logic for player action", isOn=LOGGING_SWITCH)
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return False
            
            # Get the game round handler
            game_round = game.get_round()
            if not game_round:
                return False
            
            # Handle the player action through the game round and store the result
            action_result = game_round.on_player_action(session_id, data)
            custom_log("Action result: " + str(action_result), isOn=LOGGING_SWITCH)
            # Return the action result
            return action_result
            
        except Exception as e:
            custom_log(f"Error in _handle_player_action_through_round: {e}", isOn=LOGGING_SWITCH)
            return False
    
    def _handle_start_match(self, session_id: str, data: dict) -> bool:
        """Handle start match event - create game in Dart service and Python"""
        try:
            game_id = data.get('game_id') or data.get('room_id')
            if not game_id:
                return False
            
            # Create game in Dart service
            if self.dart_manager.is_service_running():
                success = self.dart_manager.create_game(
                    game_id=game_id,
                    max_players=data.get('max_players', 4),
                    min_players=data.get('min_players', 2),
                    permission=data.get('permission', 'public')
                )
                if success:
                    custom_log(f"Game {game_id} created in Dart service", isOn=LOGGING_SWITCH)
            
            # Also create in Python for fallback
            return self.game_state_manager.on_start_match(session_id, data)
            
        except Exception as e:
            custom_log(f"Error in _handle_start_match: {e}", isOn=LOGGING_SWITCH)
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
            custom_log("Sending event to all players game_id: " + game_id + " event: " + event + " data: " + str(data), isOn=LOGGING_SWITCH)
            # Use direct room broadcast instead of looping through players
            self.websocket_manager.broadcast_to_room(game_id, event, data)
            return True
        except Exception as e:
            custom_log(f"Error sending to all players: {e}", isOn=LOGGING_SWITCH)
            return False


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
            custom_log("Sending partial game state update for game_id: " + game_id + " changed_properties: " + str(changed_properties), isOn=LOGGING_SWITCH)
            game = self.game_state_manager.get_game(game_id)
            if not game:
                return
            
            # Get full game state in Flutter format
            full_game_state = self.game_state_manager._to_flutter_game_data(game)
            
            # DEBUG: Log the full game state phase
            custom_log(f"🔍 _send_game_state_partial_update DEBUG:", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"🔍   Game ID: {game_id}", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"🔍   Changed properties: {changed_properties}", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"🔍   Full game state phase: {full_game_state.get('phase', 'NOT_FOUND')}", level="INFO", isOn=LOGGING_SWITCH)
            
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
                    custom_log(f"🔍   Extracted {prop} -> {flutter_key}: {partial_state[flutter_key]}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Always include core identifiers
            partial_state['gameId'] = game_id
            partial_state['timestamp'] = datetime.now().isoformat()
            
            # DEBUG: Log the final partial state being sent
            custom_log(f"🔍 Final partial state being sent:", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"🔍   partial_state: {partial_state}", level="INFO", isOn=LOGGING_SWITCH)
            
            payload = {
                'event_type': 'game_state_partial_update',
                'game_id': game_id,
                'changed_properties': changed_properties,
                'partial_game_state': partial_state,
            }
            custom_log("Sending partial game state update payload: " + str(payload), isOn=LOGGING_SWITCH)
            self._send_to_all_players(game_id, 'game_state_partial_update', payload)
            
        except Exception as e:
            pass
    
    def _send_player_state_update(self, game_id: str, player_id: str):
        """Send player state update including hand to the specific player"""
        try:
            custom_log(f"Sending player state update for game_id: {game_id} player_id: {player_id}", isOn=LOGGING_SWITCH)
            game = self.game_state_manager.get_game(game_id)
            if not game:
                custom_log(f"Game not found for player state update: {game_id}", isOn=LOGGING_SWITCH)
                return
            
            if player_id not in game.players:
                custom_log(f"Player not found in game for state update: {player_id}", isOn=LOGGING_SWITCH)
                return
            
            player = game.players[player_id]
            
            # Get player session ID
            session_id = game.player_sessions.get(player_id)
            if not session_id:
                # Computer players don't have session IDs, but their status should still be updated in game state
                if player_id.startswith('computer_'):
                    custom_log(f"Computer player {player_id} - no session ID needed", isOn=LOGGING_SWITCH)
                    return
                else:
                    custom_log(f"No session ID found for player {player_id}", isOn=LOGGING_SWITCH)
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
            custom_log(f"Sending player_state_updated to session {session_id} for player {player_id} with status {player.status}", isOn=LOGGING_SWITCH)
            self.websocket_manager.send_to_session(session_id, 'player_state_updated', payload)
            
        except Exception as e:
            custom_log(f"Error in _send_player_state_update: {e}", isOn=LOGGING_SWITCH)
    
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
