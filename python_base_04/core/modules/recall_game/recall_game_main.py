"""
Recall Game Main Entry Point

This module serves as the main entry point for the Recall game backend,
initializing all components and integrating with the main system.
"""

from typing import Optional, Dict, Any, List
from tools.logger.custom_logging import custom_log
from core.modules.base_module import BaseModule
from core.managers.jwt_manager import JWTManager, TokenType
from .managers.game_state import GameStateManager
from .game_logic.game_logic_engine import GameLogicEngine
from flask import request, jsonify
import time
# RecallGameplayManager consolidated into GameStateManager


class RecallGameMain(BaseModule):
    """Main orchestrator for the Recall game backend"""
    
    def __init__(self, app_manager=None):
        super().__init__(app_manager)
        self.websocket_manager = None
        self.game_state_manager = None
        self.game_logic_engine = None
        self.recall_ws_manager = None
        # recall_gameplay_manager consolidated into game_state_manager
    
    def initialize(self, app_manager) -> bool:
        """Initialize the Recall game backend with the main app_manager"""
        try:
            # Call parent class initialize
            super().initialize(app_manager)
            
            # Set Flask app reference for route registration
            self.app = app_manager.flask_app
            
            self.websocket_manager = app_manager.get_websocket_manager()
            
            if not self.websocket_manager:
                custom_log("❌ WebSocket manager not available for Recall game", level="ERROR")
                return False
            
            # Initialize core components
            self.game_state_manager = GameStateManager()
            self.game_logic_engine = GameLogicEngine()
            
            # Initialize game state manager with WebSocket support
            self.game_state_manager.initialize(self.app_manager, self.game_logic_engine)
            
            # Register routes now that Flask app is available
            self.register_routes()
            
            self._initialized = True
            custom_log("✅ Recall Game backend initialized successfully")
            return True
            
        except Exception as e:
            custom_log(f"❌ Failed to initialize Recall Game backend: {str(e)}", level="ERROR")
            return False
    
    def register_routes(self):
        """Register all Recall game routes."""
        custom_log("Registering Recall game routes...")
        
        # Register the get-available-games endpoint with JWT authentication
        self._register_route_helper("/userauth/recall/get-available-games", self.get_available_games, methods=["GET"], auth="jwt")
        
        custom_log(f"Recall game module registered {len(self.registered_routes)} routes")
    
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
            
            custom_log(f"✅ Available games retrieved successfully for user: {payload.get('user_id')}, found {len(available_games)} games")
            return jsonify(response_data), 200
            
        except Exception as e:
            custom_log(f"❌ Error in get_available_games endpoint: {e}", level="ERROR")
            return jsonify({
                "success": False,
                "message": "Failed to retrieve available games",
                "error": str(e)
            }), 500
    
    
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
