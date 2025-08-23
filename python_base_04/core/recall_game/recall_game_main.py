"""
Recall Game Main Entry Point

This module serves as the main entry point for the Recall game backend,
initializing all components and integrating with the main system.
"""

from typing import Optional, Dict, Any, List
from tools.logger.custom_logging import custom_log
from .managers.game_state import GameStateManager
from .game_logic.game_logic_engine import GameLogicEngine
import time
from .managers.recall_websockets_manager import RecallWebSocketsManager
from .managers.recall_message_system import RecallMessageSystem
# RecallGameplayManager consolidated into GameStateManager


class RecallGameMain:
    """Main orchestrator for the Recall game backend"""
    
    def __init__(self):
        self.app_manager = None
        self.websocket_manager = None
        self.game_state_manager = None
        self.game_logic_engine = None
        self.recall_ws_manager = None
        self.recall_message_system = None
# recall_gameplay_manager consolidated into game_state_manager
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
            
            # Initialize game state manager with WebSocket support
            self.game_state_manager.initialize(self.app_manager, self.game_logic_engine)
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
