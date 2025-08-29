"""
Game Event Coordinator for Recall Game

This module handles all WebSocket event coordination for the Recall game,
including event registration, routing, and handling.
"""

from typing import Dict, Any, Optional
from tools.logger.custom_logging import custom_log


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
                return self.game_state_manager.on_player_action(session_id, 'draw_from_deck', data)
            elif event_name == 'play_card':
                return self.game_state_manager.on_player_action(session_id, 'play_card', data)
            elif event_name == 'discard_card':
                return self.game_state_manager.on_player_action(session_id, 'discard_card', data)
            elif event_name == 'take_from_discard':
                return self.game_state_manager.on_player_action(session_id, 'take_from_discard', data)
            elif event_name == 'call_recall':
                return self.game_state_manager.on_player_action(session_id, 'call_recall', data)
            else:
                custom_log(f"⚠️ [RECALL-GAME] Unknown game event: '{event_name}'")
                return False
                
        except Exception as e:
            custom_log(f"❌ [RECALL-GAME] Error handling game event: {e}", level="ERROR")
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
