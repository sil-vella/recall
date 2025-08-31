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
            
            # Send game state update to all players
            self._send_game_state_update()
            
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
            
            # Update round state
            self.round_status = "active"
            self.current_turn_start_time = time.time()
            
            # Log the successful action for round tracking
            self.actions_performed.append({
                'action': 'player_action_completed',
                'timestamp': time.time(),
                'result': action_result
            })
            
            # Send player state update for the current player via GameEventCoordinator
            self._send_player_state_update()
            
            custom_log(f"🎮 [COMPLETE_ROUND] Round completed and game state updated")
            
            return True
            
        except Exception as e:
            custom_log(f"❌ [COMPLETE_ROUND] Error completing round: {e}", level="ERROR")
            return False
    
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
                'game_state': self._to_flutter_game_data(),
                'player_id': current_player_id,
                'player_status': player_status,
                'turn_timeout': self.turn_timeout_seconds,
                'is_my_turn': True,  # Add missing field that frontend expects
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
    
    def _to_flutter_game_data(self) -> Dict[str, Any]:
        """
        Convert game state to Flutter format - delegates to game_state manager
        
        This method ensures all game data goes through the single source of truth
        in the GameStateManager._to_flutter_game_data method.
        """
        try:
            # Use the GameStateManager for data conversion since it has the proper method
            if hasattr(self.game_state, 'app_manager') and self.game_state.app_manager:
                game_state_manager = getattr(self.game_state.app_manager, 'game_state_manager', None)
                if game_state_manager:
                    return game_state_manager._to_flutter_game_data(self.game_state)
                else:
                    custom_log(f"❌ GameStateManager not available", level="ERROR")
                    return {}
            else:
                custom_log(f"❌ App manager not available", level="ERROR")
                return {}
        except Exception as e:
            custom_log(f"❌ Error converting game state: {e}", level="ERROR")
            return {}

    def _send_game_state_update(self):
        """Wrapper method to send game state update via GameEventCoordinator"""
        try:
            if self.game_state.app_manager:
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_game_state_update(self.game_state.game_id)
                    custom_log(f"📡 Game state update sent via GameEventCoordinator for game {self.game_state.game_id}")
                else:
                    custom_log("⚠️ GameEventCoordinator not available for game state update")
            else:
                custom_log("⚠️ App manager not available for game state update")
        except Exception as e:
            custom_log(f"❌ Error sending game state update: {e}", level="ERROR")
    
    def _send_player_state_update(self):
        """Wrapper method to send player state update via GameEventCoordinator"""
        try:
            if self.game_state.app_manager:
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    # Get current player ID
                    current_player_id = self.game_state.current_player_id
                    if current_player_id:
                        coordinator._send_player_state_update(self.game_state.game_id, current_player_id)
                        custom_log(f"📡 Player state update sent via GameEventCoordinator for player {current_player_id} in game {self.game_state.game_id}")
                    else:
                        custom_log("⚠️ No current player ID available for player state update")
                else:
                    custom_log("⚠️ GameEventCoordinator not available for player state update")
            else:
                custom_log("⚠️ App manager not available for player state update")
        except Exception as e:
            custom_log(f"❌ Error sending player state update: {e}", level="ERROR") 
            
    # =======================================================
    # Player Actions
    # =======================================================

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
            
            # Route to appropriate action handler based on action type and wait for completion
            action_result = False
            
            if action == 'draw_from_deck':
                action_result = self._handle_draw_from_pile(user_id, action_data)
            elif action == 'play_card':
                custom_log(f"🎮 [PLAYER_ACTION] Play card action received - TODO: implement")
                action_result = True  # Placeholder - will be False when implemented
            elif action == 'discard_card':
                custom_log(f"🎮 [PLAYER_ACTION] Discard card action received - TODO: implement")
                action_result = True  # Placeholder - will be False when implemented
            elif action == 'take_from_discard':
                custom_log(f"🎮 [PLAYER_ACTION] Take from discard action received - TODO: implement")
                action_result = True  # Placeholder - will be False when implemented
            elif action == 'call_recall':
                custom_log(f"🎮 [PLAYER_ACTION] Call recall action received - TODO: implement")
                action_result = True  # Placeholder - will be False when implemented
            else:
                custom_log(f"❌ [PLAYER_ACTION] Unknown action type: {action}")
                action_result = False
            
            # Log the action result
            custom_log(f"🎮 [PLAYER_ACTION] Action '{action}' completed with result: {action_result}")
            
            # Complete the round with the action result to continue game logic
            round_completion_result = self.complete_round(action_result)
            
            # Return the round completion result
            return round_completion_result
            
        except Exception as e:
            custom_log(f"❌ [PLAYER_ACTION] Error in on_player_action: {e}", level="ERROR")
            return False

    def _handle_draw_from_pile(self, player_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle drawing a card from the deck or discard pile"""
        try:
            custom_log(f"🎮 [DRAW_FROM_PILE] Handling draw action for player: {player_id}, action_data: {action_data}")
            
            # Get the source pile (deck or discard)
            source = action_data.get('source')
            if not source:
                custom_log(f"❌ [DRAW_FROM_PILE] Missing source in action_data: {action_data}")
                return False
            
            # Validate source
            if source not in ['deck', 'discard']:
                custom_log(f"❌ [DRAW_FROM_PILE] Invalid source: {source}. Must be 'deck' or 'discard'")
                return False
            
            # Get the player
            if player_id not in self.game_state.players:
                custom_log(f"❌ [DRAW_FROM_PILE] Player not found: {player_id}")
                return False
            
            player = self.game_state.players[player_id]
            
            # Draw card based on source
            drawn_card = None
            
            if source == 'deck':
                # Draw from draw pile (remove last card)
                if not self.game_state.draw_pile:
                    custom_log(f"❌ [DRAW_FROM_PILE] Draw pile is empty")
                    return False
                
                drawn_card = self.game_state.draw_pile.pop()  # Remove last card
                custom_log(f"🎮 [DRAW_FROM_PILE] Drew card {drawn_card.card_id} from draw pile. Remaining: {len(self.game_state.draw_pile)}")
                
                # Check if draw pile is now empty (special game logic)
                if len(self.game_state.draw_pile) == 0:
                    custom_log(f"🎮 [DRAW_FROM_PILE] Draw pile is now empty - this may trigger special game logic")
                    # TODO: Implement special logic for empty draw pile (e.g., game end conditions)
                
            elif source == 'discard':
                # Take from discard pile (remove last card)
                if not self.game_state.discard_pile:
                    custom_log(f"❌ [DRAW_FROM_PILE] Discard pile is empty")
                    return False
                
                drawn_card = self.game_state.discard_pile.pop()  # Remove last card
                custom_log(f"🎮 [DRAW_FROM_PILE] Took card {drawn_card.card_id} from discard pile. Remaining: {len(self.game_state.discard_pile)}")
            
            if not drawn_card:
                custom_log(f"❌ [DRAW_FROM_PILE] Failed to draw card from {source}")
                return False
            
            # Add card to player's hand
            player.add_card_to_hand(drawn_card)
            custom_log(f"🎮 [DRAW_FROM_PILE] Added card {drawn_card.card_id} to player {player_id}'s hand. Hand size: {len(player.hand)}")
            
            # Update game state
            self.game_state.last_action_time = datetime.now()
            
            # Log the action
            custom_log(f"✅ [DRAW_FROM_PILE] Successfully drew card {drawn_card.card_id} from {source} for player {player_id}")
            

            return True
            
        except Exception as e:
            custom_log(f"❌ [DRAW_FROM_PILE] Error handling draw action: {e}", level="ERROR")
            return False  
    