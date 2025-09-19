"""
Dart Subprocess Manager for Recall Game

This module manages communication with the Dart game service subprocess,
handling all game logic through the persistent Dart service.
"""

import subprocess
import json
import threading
import time
import os
from typing import Dict, Any, Optional, Callable
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '../../../../..'))
from tools.logger.custom_logging import custom_log

LOGGING_SWITCH = False


class DartSubprocessManager:
    """Manages communication with the Dart game service subprocess"""
    
    def __init__(self):
        self.dart_process = None
        self.is_running = False
        self.message_queue = []
        self.response_handlers = {}
        self.message_id_counter = 0
        self.lock = threading.Lock()
        
    def start_dart_service(self, dart_service_path: str) -> bool:
        """Start the Dart game service subprocess"""
        try:
            custom_log("Starting Dart game service...", isOn=LOGGING_SWITCH)
            
            # Start the Dart subprocess
            self.dart_process = subprocess.Popen(
                ['dart', 'run', dart_service_path],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=0,  # Unbuffered
                cwd=os.path.dirname(os.path.abspath(dart_service_path))  # Set working directory
            )
            
            # Start the response reader thread
            self.response_thread = threading.Thread(target=self._read_responses)
            self.response_thread.daemon = True
            self.response_thread.start()
            
            self.is_running = True
            
            # Send health check to verify connection
            if self.health_check():
                custom_log("Dart game service started successfully", isOn=LOGGING_SWITCH)
                return True
            else:
                custom_log("Dart game service failed health check", isOn=LOGGING_SWITCH)
                return False
                
        except Exception as e:
            custom_log(f"Error starting Dart service: {e}", isOn=LOGGING_SWITCH)
            return False
    
    def stop_dart_service(self):
        """Stop the Dart game service subprocess"""
        try:
            if self.dart_process:
                self.dart_process.terminate()
                self.dart_process.wait(timeout=5)
                self.is_running = False
                custom_log("Dart game service stopped", isOn=LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"Error stopping Dart service: {e}", isOn=LOGGING_SWITCH)
    
    def _read_responses(self):
        """Read responses from Dart service in a separate thread"""
        try:
            while self.is_running and self.dart_process:
                line = self.dart_process.stdout.readline()
                if not line:
                    break
                    
                try:
                    response = json.loads(line.strip())
                    self._handle_response(response)
                except json.JSONDecodeError as e:
                    custom_log(f"Invalid JSON response from Dart: {e}", isOn=LOGGING_SWITCH)
                    
        except Exception as e:
            custom_log(f"Error reading Dart responses: {e}", isOn=LOGGING_SWITCH)
    
    def _handle_response(self, response: Dict[str, Any]):
        """Handle response from Dart service"""
        try:
            if response.get('success'):
                data = response.get('data', {})
                action = data.get('action', '')
                
                # Handle specific responses
                if action == 'health_check':
                    custom_log("Dart service health check successful", isOn=LOGGING_SWITCH)
                elif action in ['create_game', 'join_game', 'player_action', 'get_game_state', 'get_player_state']:
                    # These responses will be handled by the calling code
                    pass
                    
            else:
                error = response.get('error', 'Unknown error')
                custom_log(f"Dart service error: {error}", isOn=LOGGING_SWITCH)
                
        except Exception as e:
            custom_log(f"Error handling Dart response: {e}", isOn=LOGGING_SWITCH)
    
    def _send_message(self, message: Dict[str, Any]) -> bool:
        """Send message to Dart service"""
        try:
            if not self.is_running or not self.dart_process:
                custom_log("Dart service not running", isOn=LOGGING_SWITCH)
                return False
            
            message_json = json.dumps(message) + '\n'
            self.dart_process.stdin.write(message_json)
            self.dart_process.stdin.flush()
            return True
            
        except Exception as e:
            custom_log(f"Error sending message to Dart: {e}", isOn=LOGGING_SWITCH)
            return False
    
    def create_game(self, game_id: str, max_players: int = 4, min_players: int = 2, permission: str = 'public') -> bool:
        """Create a new game in the Dart service"""
        message = {
            'action': 'create_game',
            'game_id': game_id,
            'data': {
                'max_players': max_players,
                'min_players': min_players,
                'permission': permission,
            }
        }
        return self._send_message(message)
    
    def join_game(self, game_id: str, player_id: str, player_name: str, player_type: str = 'human', difficulty: str = 'medium') -> bool:
        """Join a player to a game in the Dart service"""
        message = {
            'action': 'join_game',
            'game_id': game_id,
            'data': {
                'player_id': player_id,
                'player_name': player_name,
                'player_type': player_type,
                'difficulty': difficulty,
            }
        }
        return self._send_message(message)
    
    def add_player(self, game_id: str, player_data: Dict[str, Any]) -> bool:
        """Add a player to a game in the Dart service (alias for join_game)"""
        return self.join_game(
            game_id=game_id,
            player_id=player_data.get('player_id', ''),
            player_name=player_data.get('player_name', 'Player'),
            player_type=player_data.get('player_type', 'human'),
            difficulty=player_data.get('difficulty', 'medium')
        )
    
    def start_game(self, game_id: str) -> bool:
        """Start a game in the Dart service"""
        message = {
            'action': 'start_game',
            'game_id': game_id,
            'data': {}
        }
        return self._send_message(message)
    
    def player_action(self, game_id: str, session_id: str, action: str, data: Dict[str, Any]) -> bool:
        """Send player action to the Dart service"""
        message = {
            'action': 'player_action',
            'game_id': game_id,
            'data': {
                'session_id': session_id,
                'action': action,
                **data
            }
        }
        return self._send_message(message)
    
    def get_game_state(self, game_id: str) -> Optional[Dict[str, Any]]:
        """Get game state from the Dart service"""
        message = {
            'action': 'get_game_state',
            'game_id': game_id,
            'data': {}
        }
        
        if not self._send_message(message):
            return None
        
        # Return a mock game state for now
        # In a real implementation, this would wait for the actual response
        return {
            'status': 'success',
            'message': 'Game state retrieved',
            'game_state': {
                'game_id': game_id,
                'status': 'active',
                'phase': 'player_turn',
                'current_player': 0,
                'players': [],
                'deck_count': 52,
                'discard_pile': []
            }
        }
    
    def get_player_state(self, game_id: str, player_id: str) -> bool:
        """Get player state from the Dart service"""
        message = {
            'action': 'get_player_state',
            'game_id': game_id,
            'data': {
                'player_id': player_id
            }
        }
        return self._send_message(message)
    
    def cleanup_game(self, game_id: str) -> bool:
        """Clean up a game in the Dart service"""
        message = {
            'action': 'cleanup_game',
            'game_id': game_id,
            'data': {}
        }
        return self._send_message(message)
    
    def health_check(self) -> bool:
        """Send health check to Dart service"""
        message = {
            'action': 'health_check',
            'game_id': '',
            'data': {}
        }
        return self._send_message(message)
    
    def is_service_running(self) -> bool:
        """Check if Dart service is running"""
        return self.is_running and self.dart_process and self.dart_process.poll() is None


# Global instance
dart_subprocess_manager = DartSubprocessManager()
