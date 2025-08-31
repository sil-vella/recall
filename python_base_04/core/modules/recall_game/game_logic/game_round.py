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
from ..models.player import Player, PlayerStatus
from tools.logger.custom_logging import custom_log


class GameRound:
    """Manages a single round of gameplay in the Recall game"""
    
    def __init__(self, game_state: GameState):
        self.game_state = game_state
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
            
            # Send room-wide game state update to all players using coordinator
            self._send_game_state_update_via_coordinator()
            
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


    def complete_round(self, action_result: bool) -> bool:
        """Complete the current round after a player action"""
        try:
            custom_log(f"🎮 [COMPLETE_ROUND] Completing round after player action. Action result: {action_result}")
            
            # Only complete round if action was successful
            if not action_result:
                custom_log(f"⚠️ [COMPLETE_ROUND] Action failed, not completing round")
                return False
            
            # Log the successful action for round tracking
            self.actions_performed.append({
                'action': 'player_action_completed',
                'timestamp': time.time(),
                'result': action_result
            })
            
            # Send room-wide game state update to all players using coordinator
            self._send_game_state_update_via_coordinator()
            custom_log(f"🎮 [COMPLETE_ROUND] Round completed and game state updated")
            
            return True
            
        except Exception as e:
            custom_log(f"❌ [COMPLETE_ROUND] Error completing round: {e}", level="ERROR")
            return False
    
    def _send_game_state_update_via_coordinator(self):
        """Send game state update using the coordinator through the app manager"""
        try:
            if hasattr(self.game_state, 'app_manager') and self.game_state.app_manager:
                # Try to get the coordinator through the app manager
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator.send_game_state_update(self.game_state.game_id)
                    custom_log(f"📡 Game state update sent via coordinator for game {self.game_state.game_id}")
                else:
                    custom_log(f"⚠️ Coordinator not available for game state update in game {self.game_state.game_id}")
            else:
                custom_log(f"⚠️ App manager not available for game state update in game {self.game_state.game_id}")
        except Exception as e:
            custom_log(f"❌ Error sending game state update via coordinator: {e}", level="ERROR")
    
    def _send_turn_started_event_via_coordinator(self, current_player_id: str, player_status: str):
        """Send turn started event using the coordinator through the app manager"""
        try:
            if hasattr(self.game_state, 'app_manager') and self.game_state.app_manager:
                # Try to get the coordinator through the app manager
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator.send_game_state_update(
                        self.game_state.game_id, 
                        event_type='turn_started'
                    )
                    custom_log(f"📡 Turn started event sent via coordinator for game {self.game_state.game_id}")
                else:
                    custom_log(f"⚠️ Coordinator not available for turn started event in game {self.game_state.game_id}")
            else:
                custom_log(f"⚠️ App manager not available for turn started event in game {self.game_state.game_id}")
        except Exception as e:
            custom_log(f"❌ Error sending turn started event via coordinator: {e}", level="ERROR")
    
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
            
            # Get player session ID directly from game state
            session_id = self.game_state.get_player_session(current_player_id)
            if not session_id:
                custom_log(f"⚠️ No session found for player {current_player_id}")
                return
            
            # Get current player object to access their status
            current_player = self.game_state.players.get(current_player_id)
            player_status = current_player.status.value if current_player else "unknown"
            
            # Use the coordinator to send turn started event with game state
            self._send_turn_started_event_via_coordinator(current_player_id, player_status)
            
            # Send additional turn-specific data to the current player
            turn_data = {
                'event_type': 'turn_started',
                'game_id': self.game_state.game_id,
                'player_id': current_player_id,
                'player_status': player_status,
                'turn_timeout': self.turn_timeout_seconds,
                'timestamp': datetime.now().isoformat()
            }
            ws_manager.send_to_session(session_id, 'turn_started', turn_data)
            custom_log(f"📡 Turn started event sent to player {current_player_id}")
            
        except Exception as e:
            custom_log(f"❌ Error sending turn started event: {e}", level="ERROR")
    

    



    def on_player_action(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle player actions through the game round"""
        try:
            custom_log(f"🎮 [PLAYER_ACTION] Handling player action for session: {session_id}, data: {data}")
            
            action = data.get('action') or data.get('action_type')
            if not action:
                custom_log(f"❌ [PLAYER_ACTION] Missing action in data: {data}")
                return False
                
            # Get player ID from session data or request data
            session_data = self.websocket_manager.get_session_data(session_id) if self.websocket_manager else {}
            user_id = str(session_data.get('user_id') or data.get('player_id') or session_id)
            
            custom_log(f"🎮 [PLAYER_ACTION] User ID: {user_id}, Action: {action}")
            
            # Build action data for the round
            action_data = {
                'card_id': (data.get('card') or {}).get('card_id') or (data.get('card') or {}).get('id'),
                'replace_card_id': (data.get('replace_card') or {}).get('card_id') or data.get('replace_card_id'),
                'replace_index': data.get('replaceIndex'),
                'power_data': data.get('power_data'),
                'indices': data.get('indices', []),
                'source': data.get('source'),  # For draw actions (deck/discard)
            }
            
            custom_log(f"🎮 [PLAYER_ACTION] Action data built: {action_data}")
            
            # Route to appropriate action handler based on action type
            if action == 'draw_from_deck':
                return self._handle_draw_from_deck(user_id, action_data)
            elif action == 'play_card':
                custom_log(f"🎮 [PLAYER_ACTION] Play card action received - TODO: implement")
                return True
            elif action == 'discard_card':
                custom_log(f"🎮 [PLAYER_ACTION] Discard card action received - TODO: implement")
                return True
            elif action == 'take_from_discard':
                custom_log(f"🎮 [PLAYER_ACTION] Take from discard action received - TODO: implement")
                return True
            elif action == 'call_recall':
                custom_log(f"🎮 [PLAYER_ACTION] Call recall action received - TODO: implement")
                return True
            else:
                custom_log(f"❌ [PLAYER_ACTION] Unknown action type: {action}")
                return False
            
        except Exception as e:
            custom_log(f"❌ [PLAYER_ACTION] Error in on_player_action: {e}", level="ERROR")
            return False



    #========== PLAYER ACTION FUNCTIONS ==========#
    
    
    def _handle_draw_from_deck(self, player_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle drawing a card from the deck"""
        try:
            custom_log(f"🎮 [DRAW_FROM_DECK] Player {player_id} drawing from deck")
            
            # Validate that the player exists and it's their turn
            if player_id not in self.game_state.players:
                custom_log(f"❌ [DRAW_FROM_DECK] Player {player_id} not found in game")
                return False
            
            if self.game_state.current_player_id != player_id:
                custom_log(f"❌ [DRAW_FROM_DECK] Not player {player_id}'s turn (current: {self.game_state.current_player_id})")
                return False
            
            # Check if player is in drawing status
            player = self.game_state.players[player_id]
            if player.status.value != 'drawing_card':
                custom_log(f"❌ [DRAW_FROM_DECK] Player {player_id} not in drawing status (current: {player.status.value})")
                return False
            
            # Check if draw pile has cards
            if not self.game_state.draw_pile:
                custom_log(f"❌ [DRAW_FROM_DECK] Draw pile is empty")
                return False
            
            # Draw the top card from the draw pile
            drawn_card = self.game_state.draw_pile.pop(0)
            custom_log(f"🎮 [DRAW_FROM_DECK] Drawn card: {drawn_card.rank} of {drawn_card.suit} (ID: {drawn_card.card_id})")
            
            # Add card to player's hand
            player.add_card_to_hand(drawn_card)
            custom_log(f"🎮 [DRAW_FROM_DECK] Card added to player {player_id}'s hand. Hand size: {len(player.hand)}")
            
            # Update player status to playing (ready to play a card)
            player.set_playing_card()
            custom_log(f"🎮 [DRAW_FROM_DECK] Player {player_id} status updated to: {player.status.value}")
            
            # Update game state
            self.game_state.last_action_time = time.time()
                        
            custom_log(f"✅ [DRAW_FROM_DECK] Successfully drew card for player {player_id}")
            return True
            
        except Exception as e:
            custom_log(f"❌ [DRAW_FROM_DECK] Error handling draw from deck: {e}", level="ERROR")
            return False