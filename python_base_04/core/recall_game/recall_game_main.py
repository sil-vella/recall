"""
Recall Game Main Entry Point

This module serves as the main entry point for the Recall game backend,
initializing all components and integrating with the main system.
"""

from typing import Optional, Dict, Any, List
from tools.logger.custom_logging import custom_log
from .models.game_state import GameStateManager
from .game_logic.game_logic_engine import GameLogicEngine
import time
from .managers.recall_websockets_manager import RecallWebSocketsManager
from .managers.recall_message_system import RecallMessageSystem
from .managers.recall_gameplay_manager import RecallGameplayManager


class RecallGameMain:
    """Main orchestrator for the Recall game backend"""
    
    def __init__(self):
        self.app_manager = None
        self.websocket_manager = None
        self.game_state_manager = None
        self.game_logic_engine = None
        self.recall_ws_manager = None
        self.recall_message_system = None
        self.recall_gameplay_manager = None
        self._initialized = False
    
    def initialize(self, app_manager) -> bool:
        """Initialize the Recall game backend with the main app_manager"""
        try:
            self.app_manager = app_manager
            self.websocket_manager = app_manager.get_websocket_manager()
            
            if not self.websocket_manager:
                custom_log("❌ WebSocket manager not available for Recall game", level="ERROR")
                return False
            
            # Initialize core components
            self.game_state_manager = GameStateManager()
            self.game_logic_engine = GameLogicEngine()
            
            # Initialize gameplay manager and wire handlers
            self.recall_gameplay_manager = RecallGameplayManager()
            self.recall_gameplay_manager.initialize(self.app_manager, self.game_state_manager, self.game_logic_engine)
            self._register_recall_handlers()
            # Initialize Recall-specific WebSocket event bridge (non-core)
            self.recall_ws_manager = RecallWebSocketsManager()
            self.recall_ws_manager.initialize(self.app_manager)

            # Initialize Recall message system (facade)
            self.recall_message_system = RecallMessageSystem()
            self.recall_message_system.initialize(self.app_manager)
            
            self._initialized = True
            custom_log("✅ Recall Game backend initialized successfully")
            return True
            
        except Exception as e:
            custom_log(f"❌ Failed to initialize Recall Game backend: {str(e)}", level="ERROR")
            return False
    
    def _register_recall_handlers(self):
        """Register Recall game handlers with the main WebSocket manager"""
        if not self.websocket_manager:
            custom_log("Warning: WebSocket manager not available")
            return

        # Prefer centralized event listeners API
        listeners = getattr(self.websocket_manager, 'event_listeners', None)
        if not listeners:
            custom_log("Warning: Event listeners not available on WebSocket manager")
            return

        gp = self.recall_gameplay_manager
        listeners.register_custom_listener('join_game', gp.on_join_game)
        listeners.register_custom_listener('recall_leave_game', gp.on_leave_game)
        listeners.register_custom_listener('recall_player_action', gp.on_player_action)
        listeners.register_custom_listener('start_match', gp.on_start_match)
        listeners.register_custom_listener('recall_call_recall', gp.on_call_recall)
        listeners.register_custom_listener('recall_play_out_of_turn', gp.on_play_out_of_turn)
        listeners.register_custom_listener('recall_use_special_power', gp.on_use_special_power)
        listeners.register_custom_listener('recall_initial_peek', gp.on_initial_peek)
        listeners.register_custom_listener('recall_get_public_rooms', gp.on_get_public_rooms)
        listeners.register_custom_listener('recall_game_event', self._handle_recall_game_event)

        custom_log("✅ Recall game handlers registered via WebSocket event listeners")
    
    def _handle_recall_game_event(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle generic recall_game_event and route based on event_type"""
        try:
            custom_log(f"🎯 [recall_game_event] Received event from session {session_id}: {data}")
            
            event_type = data.get('event_type')
            if not event_type:
                custom_log(f"❌ Missing event_type in recall_game_event: {data}", level="ERROR")
                return False
            
            custom_log(f"🎯 Routing recall_game_event: {event_type} from session {session_id}")
            
            # Route to appropriate handler based on event_type
            if event_type == 'get_public_rooms':
                return self.recall_gameplay_manager.on_get_public_rooms(session_id, data)
            elif event_type == 'join_game':
                custom_log(f"🎮 Calling on_join_game for session {session_id} with data: {data}")
                result = self.recall_gameplay_manager.on_join_game(session_id, data)
                custom_log(f"🎮 on_join_game result: {result}")
                return result
            elif event_type == 'start_match':
                custom_log(f"🎮 Calling on_start_match for session {session_id} with data: {data}")
                result = self.recall_gameplay_manager.on_start_match(session_id, data)
                custom_log(f"🎮 on_start_match result: {result}")
                return result
            elif event_type == 'create_room':
                # Route to room creation handler
                return self._handle_create_room(session_id, data)
            else:
                custom_log(f"❌ Unknown event_type: {event_type} in recall_game_event", level="ERROR")
                return False
                
        except Exception as e:
            custom_log(f"❌ Error handling recall_game_event: {e}", level="ERROR")
            return False
    
    def _handle_get_public_rooms(self, data):
        """Handle request for public rooms list"""
        try:
            session_id = data.get('session_id')
            
            if not session_id:
                self._emit_error(session_id, 'Session ID required')
                return False
            
            # Get all public rooms from the WebSocket manager's room manager
            if self.websocket_manager and hasattr(self.websocket_manager, 'room_manager'):
                all_rooms = self.websocket_manager.room_manager.get_all_rooms()
                
                # Filter for public rooms only
                public_rooms = []
                for room_id, room_info in all_rooms.items():
                    if room_info.get('permission') == 'public':
                        public_rooms.append({
                            'room_id': room_id,
                            'room_name': room_info.get('room_name', room_id),
                            'owner_id': room_info.get('owner_id'),
                            'permission': room_info.get('permission'),
                            'current_size': room_info.get('current_size', 0),
                            'max_size': room_info.get('max_size', 4),
                            'min_size': room_info.get('min_size', 2),
                            'created_at': room_info.get('created_at'),
                            'game_type': room_info.get('game_type', 'classic'),
                            'turn_time_limit': room_info.get('turn_time_limit', 30),
                            'auto_start': room_info.get('auto_start', True)
                        })
                
                # Send response
                self._emit_to_session(session_id, 'get_public_rooms_success', {
                    'success': True,
                    'data': public_rooms,
                    'count': len(public_rooms),
                    'timestamp': time.time()
                })
                
                custom_log(f"Sent {len(public_rooms)} public rooms to session {session_id}")
                return True
            else:
                # Fallback: return empty list if room manager not available
                self._emit_to_session(session_id, 'get_public_rooms_success', {
                    'success': True,
                    'data': [],
                    'count': 0,
                    'timestamp': time.time()
                })
                
                custom_log(f"Room manager not available, sent empty public rooms list to session {session_id}")
                return True
        
        except Exception as e:
            custom_log(f"Error in _handle_get_public_rooms: {str(e)}", level="ERROR")
            self._emit_error(session_id, f'Error getting public rooms: {str(e)}')
            return False

    def _handle_create_room(self, session_id, data):
        """Handle room creation request"""
        try:
            import uuid
            from datetime import datetime
            
            # Extract room creation data
            room_name = data.get('room_name', 'New Room')
            permission = data.get('permission', 'public')
            max_players = data.get('max_players', 4)
            min_players = data.get('min_players', 2)
            game_type = data.get('game_type', 'classic')
            turn_time_limit = data.get('turn_time_limit', 30)
            auto_start = data.get('auto_start', True)
            password = data.get('password', None)
            
            # Generate room ID using consistent UUID method
            room_id = f"room_{uuid.uuid4().hex[:8]}"
            
            # Get user ID from session data
            session_data = self.websocket_manager.get_session_data(session_id) if self.websocket_manager else {}
            user_id = session_data.get('user_id') or session_id
            
            custom_log(f"Creating room: {room_id} with owner: {user_id}")
            
            # Create room using WebSocket manager
            if self.websocket_manager:
                success = self.websocket_manager.create_room(
                    room_id=room_id,
                    permission=permission,
                    owner_id=user_id
                )
                
                if success:
                    # Join the room after creation
                    join_success = self.websocket_manager.join_room(room_id, session_id, user_id)
                    
                    if join_success:
                        # Prepare room data for response
                        room_data = {
                            'room_id': room_id,
                            'room_name': room_name,
                            'owner_id': user_id,
                            'permission': permission,
                            'current_size': 1,
                            'max_size': max_players,
                            'min_size': min_players,
                            'created_at': datetime.now().isoformat(),
                            'game_type': game_type,
                            'turn_time_limit': turn_time_limit,
                            'auto_start': auto_start,
                            'password': password
                        }
                        
                        # Get owner_id from memory storage
                        owner_id = self.websocket_manager.get_room_creator(room_id)
                        
                        # Emit success response
                        self._emit_to_session(session_id, 'create_room_success', {
                            'success': True,
                            'room_id': room_id,
                            'room_data': room_data,
                            'owner_id': owner_id,  # Include owner_id from memory
                            'timestamp': time.time()
                        })
                        
                        # Emit room joined event
                        self._emit_to_session(session_id, 'room_joined', {
                            'room_id': room_id,
                            'session_id': session_id,
                            'user_id': user_id,
                            'owner_id': owner_id,  # Include owner_id from memory
                            'timestamp': time.time(),
                            'current_size': 1,
                            'max_size': max_players
                        })
                        
                        custom_log(f"✅ Successfully created and joined room: {room_id} with owner: {user_id}")
                        return True
                    else:
                        custom_log(f"❌ Failed to join room after creation: {room_id}")
                        self._emit_error(session_id, 'Failed to join room after creation')
                        return False
                else:
                    custom_log(f"❌ Failed to create room: {room_id}")
                    self._emit_error(session_id, 'Failed to create room')
                    return False
            else:
                custom_log(f"❌ WebSocket manager not available for room creation")
                self._emit_error(session_id, 'WebSocket manager not available')
                return False
                
        except Exception as e:
            custom_log(f"❌ Error in _handle_create_room: {str(e)}", level="ERROR")
            self._emit_error(session_id, f'Error creating room: {str(e)}')
            return False

    # ==== New unified listener handlers (session_id, data) ====

    # Deprecated: moved to RecallGameplayManager

    # Handlers moved to RecallGameplayManager

    # Handlers moved to RecallGameplayManager

    # Handlers moved to RecallGameplayManager

    # Handlers moved to RecallGameplayManager

    # Handlers moved to RecallGameplayManager

    # Handlers moved to RecallGameplayManager

    # Handlers moved to RecallGameplayManager

    # ==== Helpers ====

    def _broadcast_message(self, room_id: str, payload: Dict[str, Any], sender_session_id: Optional[str] = None):
        try:
            # Use broadcast_message which Flutter listens to as 'message'
            self.websocket_manager.broadcast_message(room_id, payload, sender_session_id)
        except Exception as e:
            custom_log(f"Error broadcasting recall event: {e}")

    def _to_flutter_card(self, card) -> Dict[str, Any]:
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
            'cardId': card.card_id,  # Include the unique card identifier
            'suit': suit,
            'rank': _convert_rank_to_word(rank),
            'points': int(card.points),
            'specialPower': (card.special_power or 'none'),
            'specialPowerDescription': None,
            'specialPowerData': None,
            'displayName': str(card),
            'color': 'red' if suit in ['hearts', 'diamonds'] else 'black',
        }

    def _to_flutter_player(self, player, is_current: bool = False) -> Dict[str, Any]:
        return {
            'id': player.player_id,
            'name': player.name,
            'type': 'human' if player.player_type.value == 'human' else 'computer',
            'hand': [self._to_flutter_card(c) for c in player.hand],
            'visibleCards': [self._to_flutter_card(c) for c in player.visible_cards],
            'score': int(player.calculate_points()),
            'status': 'playing' if is_current else 'ready',
            'isCurrentPlayer': is_current,
            'hasCalledRecall': bool(player.has_called_recall),
        }

    def _to_flutter_phase(self, phase: str) -> str:
        mapping = {
            'waiting_for_players': 'waiting',
            'dealing_cards': 'setup',
            'player_turn': 'playing',
            'out_of_turn_play': 'playing',
            'recall_called': 'recall',
            'game_ended': 'finished',
        }
        return mapping.get(phase, 'waiting')

    def _to_flutter_game_state(self, game) -> Dict[str, Any]:
        players_list: List[Dict[str, Any]] = []
        for pid, p in game.players.items():
            players_list.append(self._to_flutter_player(p, pid == game.current_player_id))

        # Determine game status based on phase
        # Game is 'inactive' when waiting for players, 'active' after match starts
        game_status = 'inactive' if game.phase.value == 'waiting_for_players' else 'active'
        if game.game_ended:
            game_status = 'ended'

        return {
            'gameId': game.game_id,
            'gameName': f'Recall Game {game.game_id[:6]}',
            'players': players_list,
            'currentPlayer': self._to_flutter_player(game.players[game.current_player_id], True) if game.current_player_id and game.current_player_id in game.players else None,
            'phase': self._to_flutter_phase(game.phase.value),
            'status': game_status,
            'drawPile': [],
            'discardPile': [self._to_flutter_card(c) for c in game.discard_pile],
            'centerPile': [],
            'turnNumber': 0,
            'roundNumber': 1,
            'gameStartTime': None,
            'lastActivityTime': None,
            'gameSettings': {},
            'winner': None,
            'errorMessage': None,
        }
    
    def _handle_join_game(self, data):
        """Handle player joining a game"""
        # TODO: Implement game joining logic
        custom_log("Join game handler called")
        return True
    
    def _handle_leave_game(self, data):
        """Handle player leaving a game"""
        # TODO: Implement game leaving logic
        custom_log("Leave game handler called")
        return True
    
    def _handle_player_action(self, data):
        """Handle player action through declarative rules"""
        # TODO: Implement player action logic
        custom_log("Player action handler called")
        return True
    
    def _handle_call_recall(self, data):
        """Handle player calling Recall"""
        # TODO: Implement Recall calling logic
        custom_log("Call Recall handler called")
        return True
    
    def _handle_play_out_of_turn(self, data):
        """Handle out-of-turn card play"""
        # TODO: Implement out-of-turn play logic
        custom_log("Play out of turn handler called")
        return True
    
    def _handle_use_special_power(self, data):
        """Handle special power card usage"""
        # TODO: Implement special power logic
        custom_log("Use special power handler called")
        return True
    
    def _emit_to_session(self, session_id: str, event: str, data: dict):
        """Emit event to a specific session"""
        if self.websocket_manager:
            self.websocket_manager.send_to_session(session_id, event, data)
    
    def _emit_error(self, session_id: str, message: str):
        """Emit error to a specific session"""
        self._emit_to_session(session_id, 'recall_error', {'message': message})
    
    def get_websocket_manager(self):
        """Get the WebSocket manager"""
        return self.websocket_manager if self._initialized else None
    
    def get_game_state_manager(self) -> Optional[GameStateManager]:
        """Get the game state manager"""
        return self.game_state_manager if self._initialized else None
    
    def get_game_logic_engine(self) -> Optional[GameLogicEngine]:
        """Get the game logic engine"""
        return self.game_logic_engine if self._initialized else None
    
    def is_initialized(self) -> bool:
        """Check if the Recall game backend is initialized"""
        return self._initialized
    
    def health_check(self) -> dict:
        """Perform health check on Recall game components"""
        if not self._initialized:
            return {
                'status': 'not_initialized',
                'component': 'recall_game',
                'details': 'Recall game backend not initialized'
            }
        
        try:
            websocket_health = 'healthy' if self.websocket_manager else 'unhealthy'
            state_manager_health = 'healthy' if self.game_state_manager else 'unhealthy'
            logic_engine_health = 'healthy' if self.game_logic_engine else 'unhealthy'
            
            return {
                'status': 'healthy' if all([
                    websocket_health == 'healthy',
                    state_manager_health == 'healthy',
                    logic_engine_health == 'healthy'
                ]) else 'degraded',
                'component': 'recall_game',
                'details': {
                    'websocket_manager': websocket_health,
                    'game_state_manager': state_manager_health,
                    'game_logic_engine': logic_engine_health
                }
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'component': 'recall_game',
                'details': f'Health check failed: {str(e)}'
            }
    
    def cleanup(self):
        """Clean up Recall game resources"""
        try:
            custom_log("✅ Recall Game backend cleaned up successfully")
            
        except Exception as e:
            custom_log(f"❌ Error cleaning up Recall Game backend: {str(e)}", level="ERROR")


# Global instance for easy access
_recall_game_main = None


def initialize_recall_game(app_manager) -> Optional[RecallGameMain]:
    """Initialize the Recall game backend"""
    global _recall_game_main
    
    try:
        _recall_game_main = RecallGameMain()
        success = _recall_game_main.initialize(app_manager)
        
        if success:
            custom_log("✅ Recall Game backend initialized successfully")
            return _recall_game_main
        else:
            custom_log("❌ Failed to initialize Recall Game backend", level="ERROR")
            return None
            
    except Exception as e:
        custom_log(f"❌ Error initializing Recall Game backend: {str(e)}", level="ERROR")
        return None


def get_recall_game_main() -> Optional[RecallGameMain]:
    """Get the global Recall game main instance"""
    return _recall_game_main


def get_recall_game_websocket_manager():
    """Get the Recall game WebSocket manager"""
    if _recall_game_main:
        return _recall_game_main.get_websocket_manager()
    return None


def get_recall_game_state_manager():
    """Get the Recall game state manager"""
    if _recall_game_main:
        return _recall_game_main.get_game_state_manager()
    return None


def get_recall_game_logic_engine():
    """Get the Recall game logic engine"""
    if _recall_game_main:
        return _recall_game_main.get_game_logic_engine()
    return None 