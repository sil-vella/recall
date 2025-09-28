"""
Recall Game Main Entry Point

This module serves as the main entry point for the Recall game backend,
initializing all components and integrating with the main system.
"""

from typing import Optional, Dict, Any, List
from tools.logger.custom_logging import custom_log
from core.modules.base_module import BaseModule

from core.managers.jwt_manager import JWTManager, TokenType
# from .game_logic.game_state import GameStateManager  # This is a Dart file, not Python
from .game_logic.game_event_coordinator import GameEventCoordinator
from flask import request, jsonify
import time
# RecallGameplayManager consolidated into GameStateManager

# Logging switch for this module
LOGGING_SWITCH = True

class RecallGameMain(BaseModule):
    """Main orchestrator for the Recall game backend"""
    
    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.websocket_manager = None
        self.game_state_manager = None
        self.game_event_coordinator = None
    
    def initialize(self, app_manager) -> bool:
        """Initialize the Recall game backend with the main app_manager"""
        try:
            custom_log("Starting RecallGameMain initialization...", isOn=LOGGING_SWITCH)
            
            # Call parent class initialize
            super().initialize(app_manager)
            custom_log("Parent class initialized successfully", isOn=LOGGING_SWITCH)
            
            # Set Flask app reference for route registration
            self.app = app_manager.flask_app
            custom_log("Flask app reference set", isOn=LOGGING_SWITCH)
            
            self.websocket_manager = app_manager.get_websocket_manager()
            
            if not self.websocket_manager:
                custom_log("ERROR: WebSocket manager not found", isOn=LOGGING_SWITCH)
                return False
            
            custom_log("WebSocket manager obtained successfully", isOn=LOGGING_SWITCH)
            
            # Initialize core components
            # Note: Using Dart service for game logic, so no Python GameStateManager needed
            custom_log("Initializing GameEventCoordinator...", isOn=LOGGING_SWITCH)
            
            # Initialize game event coordinator (Python class that communicates with Dart service)
            self.game_event_coordinator = GameEventCoordinator(None, self.websocket_manager)  # Pass None for game_state_manager since we use Dart service
            custom_log("GameEventCoordinator created successfully", isOn=LOGGING_SWITCH)
            
            # Attach coordinator to app_manager so other modules can access it
            setattr(self.app_manager, 'game_event_coordinator', self.game_event_coordinator)
            custom_log("GameEventCoordinator attached to app_manager", isOn=LOGGING_SWITCH)
            
            # Register WebSocket event listeners for game events
            custom_log("Registering WebSocket event listeners...", isOn=LOGGING_SWITCH)
            listeners_registered = self.game_event_coordinator.register_game_event_listeners()
            if listeners_registered:
                custom_log("WebSocket event listeners registered successfully", isOn=LOGGING_SWITCH)
            else:
                custom_log("WARNING: Failed to register WebSocket event listeners", isOn=LOGGING_SWITCH)
            
            # Register routes now that Flask app is available
            custom_log("Registering Flask routes...", isOn=LOGGING_SWITCH)
            self.register_routes()
            custom_log("Flask routes registered successfully", isOn=LOGGING_SWITCH)
            
            self._initialized = True
            custom_log("RecallGameMain initialization completed successfully!", isOn=LOGGING_SWITCH)
            return True
            
        except Exception as e:
            custom_log(f"ERROR: RecallGameMain initialization failed: {e}", isOn=LOGGING_SWITCH)
            return False
    
    def register_routes(self):
        """Register all Recall game routes."""
        custom_log("Starting route registration for RecallGameMain...", isOn=LOGGING_SWITCH)
        
        # Register the get-available-games endpoint with JWT authentication
        self._register_route_helper("/userauth/recall/get-available-games", self.get_available_games, methods=["GET"], auth="jwt")
        custom_log("Registered route: /userauth/recall/get-available-games", isOn=LOGGING_SWITCH)
        
        # Register the find-room endpoint with JWT authentication
        self._register_route_helper("/userauth/recall/find-room", self.find_room, methods=["POST"], auth="jwt")
        custom_log("Registered route: /userauth/recall/find-room", isOn=LOGGING_SWITCH)
        
        custom_log("All RecallGameMain routes registered successfully", isOn=LOGGING_SWITCH)
    

    
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
            # available_games = self.game_state_manager.get_available_games()  # Need to fix this
            available_games = []  # Temporary placeholder
            
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
            # game = self.game_state_manager.get_game(room_id)  # Need to fix this
            
            # if not game:
            #     return jsonify({
            #         "success": False,
            #         "message": f"Game '{room_id}' not found",
            #         "error": "Game does not exist"
            #     }), 404
            
            # Convert game to Flutter-compatible format using GameStateManager's method
            # game_info = self.game_state_manager._to_flutter_game_data(game)  # Need to fix this
            game_info = {"room_id": room_id, "status": "placeholder"}  # Temporary placeholder
            
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
                'component': 'recall_game',
                'details': 'Recall game backend not initialized'
            }
        
        try:
            websocket_health = 'healthy' if self.websocket_manager else 'unhealthy'
            state_manager_health = 'healthy' if self.game_state_manager else 'unhealthy'
            event_coordinator_health = 'healthy' if self.game_event_coordinator else 'unhealthy'
            
            return {
                'status': 'healthy' if all([
                    websocket_health == 'healthy',
                    state_manager_health == 'healthy',
                    event_coordinator_health == 'healthy'
                ]) else 'degraded',
                'component': 'recall_game',
                'details': {
                    'websocket_manager': websocket_health,
                    'game_state_manager': state_manager_health,
                    'game_event_coordinator': event_coordinator_health
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
            pass
        except Exception as e:
            pass


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
