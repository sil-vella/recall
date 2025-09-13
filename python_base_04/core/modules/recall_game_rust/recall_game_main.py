"""
Recall Game Main Entry Point - Rust Bridge

This module serves as the main entry point for the Recall game backend,
providing a Python bridge to the Rust implementation of the game logic.
"""

from typing import Optional, Dict, Any, List
from tools.logger.custom_logging import custom_log
from core.modules.base_module import BaseModule
from core.managers.jwt_manager import JWTManager, TokenType
from flask import request, jsonify
import time
import json
import ctypes
from ctypes import c_char_p, c_void_p, c_int, Structure, POINTER
import os
import sys


class RustGameStateManager:
    """Python bridge to Rust GameStateManager"""
    
    def __init__(self, rust_lib):
        self.rust_lib = rust_lib
        self.engine_ptr = None
        self._setup_function_signatures()
    
    def _setup_function_signatures(self):
        """Setup C function signatures for FFI"""
        # Game management
        self.rust_lib.create_game.argtypes = [c_void_p, c_char_p]
        self.rust_lib.create_game.restype = c_char_p
        
        self.rust_lib.get_game.argtypes = [c_void_p, c_char_p]
        self.rust_lib.get_game.restype = c_char_p
        
        self.rust_lib.get_available_games.argtypes = [c_void_p]
        self.rust_lib.get_available_games.restype = c_char_p
        
        # Game state operations
        self.rust_lib.to_flutter_game_data.argtypes = [c_void_p, c_char_p]
        self.rust_lib.to_flutter_game_data.restype = c_char_p
        
        self.rust_lib.to_flutter_player_data.argtypes = [c_void_p, c_char_p, c_char_p, c_int]
        self.rust_lib.to_flutter_player_data.restype = c_char_p
    
    def initialize(self, app_manager, game_logic_engine):
        """Initialize the Rust game state manager"""
        try:
            # Create the Rust engine instance
            self.engine_ptr = self.rust_lib.create_engine()
            if not self.engine_ptr:
                custom_log("Failed to create Rust game engine", level="ERROR")
                return False
            
            custom_log("Rust GameStateManager initialized successfully", level="INFO")
            return True
        except Exception as e:
            custom_log(f"Error initializing Rust GameStateManager: {e}", level="ERROR")
            return False
    
    def create_game(self, max_players: int = 4, min_players: int = 2, permission: str = 'public') -> str:
        """Create a new game"""
        try:
            config = {
                "max_players": max_players,
                "min_players": min_players,
                "permission": permission
            }
            config_json = json.dumps(config).encode('utf-8')
            result = self.rust_lib.create_game(self.engine_ptr, config_json)
            game_id = result.decode('utf-8')
            custom_log(f"Created game with ID: {game_id}", level="INFO")
            return game_id
        except Exception as e:
            custom_log(f"Error creating game: {e}", level="ERROR")
            return None
    
    def get_game(self, game_id: str) -> Optional[Dict[str, Any]]:
        """Get a game by ID"""
        try:
            game_id_bytes = game_id.encode('utf-8')
            result = self.rust_lib.get_game(self.engine_ptr, game_id_bytes)
            if result:
                return json.loads(result.decode('utf-8'))
            return None
        except Exception as e:
            custom_log(f"Error getting game {game_id}: {e}", level="ERROR")
            return None
    
    def get_available_games(self) -> List[Dict[str, Any]]:
        """Get all available games"""
        try:
            result = self.rust_lib.get_available_games(self.engine_ptr)
            if result:
                return json.loads(result.decode('utf-8'))
            return []
        except Exception as e:
            custom_log(f"Error getting available games: {e}", level="ERROR")
            return []
    
    def _to_flutter_game_data(self, game: Dict[str, Any]) -> Dict[str, Any]:
        """Convert game state to Flutter format"""
        try:
            game_json = json.dumps(game).encode('utf-8')
            result = self.rust_lib.to_flutter_game_data(self.engine_ptr, game_json)
            if result:
                return json.loads(result.decode('utf-8'))
            return {}
        except Exception as e:
            custom_log(f"Error converting game data: {e}", level="ERROR")
            return {}
    
    def _to_flutter_player_data(self, player: Dict[str, Any], is_current: bool = False) -> Dict[str, Any]:
        """Convert player data to Flutter format"""
        try:
            player_json = json.dumps(player).encode('utf-8')
            result = self.rust_lib.to_flutter_player_data(
                self.engine_ptr, 
                player_json, 
                b"",  # game_id not needed for player conversion
                c_int(1 if is_current else 0)
            )
            if result:
                return json.loads(result.decode('utf-8'))
            return {}
        except Exception as e:
            custom_log(f"Error converting player data: {e}", level="ERROR")
            return {}


class RustGameEventCoordinator:
    """Python bridge to Rust GameEventCoordinator"""
    
    def __init__(self, game_state_manager, websocket_manager):
        self.game_state_manager = game_state_manager
        self.websocket_manager = websocket_manager
        self.rust_lib = game_state_manager.rust_lib
        self.engine_ptr = game_state_manager.engine_ptr
        self.registered_events = []
        self._setup_function_signatures()
    
    def _setup_function_signatures(self):
        """Setup C function signatures for FFI"""
        # Event handling
        self.rust_lib.handle_game_event.argtypes = [c_void_p, c_char_p, c_char_p, c_char_p]
        self.rust_lib.handle_game_event.restype = c_int
        
        self.rust_lib.register_game_event_listeners.argtypes = [c_void_p]
        self.rust_lib.register_game_event_listeners.restype = c_int
    
    def register_game_event_listeners(self) -> bool:
        """Register WebSocket event listeners for Recall game events"""
        try:
            # Register events in Rust
            result = self.rust_lib.register_game_event_listeners(self.engine_ptr)
            if result == 1:
                # Define the same events for Python tracking
                self.registered_events = [
                    'start_match', 'draw_card', 'play_card', 'discard_card',
                    'take_from_discard', 'call_recall', 'same_rank_play',
                    'jack_swap', 'queen_peek', 'completed_initial_peek'
                ]
                custom_log("Rust game event listeners registered successfully", level="INFO")
                return True
            return False
        except Exception as e:
            custom_log(f"Error registering game event listeners: {e}", level="ERROR")
            return False
    
    def handle_game_event(self, session_id: str, event_name: str, data: Dict[str, Any]) -> bool:
        """Handle incoming game events and route to Rust"""
        try:
            event_data = {
                "session_id": session_id,
                "event_name": event_name,
                "data": data
            }
            event_json = json.dumps(event_data).encode('utf-8')
            
            result = self.rust_lib.handle_game_event(
                self.engine_ptr,
                session_id.encode('utf-8'),
                event_name.encode('utf-8'),
                event_json
            )
            
            return result == 1
        except Exception as e:
            custom_log(f"Error handling game event {event_name}: {e}", level="ERROR")
            return False
    
    def get_registered_events(self) -> List[str]:
        """Get list of registered event names"""
        return self.registered_events.copy()
    
    def is_event_registered(self, event_name: str) -> bool:
        """Check if a specific event is registered"""
        return event_name in self.registered_events
    
    def health_check(self) -> Dict[str, Any]:
        """Perform health check on event coordinator"""
        try:
            return {
                'status': 'healthy',
                'component': 'rust_game_event_coordinator',
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
                'component': 'rust_game_event_coordinator',
                'details': f'Health check failed: {str(e)}'
            }


class RecallGameMain(BaseModule):
    """Main orchestrator for the Recall game backend - Rust Bridge"""
    
    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.websocket_manager = None
        self.game_state_manager = None
        self.game_event_coordinator = None
        self.rust_lib = None
    
    def initialize(self, app_manager) -> bool:
        """Initialize the Recall game backend with the main app_manager"""
        try:
            # Call parent class initialize
            super().initialize(app_manager)
            
            # Set Flask app reference for route registration
            self.app = app_manager.flask_app
            
            self.websocket_manager = app_manager.get_websocket_manager()
            
            if not self.websocket_manager:
                custom_log("WebSocket manager not available", level="ERROR")
                return False
            
            # Load Rust library
            if not self._load_rust_library():
                custom_log("Failed to load Rust library", level="ERROR")
                return False
            
            # Initialize Rust game state manager
            self.game_state_manager = RustGameStateManager(self.rust_lib)
            if not self.game_state_manager.initialize(self.app_manager, None):
                custom_log("Failed to initialize Rust GameStateManager", level="ERROR")
                return False
            
            # Initialize Rust game event coordinator
            self.game_event_coordinator = RustGameEventCoordinator(self.game_state_manager, self.websocket_manager)
            
            # Attach coordinator and game state manager to app_manager so other modules can access them
            setattr(self.app_manager, 'game_event_coordinator', self.game_event_coordinator)
            setattr(self.app_manager, 'game_state_manager', self.game_state_manager)
            
            # Register WebSocket event listeners for game events
            if not self.game_event_coordinator.register_game_event_listeners():
                custom_log("Failed to register game event listeners", level="ERROR")
                return False
            
            # Register routes now that Flask app is available
            self.register_routes()
            
            custom_log("Recall Game Rust Bridge initialized successfully", level="INFO")
            self._initialized = True
            return True
            
        except Exception as e:
            custom_log(f"Error initializing Recall Game Rust Bridge: {e}", level="ERROR")
            return False
    
    def _load_rust_library(self) -> bool:
        """Load the Rust library for FFI communication"""
        try:
            # Determine the library path based on platform
            if sys.platform.startswith('linux'):
                lib_name = 'librecall_game.so'
            elif sys.platform == 'darwin':
                lib_name = 'librecall_game.dylib'
            elif sys.platform.startswith('win'):
                lib_name = 'recall_game.dll'
            else:
                custom_log(f"Unsupported platform: {sys.platform}", level="ERROR")
                return False
            
            # Try to find the library in common locations
            possible_paths = [
                f"./target/release/{lib_name}",
                f"./target/debug/{lib_name}",
                f"./recall_game_rust/target/release/{lib_name}",
                f"./recall_game_rust/target/debug/{lib_name}",
                f"./python_base_04/core/modules/recall_game_rust/target/release/{lib_name}",
                f"./python_base_04/core/modules/recall_game_rust/target/debug/{lib_name}",
            ]
            
            lib_path = None
            for path in possible_paths:
                if os.path.exists(path):
                    lib_path = path
                    break
            
            if not lib_path:
                custom_log(f"Rust library not found. Searched paths: {possible_paths}", level="ERROR")
                return False
            
            # Load the library
            self.rust_lib = ctypes.CDLL(lib_path)
            custom_log(f"Loaded Rust library from: {lib_path}", level="INFO")
            
            # Setup basic function signatures
            self.rust_lib.create_engine.argtypes = []
            self.rust_lib.create_engine.restype = c_void_p
            
            return True
            
        except Exception as e:
            custom_log(f"Error loading Rust library: {e}", level="ERROR")
            return False
    
    def register_routes(self):
        """Register all Recall game routes."""
        
        # Register the get-available-games endpoint with JWT authentication
        self._register_route_helper("/userauth/recall/get-available-games", self.get_available_games, methods=["GET"], auth="jwt")
        
        # Register the find-room endpoint with JWT authentication
        self._register_route_helper("/userauth/recall/find-room", self.find_room, methods=["POST"], auth="jwt")
    

    
    def get_available_games(self):
        """Get all available games that can be joined (JWT protected endpoint)"""
        try:
            # Verify JWT token
            auth_header = request.headers.get('Authorization')
            
            if not auth_header:
                return jsonify({
                    "success": False,
                    "message": "No Authorization header provided",
                    "error": "Missing JWT token"
                }), 401
            
            # Extract token from Authorization header
            if auth_header.startswith('Bearer '):
                token = auth_header[7:]  # Remove 'Bearer ' prefix
            else:
                token = auth_header
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Verify the token
            payload = jwt_manager.verify_token(token, TokenType.ACCESS)
            
            if not payload:
                return jsonify({
                    "success": False,
                    "message": "Invalid or expired JWT token",
                    "error": "Token validation failed"
                }), 401
            
            # Get available games from game state manager
            available_games = self.game_state_manager.get_available_games()
            
            # Return success response with available games
            response_data = {
                "success": True,
                "message": f"Found {len(available_games)} available games",
                "games": available_games,
                "count": len(available_games),
                "timestamp": time.time()
            }
            return jsonify(response_data), 200
            
        except Exception as e:
            return jsonify({
                "success": False,
                "message": "Failed to retrieve available games",
                "error": str(e)
            }), 500
    
    def find_room(self):
        """Find a specific room by room ID (JWT protected endpoint)"""
        try:
            # Verify JWT token
            auth_header = request.headers.get('Authorization')
            
            if not auth_header:
                return jsonify({
                    "success": False,
                    "message": "No Authorization header provided",
                    "error": "Missing JWT token"
                }), 401
            
            # Extract token from Authorization header
            if auth_header.startswith('Bearer '):
                token = auth_header[7:]  # Remove 'Bearer ' prefix
            else:
                token = auth_header
            
            # Get JWT manager from app_manager
            jwt_manager = self.app_manager.jwt_manager
            
            # Verify the token
            payload = jwt_manager.verify_token(token, TokenType.ACCESS)
            
            if not payload:
                return jsonify({
                    "success": False,
                    "message": "Invalid or expired JWT token",
                    "error": "Token validation failed"
                }), 401
            
            # Get room ID from request body
            data = request.get_json()
            if not data or 'room_id' not in data:
                return jsonify({
                    "success": False,
                    "message": "Room ID is required",
                    "error": "Missing room_id in request body"
                }), 400
            
            room_id = data['room_id']
            
            # Get game info from game state manager (games use room_id as game_id)
            game = self.game_state_manager.get_game(room_id)
            
            if not game:
                return jsonify({
                    "success": False,
                    "message": f"Game '{room_id}' not found",
                    "error": "Game does not exist"
                }), 404
            
            # Convert game to Flutter-compatible format using GameStateManager's method
            game_info = self.game_state_manager._to_flutter_game_data(game)
            
            # Get room info from WebSocket manager to include permission and password requirement
            room_info = self.websocket_manager.get_room_info(room_id)
            if room_info:
                # Add room permission info to game info
                game_info['room_permission'] = room_info.get('permission', 'public')
                game_info['requires_password'] = room_info.get('permission') == 'private'
                # Don't include actual password for security
            
            # Return success response with game info
            response_data = {
                "success": True,
                "message": f"Game '{room_id}' found",
                "game": game_info,
                "timestamp": time.time()
            }
            return jsonify(response_data), 200
            
        except Exception as e:
            return jsonify({
                "success": False,
                "message": "Failed to find game",
                "error": str(e)
            }), 500
    
    
    def get_game_event_coordinator(self) -> Optional[GameEventCoordinator]:
        """Get the game event coordinator"""
        return self.game_event_coordinator if self._initialized else None
    
    def is_initialized(self) -> bool:
        """Check if the Recall game backend is initialized"""
        return self._initialized
    
    def health_check(self) -> dict:
        """Perform health check on Recall game components"""
        if not self._initialized:
            return {
                'status': 'not_initialized',
                'component': 'recall_game_rust_bridge',
                'details': 'Recall game Rust bridge not initialized'
            }
        
        try:
            websocket_health = 'healthy' if self.websocket_manager else 'unhealthy'
            rust_lib_health = 'healthy' if self.rust_lib else 'unhealthy'
            state_manager_health = 'healthy' if self.game_state_manager else 'unhealthy'
            event_coordinator_health = 'healthy' if self.game_event_coordinator else 'unhealthy'
            
            # Get detailed health from Rust components
            state_manager_details = {}
            event_coordinator_details = {}
            
            if self.game_state_manager:
                state_manager_details = {
                    'rust_engine_available': self.game_state_manager.engine_ptr is not None,
                    'rust_lib_loaded': self.game_state_manager.rust_lib is not None
                }
            
            if self.game_event_coordinator:
                event_coordinator_details = self.game_event_coordinator.health_check().get('details', {})
            
            return {
                'status': 'healthy' if all([
                    websocket_health == 'healthy',
                    rust_lib_health == 'healthy',
                    state_manager_health == 'healthy',
                    event_coordinator_health == 'healthy'
                ]) else 'degraded',
                'component': 'recall_game_rust_bridge',
                'details': {
                    'websocket_manager': websocket_health,
                    'rust_library': rust_lib_health,
                    'rust_game_state_manager': {
                        'status': state_manager_health,
                        'details': state_manager_details
                    },
                    'rust_game_event_coordinator': {
                        'status': event_coordinator_health,
                        'details': event_coordinator_details
                    }
                }
            }
            
        except Exception as e:
            return {
                'status': 'unhealthy',
                'component': 'recall_game_rust_bridge',
                'details': f'Health check failed: {str(e)}'
            }
    
    def cleanup(self):
        """Clean up Recall game resources"""
        try:
            # Clean up Rust engine if it exists
            if self.game_state_manager and self.game_state_manager.engine_ptr:
                # Call Rust cleanup function if available
                if hasattr(self.rust_lib, 'destroy_engine'):
                    self.rust_lib.destroy_engine.argtypes = [c_void_p]
                    self.rust_lib.destroy_engine(self.game_state_manager.engine_ptr)
                    custom_log("Rust game engine destroyed", level="INFO")
            
            # Clear references
            self.game_state_manager = None
            self.game_event_coordinator = None
            self.rust_lib = None
            
            custom_log("Recall Game Rust Bridge cleaned up", level="INFO")
        except Exception as e:
            custom_log(f"Error during cleanup: {e}", level="ERROR")


# Global instance for easy access
_recall_game_main = None


def initialize_recall_game(app_manager) -> Optional[RecallGameMain]:
    """Initialize the Recall game backend"""
    global _recall_game_main
    
    try:
        _recall_game_main = RecallGameMain()
        success = _recall_game_main.initialize(app_manager)
        
        if success:
            return _recall_game_main
        else:
            return None
            
    except Exception as e:
        return None


def get_recall_game_main() -> Optional[RecallGameMain]:
    """Get the global Recall game main instance"""
    return _recall_game_main
