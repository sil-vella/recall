"""
Game Round for Recall Game

This module defines the GameRound class which serves as the entry point
for all gameplay during a round, managing round state and coordinating
with game actions.
"""

from typing import Dict, Any, Optional, List
from datetime import datetime
import time
from .game_state import GameState, GamePhase
from .game_actions import GameActions
from ..models.player import Player, PlayerStatus
from tools.logger.custom_logging import custom_log


class GameRound:
    """Manages a single round of gameplay in the Recall game"""
    
    def __init__(self, game_state: GameState):
        self.game_state = game_state
        self.game_actions = GameActions(game_state)
        self.round_number = 1
        self.round_start_time = None
        self.round_end_time = None
        self.current_turn_start_time = None
        self.turn_timeout_seconds = 30  # 30 seconds per turn
        self.actions_performed = []
        self.round_status = "waiting"  # waiting, active, paused, completed
        
        # Timed rounds configuration
        self.timed_rounds_enabled = False
        self.round_time_limit_seconds = 300  # 5 minutes default
        self.round_time_remaining = None
        
        # WebSocket manager reference for sending events
        self.websocket_manager = getattr(game_state, 'websocket_manager', None)
        
    def start_round(self) -> Dict[str, Any]:
        """Start a new round of gameplay"""
        try:
            custom_log(f"🎮 Starting round {self.round_number} for game {self.game_state.game_id}")
            
            # Initialize round state
            self.round_start_time = time.time()
            self.current_turn_start_time = self.round_start_time
            self.round_status = "active"
            self.actions_performed = []
            
            # Initialize timed rounds if enabled
            if self.timed_rounds_enabled:
                self.round_time_remaining = self.round_time_limit_seconds
                custom_log(f"⏰ Round {self.round_number} started with {self.round_time_limit_seconds} second time limit")
            
            # Log round start
            self._log_action("round_started", {
                "round_number": self.round_number,
                "current_player": self.game_state.current_player_id,
                "player_count": len(self.game_state.players)
            })
            
            custom_log(f"✅ Round {self.round_number} started successfully")
            
            # Log actions_performed at round start
            custom_log(f"📋 Round {self.round_number} actions_performed initialized: {len(self.actions_performed)} actions")
            
            # Send room-wide game state update to all players
            self._send_room_game_state_update()
            
            # Send turn started event to current player
            self._send_turn_started_event()
            
            return {
                "success": True,
                "round_number": self.round_number,
                "round_start_time": datetime.fromtimestamp(self.round_start_time).isoformat(),
                "current_player": self.game_state.current_player_id,
                "game_phase": self.game_state.phase.value,
                "player_count": len(self.game_state.players)
            }
            
        except Exception as e:
            custom_log(f"❌ Error starting round: {e}", level="ERROR")
            return {"error": f"Failed to start round: {str(e)}"}
    
    def perform_action(self, player_id: str, action_type: str, action_data: Dict[str, Any] = None) -> Dict[str, Any]:
        """Perform a game action during the current round"""
        try:
            if self.round_status != "active":
                return {"error": "Round is not active"}
            
            if not action_data:
                action_data = {}
            
            # Validate it's the player's turn (except for out-of-turn actions)
            if action_type not in ["play_out_of_turn", "call_recall"]:
                if player_id != self.game_state.current_player_id:
                    return {"error": "Not your turn"}
            
            # Check turn timeout
            if self._is_turn_timed_out():
                return {"error": "Turn timed out"}
            
            # Perform the action based on type
            result = self._execute_action(player_id, action_type, action_data)
            
            if result.get("success"):
                # Log the action
                self._log_action(action_type, {
                    "player_id": player_id,
                    "action_data": action_data,
                    "result": result
                })
                
                # Update turn timing
                self._update_turn_timing()
                
                # Check for round end conditions
                if self._should_end_round(result):
                    return self._end_round(result)
            
            return result
            
        except Exception as e:
            custom_log(f"❌ Error performing action: {e}", level="ERROR")
            return {"error": f"Action failed: {str(e)}"}
    
    def pause_round(self) -> Dict[str, Any]:
        """Pause the current round"""
        if self.round_status != "active":
            return {"error": "Round is not active"}
        
        self.round_status = "paused"
        custom_log(f"⏸️ Round {self.round_number} paused")
        
        return {
            "success": True,
            "round_status": self.round_status,
            "pause_time": datetime.now().isoformat()
        }
    
    def resume_round(self) -> Dict[str, Any]:
        """Resume a paused round"""
        if self.round_status != "paused":
            return {"error": "Round is not paused"}
        
        self.round_status = "active"
        self.current_turn_start_time = time.time()
        custom_log(f"▶️ Round {self.round_number} resumed")
        
        return {
            "success": True,
            "round_status": self.round_status,
            "resume_time": datetime.now().isoformat()
        }
    
    def get_round_status(self) -> Dict[str, Any]:
        """Get current round status and information"""
        # Get timed rounds status
        timed_rounds_status = self.get_timed_rounds_status()
        
        return {
            "round_number": self.round_number,
            "round_status": self.round_status,
            "round_start_time": datetime.fromtimestamp(self.round_start_time).isoformat() if self.round_start_time else None,
            "round_end_time": datetime.fromtimestamp(self.round_end_time).isoformat() if self.round_end_time else None,
            "current_turn_start_time": datetime.fromtimestamp(self.current_turn_start_time).isoformat() if self.current_turn_start_time else None,
            "current_player": self.game_state.current_player_id,
            "game_phase": self.game_state.phase.value,
            "turn_timeout_seconds": self.turn_timeout_seconds,
            "actions_performed_count": len(self.actions_performed),
            "player_count": len(self.game_state.players),
            **timed_rounds_status  # Include timed rounds information
        }
    
    def get_round_history(self) -> List[Dict[str, Any]]:
        """Get the history of actions performed in this round"""
        return self.actions_performed.copy()
    
    def set_turn_timeout(self, timeout_seconds: int) -> Dict[str, Any]:
        """Set the turn timeout duration"""
        if timeout_seconds < 5 or timeout_seconds > 300:
            return {"error": "Timeout must be between 5 and 300 seconds"}
        
        self.turn_timeout_seconds = timeout_seconds
        custom_log(f"⏱️ Turn timeout set to {timeout_seconds} seconds")
        
        return {
            "success": True,
            "turn_timeout_seconds": self.turn_timeout_seconds
        }
    
    def configure_timed_rounds(self, enabled: bool, time_limit_seconds: int = None) -> Dict[str, Any]:
        """Configure timed rounds settings"""
        if enabled:
            if time_limit_seconds is None:
                time_limit_seconds = 300  # Default 5 minutes
            
            if time_limit_seconds < 60 or time_limit_seconds > 1800:
                return {"error": "Round time limit must be between 60 and 1800 seconds (1-30 minutes)"}
            
            self.timed_rounds_enabled = True
            self.round_time_limit_seconds = time_limit_seconds
            self.round_time_remaining = time_limit_seconds
            
            custom_log(f"⏰ Timed rounds enabled with {time_limit_seconds} second limit")
            
            return {
                "success": True,
                "timed_rounds_enabled": True,
                "round_time_limit_seconds": self.round_time_limit_seconds,
                "round_time_remaining": self.round_time_remaining
            }
        else:
            self.timed_rounds_enabled = False
            self.round_time_remaining = None
            
            custom_log("⏰ Timed rounds disabled")
            
            return {
                "success": True,
                "timed_rounds_enabled": False,
                "round_time_limit_seconds": None,
                "round_time_remaining": None
            }
    
    def get_timed_rounds_status(self) -> Dict[str, Any]:
        """Get current timed rounds configuration and status"""
        if not self.timed_rounds_enabled:
            return {
                "timed_rounds_enabled": False,
                "round_time_limit_seconds": None,
                "round_time_remaining": None
            }
        
        # Calculate remaining time if round is active
        if self.round_status == "active" and self.round_start_time:
            elapsed_time = time.time() - self.round_start_time
            remaining_time = max(0, self.round_time_limit_seconds - elapsed_time)
            self.round_time_remaining = remaining_time
        
        return {
            "timed_rounds_enabled": True,
            "round_time_limit_seconds": self.round_time_limit_seconds,
            "round_time_remaining": self.round_time_remaining,
            "round_time_elapsed": self.round_time_limit_seconds - self.round_time_remaining if self.round_time_remaining is not None else 0
        }
    
    # ========= Private Helper Methods =========
    
    def _execute_action(self, player_id: str, action_type: str, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a specific game action"""
        try:
            if action_type == "play_card":
                card_id = action_data.get("card_id")
                if not card_id:
                    return {"error": "Missing card_id"}
                return self.game_actions.play_card(player_id, card_id)
            
            elif action_type == "play_out_of_turn":
                card_id = action_data.get("card_id")
                if not card_id:
                    return {"error": "Missing card_id"}
                return self.game_actions.play_out_of_turn(player_id, card_id)
            
            elif action_type == "draw_from_deck":
                return self.game_actions.draw_from_deck(player_id)
            
            elif action_type == "take_from_discard":
                return self.game_actions.take_from_discard(player_id)
            
            elif action_type == "place_drawn_card_replace":
                replace_card_id = action_data.get("replace_card_id")
                if not replace_card_id:
                    return {"error": "Missing replace_card_id"}
                return self.game_actions.place_drawn_card_replace(player_id, replace_card_id)
            
            elif action_type == "place_drawn_card_play":
                return self.game_actions.place_drawn_card_play(player_id)
            
            elif action_type == "initial_peek":
                indices = action_data.get("indices", [])
                if not indices:
                    return {"error": "Missing indices"}
                return self.game_actions.initial_peek(player_id, indices)
            
            elif action_type == "call_recall":
                return self.game_actions.call_recall(player_id)
            
            elif action_type == "end_game":
                return self.game_actions.end_game()
            

            
            else:
                return {"error": f"Unknown action type: {action_type}"}
                
        except Exception as e:
            custom_log(f"❌ Error executing action {action_type}: {e}", level="ERROR")
            return {"error": f"Action execution failed: {str(e)}"}
    
    def _should_end_round(self, action_result: Dict[str, Any]) -> bool:
        """Check if the round should end based on the action result"""
        # Check if game ended
        if self.game_state.game_ended:
            return True
        
        # Check if recall was called
        if self.game_state.phase == GamePhase.RECALL_CALLED:
            return True
        
        # Check if a player won (no cards left)
        if action_result.get("reason") == "player_empty_hand":
            return True
        
        # Check if round time limit exceeded (for timed rounds)
        if self.timed_rounds_enabled and self.round_start_time:
            elapsed_time = time.time() - self.round_start_time
            if elapsed_time >= self.round_time_limit_seconds:
                custom_log(f"⏰ Round {self.round_number} ended due to time limit ({self.round_time_limit_seconds} seconds)")
                return True
        
        return False
    
    def _end_round(self, final_action_result: Dict[str, Any]) -> Dict[str, Any]:
        """End the current round"""
        try:
            self.round_status = "completed"
            self.round_end_time = time.time()
            
            # Calculate round duration
            round_duration = self.round_end_time - self.round_start_time if self.round_start_time else 0
            
            # Log round end
            self._log_action("round_ended", {
                "round_duration": round_duration,
                "final_action": final_action_result,
                "winner": self.game_state.winner
            })
            
            custom_log(f"🏁 Round {self.round_number} completed in {round_duration:.2f} seconds")
            
            return {
                "success": True,
                "round_ended": True,
                "round_number": self.round_number,
                "round_duration": round_duration,
                "round_end_time": datetime.fromtimestamp(self.round_end_time).isoformat(),
                "winner": self.game_state.winner,
                "final_action": final_action_result,
                "game_phase": self.game_state.phase.value
            }
            
        except Exception as e:
            custom_log(f"❌ Error ending round: {e}", level="ERROR")
            return {"error": f"Failed to end round: {str(e)}"}
    
    def _is_turn_timed_out(self) -> bool:
        """Check if the current turn has timed out"""
        if not self.current_turn_start_time:
            return False
        
        elapsed_time = time.time() - self.current_turn_start_time
        return elapsed_time > self.turn_timeout_seconds
    
    def _update_turn_timing(self):
        """Update turn timing after an action"""
        self.current_turn_start_time = time.time()
    
    def _log_action(self, action_type: str, action_data: Dict[str, Any]):
        """Log an action performed during the round"""
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "action_type": action_type,
            "round_number": self.round_number,
            "data": action_data
        }
        self.actions_performed.append(log_entry)
        
        # Keep only last 100 actions to prevent memory bloat
        if len(self.actions_performed) > 100:
            self.actions_performed = self.actions_performed[-100:]
    
    def get_remaining_turn_time(self) -> Optional[float]:
        """Get remaining time for current turn"""
        if not self.current_turn_start_time:
            return None
        
        elapsed_time = time.time() - self.current_turn_start_time
        remaining_time = self.turn_timeout_seconds - elapsed_time
        return max(0, remaining_time)
    
    def is_player_turn(self, player_id: str) -> bool:
        """Check if it's the specified player's turn"""
        return (self.round_status == "active" and 
                self.game_state.current_player_id == player_id and 
                not self._is_turn_timed_out())
    
    def can_player_act(self, player_id: str, action_type: str) -> bool:
        """Check if a player can perform a specific action"""
        # Out-of-turn actions are always allowed if conditions are met
        if action_type in ["play_out_of_turn", "call_recall"]:
            return self.round_status == "active"
        
        # Regular actions require it to be the player's turn
        return self.is_player_turn(player_id)
    
    def _send_turn_started_event(self):
        """Send turn started event to current player"""
        try:
            # Get WebSocket manager through the game state's app manager
            if not self.game_state.app_manager:
                custom_log("⚠️ No app manager available for turn event")
                return
                
            ws_manager = self.game_state.app_manager.get_websocket_manager()
            if not ws_manager:
                custom_log("⚠️ No websocket manager available for turn event")
                return
            
            current_player_id = self.game_state.current_player_id
            if not current_player_id:
                custom_log("⚠️ No current player for turn event")
                return
            
            # Get player session ID
            session_id = self._get_player_session_id(current_player_id)
            if not session_id:
                custom_log(f"⚠️ No session found for player {current_player_id}")
                return
            
            # Get current player object to access their status
            current_player = self.game_state.players.get(current_player_id)
            player_status = current_player.status.value if current_player else "unknown"
            
            # Create turn started payload
            turn_payload = {
                'event_type': 'turn_started',
                'game_id': self.game_state.game_id,
                'game_state': self._to_flutter_game_state(),
                'player_id': current_player_id,
                'player_status': player_status,
                'turn_timeout': self.turn_timeout_seconds,
                'timestamp': datetime.now().isoformat()
            }
            
            # Send turn started event
            ws_manager.send_to_session(session_id, 'turn_started', turn_payload)
            custom_log(f"📡 Turn started event sent to player {current_player_id}")
            
        except Exception as e:
            custom_log(f"❌ Error sending turn started event: {e}", level="ERROR")
    
    def _get_player_session_id(self, player_id: str) -> Optional[str]:
        """Get session ID for a player"""
        try:
            # Access the player sessions directly from game state
            return self.game_state.get_player_session(player_id)
        except Exception as e:
            custom_log(f"❌ Error getting player session: {e}", level="ERROR")
            return None
    
    def _send_room_game_state_update(self):
        """Send room-wide game state update to all players"""
        try:
            # Get WebSocket manager through the game state's app manager
            if not self.game_state.app_manager:
                custom_log("⚠️ No app manager available for room game state update")
                return
                
            ws_manager = self.game_state.app_manager.get_websocket_manager()
            if not ws_manager:
                custom_log("⚠️ No websocket manager available for room game state update")
                return
            
            # Get current player object to access their status
            current_player_id = self.game_state.current_player_id
            current_player = self.game_state.players.get(current_player_id)
            current_player_status = current_player.status.value if current_player else "unknown"
            
            # Create room game state update payload
            room_payload = {
                'event_type': 'game_state_updated',
                'game_id': self.game_state.game_id,
                'game_state': self._to_flutter_game_state(),
                'round_number': self.round_number,
                'current_player': current_player_id,
                'current_player_status': current_player_status,
                'round_status': self.round_status,
                'timestamp': datetime.now().isoformat()
            }
            
            # Send to all players in the room
            room_id = self.game_state.game_id
            ws_manager.socketio.emit('game_state_updated', room_payload, room=room_id)
            custom_log(f"📡 Room game state update sent to all players in game {self.game_state.game_id} - Current player: {current_player_id} ({current_player_status})")
            
        except Exception as e:
            custom_log(f"❌ Error sending room game state update: {e}", level="ERROR")
    
    def _to_flutter_game_state(self) -> Dict[str, Any]:
        """Convert game state to Flutter format"""
        try:
            # Access the game state conversion method directly from game state
            if hasattr(self.game_state, '_to_flutter_game_state'):
                return self.game_state._to_flutter_game_state(self.game_state)
            return {}
        except Exception as e:
            custom_log(f"❌ Error converting game state: {e}", level="ERROR")
            return {}
