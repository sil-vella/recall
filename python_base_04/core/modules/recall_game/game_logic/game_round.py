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
from ..models.card import Card
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

        self.same_rank_data = {} # player_id -> same_rank_data
        self.special_card_data = {} # player_id -> special_card_data
        self.same_rank_timer = None  # Timer for same rank window

        self.round_status = "waiting"  # waiting, active, paused, completed
        
        # Timed rounds configuration
        self.timed_rounds_enabled = False
        self.round_time_limit_seconds = 300  # 5 minutes default
        self.round_time_remaining = None
        
        # WebSocket manager reference for sending events
        self.websocket_manager = getattr(game_state, 'websocket_manager', None)
        
    def start_turn(self) -> Dict[str, Any]:
        """Start a new round of gameplay"""
        try:
            custom_log(f"🎮 Starting round {self.round_number} for game {self.game_state.game_id}")
                        # Clear same rank data
            if self.same_rank_data:
                custom_log(f"🎮 [complete_round] Clearing same rank data: {len(self.same_rank_data)} plays")
                self.same_rank_data.clear()
            
            # Clear special card data
            if self.special_card_data:
                custom_log(f"🎮 [complete_round] Clearing special card data: {len(self.special_card_data)} cards")
                self.special_card_data.clear()
                
            # Initialize round state
            self.round_start_time = time.time()
            self.current_turn_start_time = self.round_start_time
            self.round_status = "active"
            self.actions_performed = []

            self.game_state.phase = GamePhase.PLAYER_TURN
            custom_log(f"🎮 [complete_round] Reset game phase from ENDING_ROUND to PLAYER_TURN")
            
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
            
                        # Update turn start time
            self.current_turn_start_time = time.time()
            
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

    def continue_turn(self, action_result: bool) -> bool:
        """Complete the current round after a player action"""
        try:
            custom_log(f"🎮 [continue_turn] Completing round after player action. Action result: {action_result}")
            
            # Only complete round if action was successful
            if not action_result:
                custom_log(f"⚠️ [continue_turn] Action failed, not completing round")
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
            
            self._send_game_state_update()

            self._end_player_turn(action_result)
            
            return True
            
        except Exception as e:
            custom_log(f"❌ [continue_turn] Error completing round: {e}", level="ERROR")
            return False
    
    def _end_player_turn(self, action_result):
        """Complete the round"""
        try:
            custom_log(f"🎮 [complete_round] Completing round")            
            # Move to next player
            self._move_to_next_player()
            
            return True
            
        except Exception as e:
            custom_log(f"❌ [complete_round] Error completing round: {e}", level="ERROR")
            return False
    
    def _move_to_next_player(self):
        """Move to the next player in the game"""
        try:
            if not self.game_state.players:
                custom_log("⚠️ [MOVE_TO_NEXT_PLAYER] No players in game")
                return
            
            # Get list of active player IDs
            active_player_ids = [pid for pid, player in self.game_state.players.items() if player.is_active]
            
            if not active_player_ids:
                custom_log("⚠️ [MOVE_TO_NEXT_PLAYER] No active players")
                return
            
            # Find current player index
            current_index = -1
            if self.game_state.current_player_id in active_player_ids:
                current_index = active_player_ids.index(self.game_state.current_player_id)
            
            # Move to next player (or first if at end)
            next_index = (current_index + 1) % len(active_player_ids)
            next_player_id = active_player_ids[next_index]
            
            # Update current player
            old_player_id = self.game_state.current_player_id
            self.game_state.current_player_id = next_player_id
            
            custom_log(f"🎮 [MOVE_TO_NEXT_PLAYER] Moved from player {old_player_id} to {next_player_id}")
            
            # Check if recall has been called
            if hasattr(self.game_state, 'recall_called_by') and self.game_state.recall_called_by:
                custom_log(f"📢 [MOVE_TO_NEXT_PLAYER] Recall called by player: {self.game_state.recall_called_by}")
                
                # Check if current player is the one who called recall
                if self.game_state.current_player_id == self.game_state.recall_called_by:
                    custom_log(f"🏁 [MOVE_TO_NEXT_PLAYER] Current player {self.game_state.current_player_id} is the recall caller - ending match")
                    self._handle_end_of_match()
                    return
                else:
                    custom_log(f"🔄 [MOVE_TO_NEXT_PLAYER] Current player {self.game_state.current_player_id} is not the recall caller - continuing game")
            else:
                custom_log("📢 [MOVE_TO_NEXT_PLAYER] No recall called yet")
            
            # Send turn started event to new player
            self.start_turn()
            
        except Exception as e:
            custom_log(f"❌ [MOVE_TO_NEXT_PLAYER] Error moving to next player: {e}", level="ERROR")
    
    def _handle_end_of_match(self):
        """Handle the end of the match"""
        try:
            custom_log(f"🎮 [HANDLE_END_OF_MATCH] Handling end of match")
            
            # Collect all player data for scoring
            player_results = {}
            
            for player_id, player in self.game_state.players.items():
                if not player.is_active:
                    continue
                    
                # Get hand cards
                hand_cards = player.hand
                card_count = len(hand_cards)
                
                # Calculate total points
                total_points = sum(card.get_point_value() for card in hand_cards)
                
                # Store player data
                player_results[player_id] = {
                    'player_id': player_id,
                    'player_name': player.name,
                    'hand_cards': [card.to_dict() for card in hand_cards],
                    'card_count': card_count,
                    'total_points': total_points
                }
                
                custom_log(f"📊 [HANDLE_END_OF_MATCH] Player {player.name} ({player_id}): {card_count} cards, {total_points} points")
            
            # Log all results
            custom_log(f"📊 [HANDLE_END_OF_MATCH] Final results for {len(player_results)} players:")
            for player_id, data in player_results.items():
                custom_log(f"📊 [HANDLE_END_OF_MATCH] - {data['player_name']}: {data['card_count']} cards, {data['total_points']} points")
            
            # Determine winner based on Recall game rules
            winner_data = self._determine_winner(player_results)
            
            # Log winner
            if winner_data['is_tie']:
                custom_log(f"🏆 [HANDLE_END_OF_MATCH] TIE! Winners: {', '.join(winner_data['winners'])}")
            else:
                custom_log(f"🏆 [HANDLE_END_OF_MATCH] WINNER: {winner_data['winner_name']} ({winner_data['winner_id']})")
            
            # TODO: Send results to all players
            # TODO: Update game state to ended
            
        except Exception as e:
            custom_log(f"❌ [HANDLE_END_OF_MATCH] Error handling end of match: {e}", level="ERROR")
    
    def _determine_winner(self, player_results: Dict[str, Any]) -> Dict[str, Any]:
        """Determine the winner based on Recall game rules"""
        try:
            # Rule 1: Check for player with 0 cards (automatic win)
            for player_id, data in player_results.items():
                if data['card_count'] == 0:
                    custom_log(f"🏆 [DETERMINE_WINNER] Player {data['player_name']} has 0 cards - automatic winner!")
                    return {
                        'is_tie': False,
                        'winner_id': player_id,
                        'winner_name': data['player_name'],
                        'win_reason': 'no_cards',
                        'winners': []
                    }
            
            # Rule 2: Find player(s) with lowest points
            min_points = min(data['total_points'] for data in player_results.values())
            lowest_point_players = [
                (player_id, data) for player_id, data in player_results.items() 
                if data['total_points'] == min_points
            ]
            
            custom_log(f"🏆 [DETERMINE_WINNER] Lowest points: {min_points}, Players with lowest: {len(lowest_point_players)}")
            
            # Rule 3: If only one player with lowest points, they win
            if len(lowest_point_players) == 1:
                winner_id, winner_data = lowest_point_players[0]
                custom_log(f"🏆 [DETERMINE_WINNER] Single lowest points winner: {winner_data['player_name']}")
                return {
                    'is_tie': False,
                    'winner_id': winner_id,
                    'winner_name': winner_data['player_name'],
                    'win_reason': 'lowest_points',
                    'winners': []
                }
            
            # Rule 4: Multiple players with lowest points - check for recall caller
            recall_caller_id = getattr(self.game_state, 'recall_called_by', None)
            if recall_caller_id:
                custom_log(f"🏆 [DETERMINE_WINNER] Recall called by: {recall_caller_id}")
                
                # Check if recall caller is among the lowest point players
                for player_id, data in lowest_point_players:
                    if player_id == recall_caller_id:
                        custom_log(f"🏆 [DETERMINE_WINNER] Recall caller {data['player_name']} has lowest points - they win!")
                        return {
                            'is_tie': False,
                            'winner_id': player_id,
                            'winner_name': data['player_name'],
                            'win_reason': 'recall_caller_lowest_points',
                            'winners': []
                        }
            
            # Rule 5: Multiple players with lowest points, none are recall callers - TIE
            winner_names = [data['player_name'] for _, data in lowest_point_players]
            custom_log(f"🏆 [DETERMINE_WINNER] TIE! Multiple players with lowest points: {', '.join(winner_names)}")
            return {
                'is_tie': True,
                'winner_id': None,
                'winner_name': None,
                'win_reason': 'tie_lowest_points',
                'winners': winner_names
            }
            
        except Exception as e:
            custom_log(f"❌ [DETERMINE_WINNER] Error determining winner: {e}", level="ERROR")
            return {
                'is_tie': False,
                'winner_id': None,
                'winner_name': 'Error',
                'win_reason': 'error',
                'winners': []
            }
    
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
    
    def _get_player(self, player_id: str) -> Optional[Player]:
        """Get player object from game state"""
        try:
            return self.game_state.players.get(player_id)
        except Exception as e:
            custom_log(f"❌ Error getting player object: {e}", level="ERROR")
            return None
    
    def _build_action_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Build standardized action data from incoming request data"""
        return {
            'card_id': data.get('card_id') or (data.get('card') or {}).get('card_id') or (data.get('card') or {}).get('id'),
            'replace_card_id': (data.get('replace_card') or {}).get('card_id') or data.get('replace_card_id'),
            'replace_index': data.get('replaceIndex'),
            'power_data': data.get('power_data'),
            'indices': data.get('indices', []),
            'source': data.get('source'),  # For draw actions (deck/discard)
        }
    
    def _extract_user_id(self, session_id: str, data: Dict[str, Any]) -> str:
        """Extract user ID from session data or request data"""
        try:
            session_data = self.websocket_manager.get_session_data(session_id) if self.websocket_manager else {}
            return str(session_data.get('user_id') or data.get('player_id') or session_id)
        except Exception as e:
            custom_log(f"❌ Error extracting user ID: {e}", level="ERROR")
            return session_id
    
    def _route_action(self, action: str, user_id: str, action_data: Dict[str, Any]) -> bool:
        """Route action to appropriate handler and return result"""
        try:
            if action == 'draw_from_deck':
                return self._handle_draw_from_pile(user_id, action_data)
            elif action == 'play_card':
                play_result = self._handle_play_card(user_id, action_data)
                special_card_data = self._check_special_card(user_id, action_data)
                same_rank_data = self._handle_same_rank_window(action_data)
                return play_result
            elif action == 'same_rank_play':
                return self._handle_same_rank_play(user_id, action_data)
            elif action == 'discard_card':
                custom_log(f"🎮 [PLAYER_ACTION] Discard card action received - TODO: implement")
                return True  # Placeholder - will be False when implemented
            elif action == 'take_from_discard':
                custom_log(f"🎮 [PLAYER_ACTION] Take from discard action received - TODO: implement")
                return True  # Placeholder - will be False when implemented
            elif action == 'call_recall':
                custom_log(f"🎮 [PLAYER_ACTION] Call recall action received - TODO: implement")
                return True  # Placeholder - will be False when implemented
            else:
                custom_log(f"❌ [PLAYER_ACTION] Unknown action type: {action}")
                return False
        except Exception as e:
            custom_log(f"❌ [PLAYER_ACTION] Error routing action {action}: {e}", level="ERROR")
            return False
    
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
    
    def _send_player_state_update(self, player_id: str):
        """Wrapper method to send player state update via GameEventCoordinator"""
        try:
            if self.game_state.app_manager:
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_player_state_update(self.game_state.game_id, player_id)
                    custom_log(f"📡 Player state update sent via GameEventCoordinator for player {player_id} in game {self.game_state.game_id}")
                else:
                    custom_log("⚠️ GameEventCoordinator not available for player state update")
            else:
                custom_log("⚠️ App manager not available for player state update")
        except Exception as e:
            custom_log(f"❌ Error sending player state update: {e}", level="ERROR")
    
    def _send_player_state_update_to_all(self):
        """Wrapper method to send player state update to all players via GameEventCoordinator"""
        try:
            if self.game_state.app_manager:
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_player_state_update_to_all(self.game_state.game_id)
                    custom_log(f"📡 Player state updates sent to all players via GameEventCoordinator in game {self.game_state.game_id}")
                else:
                    custom_log("⚠️ GameEventCoordinator not available for player state update to all")
            else:
                custom_log("⚠️ App manager not available for player state update to all")
        except Exception as e:
            custom_log(f"❌ Error sending player state update to all: {e}", level="ERROR")
    
    def update_player_state_and_send(self, player_id: str, new_status: PlayerStatus, **additional_data) -> bool:
        """
        Unified method to update player state and automatically send the update to frontend
        
        Args:
            player_id: ID of the player to update
            new_status: New PlayerStatus enum value
            **additional_data: Additional data to update (score, hand, etc.)
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            if player_id not in self.game_state.players:
                custom_log(f"❌ [UPDATE_PLAYER_STATE] Player {player_id} not found in game")
                return False
            
            player = self.game_state.players[player_id]
            
            # Update player status
            old_status = player.status
            player.set_status(new_status)
            
            # Update additional data if provided
            for key, value in additional_data.items():
                if hasattr(player, key):
                    setattr(player, key, value)
                    custom_log(f"📝 [UPDATE_PLAYER_STATE] Updated {key} for player {player_id}: {value}")
                else:
                    custom_log(f"⚠️ [UPDATE_PLAYER_STATE] Player has no attribute '{key}'")
            
            custom_log(f"✅ [UPDATE_PLAYER_STATE] Player {player_id} status changed from {old_status.value} to {new_status.value}")
            
            # Automatically send the updated state to the specific player
            self._send_player_state_update(player_id)
            
            return True
            
        except Exception as e:
            custom_log(f"❌ [UPDATE_PLAYER_STATE] Error updating player {player_id} state: {e}", level="ERROR")
            return False
    
    def update_all_players_state_and_send(self, new_status: PlayerStatus, **additional_data) -> bool:
        """
        Update all active players' status and automatically send updates to all players
        
        Args:
            new_status: New PlayerStatus enum value for all players
            **additional_data: Additional data to update for all players
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            updated_count = 0
            for player_id, player in self.game_state.players.items():
                if player.is_active:
                    success = self.update_player_state_and_send(player_id, new_status, **additional_data)
                    if success:
                        updated_count += 1
            
            custom_log(f"✅ [UPDATE_ALL_PLAYERS] Updated {updated_count} active players to status {new_status.value}")
            
            # Send updates to all players
            self._send_player_state_update_to_all()
            
            return True
            
        except Exception as e:
            custom_log(f"❌ [UPDATE_ALL_PLAYERS] Error updating all players: {e}", level="ERROR")
            return False
            
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
            user_id = self._extract_user_id(session_id, data)
            
            custom_log(f"🎮 [PLAYER_ACTION] User ID: {user_id}, Action: {action}")
            
            # Validate player exists before proceeding with any action
            if user_id not in self.game_state.players:
                custom_log(f"❌ [PLAYER_ACTION] Player not found: {user_id}")
                return False
            
            # Build action data for the round
            action_data = self._build_action_data(data)
            
            custom_log(f"🎮 [PLAYER_ACTION] Action data built: {action_data}")
            
            # Route to appropriate action handler based on action type and wait for completion
            action_result = self._route_action(action, user_id, action_data)
            
            # Log the action result
            custom_log(f"🎮 [PLAYER_ACTION] Action '{action}' completed with result: {action_result}")
            
            # Update game state timestamp after successful action
            if action_result:
                self.game_state.last_action_time = time.time()
                custom_log(f"🎮 [PLAYER_ACTION] Updated game state timestamp after successful {action}")
            
            # Complete the round with the action result to continue game logic
            round_continue_result = self.continue_turn(action_result)
            
            # Return the round completion result
            return round_continue_result
            
        except Exception as e:
            custom_log(f"❌ [PLAYER_ACTION] Error in on_player_action: {e}", level="ERROR")
            return False


    def _handle_same_rank_window(self, action_data: Dict[str, Any]) -> bool:
        """Handle same rank window action - sets all players to same_rank_window status"""
        try:
            custom_log(f"🎮 [SAME_RANK_WINDOW] Handling same rank window action: {action_data}")
                        
            # Set game state phase to SAME_RANK_WINDOW
            self.game_state.phase = GamePhase.SAME_RANK_WINDOW
            custom_log(f"🎮 [SAME_RANK_WINDOW] Set game state phase to SAME_RANK_WINDOW")
            
            # Change all players' status to same_rank_window using unified method
            success = self.update_all_players_state_and_send(PlayerStatus.SAME_RANK_WINDOW)
            if success:
                custom_log(f"🎮 [SAME_RANK_WINDOW] All active players set to SAME_RANK_WINDOW status")
            else:
                custom_log(f"⚠️ [SAME_RANK_WINDOW] Failed to update all players to SAME_RANK_WINDOW status")
            
            # Set 5-second timer to automatically end same rank window
            self._start_same_rank_timer()
            
            return True
            
        except Exception as e:
            custom_log(f"❌ [SAME_RANK_WINDOW] Error handling same rank window action: {e}", level="ERROR")
            return False
    
    def _start_same_rank_timer(self):
        """Start a 5-second timer for the same rank window"""
        try:
            import threading
            
            custom_log(f"⏰ [SAME_RANK_TIMER] Starting 5-second timer for same rank window")
            
            # Store timer reference for potential cancellation
            self.same_rank_timer = threading.Timer(5.0, self._end_same_rank_window)
            self.same_rank_timer.start()
            
            custom_log(f"⏰ [SAME_RANK_TIMER] Timer started - will end same rank window in 5 seconds")
            
        except Exception as e:
            custom_log(f"❌ [SAME_RANK_TIMER] Error starting timer: {e}", level="ERROR")
    
    def _end_same_rank_window(self):
        """End the same rank window and transition to ENDING_ROUND phase"""
        try:
            custom_log(f"⏰ [SAME_RANK_TIMER] Timer expired - ending same rank window")
            
            # Log the same_rank_data before clearing it
            if self.same_rank_data:
                custom_log(f"📊 [SAME_RANK_TIMER] Same rank data collected during window:")
                for player_id, play_data in self.same_rank_data.items():
                    custom_log(f"📊 [SAME_RANK_TIMER] Player {player_id}: {play_data['rank']} of {play_data['suit']} (order: {play_data['play_order']}, timestamp: {play_data['timestamp']})")
                custom_log(f"📊 [SAME_RANK_TIMER] Total same rank plays: {len(self.same_rank_data)}")
            else:
                custom_log(f"📊 [SAME_RANK_TIMER] No same rank plays collected during window")
            
            # Reset all players' status to WAITING using unified method
            success = self.update_all_players_state_and_send(PlayerStatus.WAITING)
            if success:
                custom_log(f"⏰ [SAME_RANK_TIMER] All active players reset to WAITING status")
            else:
                custom_log(f"⚠️ [SAME_RANK_TIMER] Failed to reset all players to WAITING status")
            
            # Set game state to ENDING_ROUND
            self.game_state.phase = GamePhase.ENDING_ROUND
            custom_log(f"⏰ [SAME_RANK_TIMER] Set game phase to ENDING_ROUND")
            
            # Clear same_rank_data after changing game phase
            if self.same_rank_data:
                custom_log(f"🧹 [SAME_RANK_TIMER] Clearing same rank data: {len(self.same_rank_data)} plays")
                self.same_rank_data.clear()
            else:
                custom_log(f"🧹 [SAME_RANK_TIMER] No same rank data to clear")
            
            # Send game state update to all players
            self._send_game_state_update()
            
            custom_log(f"⏰ [SAME_RANK_TIMER] Same rank window ended successfully")
            
        except Exception as e:
            custom_log(f"❌ [SAME_RANK_TIMER] Error ending same rank window: {e}", level="ERROR")
    
    def cancel_same_rank_timer(self):
        """Cancel the same rank window timer if it's running"""
        try:
            if self.same_rank_timer and self.same_rank_timer.is_alive():
                self.same_rank_timer.cancel()
                self.same_rank_timer = None
                custom_log(f"⏰ [SAME_RANK_TIMER] Timer cancelled")
            else:
                custom_log(f"⏰ [SAME_RANK_TIMER] No active timer to cancel")
        except Exception as e:
            custom_log(f"❌ [SAME_RANK_TIMER] Error cancelling timer: {e}", level="ERROR")

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
            
            # Player validation already done in on_player_action
            player = self._get_player(player_id)
            if not player:
                custom_log(f"❌ [DRAW_FROM_PILE] Failed to get player object for {player_id}")
                return False
            
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
            
            # Set the drawn card property
            player.set_drawn_card(drawn_card)
            
            # Change player status from DRAWING_CARD to PLAYING_CARD after successful draw using unified method
            success = self.update_player_state_and_send(
                player_id=player_id,
                new_status=PlayerStatus.PLAYING_CARD,
                drawn_card=drawn_card
            )
            
            if success:
                custom_log(f"🎮 [DRAW_FROM_PILE] Added card {drawn_card.card_id} to player {player_id}'s hand. Hand size: {len(player.hand)}")
                custom_log(f"🎮 [DRAW_FROM_PILE] Set drawn_card property to {drawn_card.card_id}")
                custom_log(f"🎮 [DRAW_FROM_PILE] Changed player status from DRAWING_CARD to PLAYING_CARD and sent update")
            else:
                custom_log(f"⚠️ [DRAW_FROM_PILE] Failed to update player status and send update")
            
            # Game state timestamp update already done in on_player_action
            
            # Log the action
            custom_log(f"✅ [DRAW_FROM_PILE] Successfully drew card {drawn_card.card_id} from {source} for player {player_id}")
            
            return True
            
        except Exception as e:
            custom_log(f"❌ [DRAW_FROM_PILE] Error handling draw action: {e}", level="ERROR")
            return False

    def _handle_play_card(self, player_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle playing a card from the player's hand"""
        try:
            custom_log(f"🎮 [PLAY_CARD] Handling play card action for player: {player_id}, action_data: {action_data}")
            
            # Log the complete payload for debugging
            custom_log(f"📋 [PLAY_CARD] Full payload: {action_data}")
            
            # Extract key information from action_data
            card_id = action_data.get('card_id', 'unknown')
            game_id = action_data.get('game_id', 'unknown')
            
            custom_log(f"🎯 [PLAY_CARD] Card ID: {card_id}, Game ID: {game_id}, Player ID: {player_id}")
            
            # Player validation already done in on_player_action
            player = self._get_player(player_id)
            if not player:
                custom_log(f"❌ [PLAY_CARD] Failed to get player object for {player_id}")
                return False
            
            # Find the card in the player's hand
            card_to_play = None
            card_index = -1
            
            for i, card in enumerate(player.hand):
                if card.card_id == card_id:
                    card_to_play = card
                    card_index = i
                    break
            
            if not card_to_play:
                custom_log(f"❌ [PLAY_CARD] Card {card_id} not found in player {player_id}'s hand")
                return False
            
            custom_log(f"🎮 [PLAY_CARD] Found card {card_id} at index {card_index} in player's hand")
            
            # Handle drawn card repositioning BEFORE removing the played card
            drawn_card = player.get_drawn_card()
            drawn_card_original_index = -1
            
            if drawn_card and drawn_card.card_id != card_id:
                # The played card was NOT the drawn card, so we need to reposition the drawn card
                # Find the drawn card in the hand BEFORE removing the played card
                for i, card in enumerate(player.hand):
                    if card.card_id == drawn_card.card_id:
                        drawn_card_original_index = i
                        break
                
                custom_log(f"🎮 [PLAY_CARD] Found drawn card {drawn_card.card_id} at original index {drawn_card_original_index}")
            
            # Remove card from player's hand
            removed_card = player.hand.pop(card_index)
            custom_log(f"🎮 [PLAY_CARD] Removed card {removed_card.card_id} from player's hand. New hand size: {len(player.hand)}")
            
            # Add card to discard pile
            self.game_state.discard_pile.append(removed_card)
            custom_log(f"🎮 [PLAY_CARD] Added card {removed_card.card_id} to discard pile. Discard pile size: {len(self.game_state.discard_pile)}")
            
            # Now handle drawn card repositioning with correct indexes
            if drawn_card and drawn_card.card_id != card_id and drawn_card_original_index != -1:
                # Calculate the new index for the drawn card after the played card removal
                if drawn_card_original_index > card_index:
                    # Drawn card was after the played card, so its index decreased by 1
                    new_drawn_card_index = drawn_card_original_index - 1
                else:
                    # Drawn card was before the played card, so its index stayed the same
                    new_drawn_card_index = drawn_card_original_index
                
                # Find the drawn card at its new position
                drawn_card_obj = player.hand.pop(new_drawn_card_index)
                # Insert drawn card at the vacated index (where the played card was)
                player.hand.insert(card_index, drawn_card_obj)
                custom_log(f"🎮 [PLAY_CARD] Repositioned drawn card {drawn_card.card_id} from original index {drawn_card_original_index} (new index {new_drawn_card_index}) to index {card_index}")
                
                # IMPORTANT: After repositioning, the drawn card becomes a regular hand card
                # Clear the drawn card property since it's no longer "drawn"
                player.clear_drawn_card()
                custom_log(f"🎮 [PLAY_CARD] Cleared drawn_card property for player {player_id} after repositioning")
                
            elif drawn_card and drawn_card.card_id == card_id:
                # The played card WAS the drawn card, so no repositioning needed
                custom_log(f"🎮 [PLAY_CARD] Played card {card_id} was the drawn card - no repositioning needed")
                # Clear the drawn card property since it's now in the discard pile
                player.clear_drawn_card()
                custom_log(f"🎮 [PLAY_CARD] Cleared drawn_card property for player {player_id}")
            else:
                # No drawn card, so no repositioning needed
                custom_log(f"🎮 [PLAY_CARD] No drawn card to reposition")
            
            # Game state timestamp update already done in on_player_action
            
            custom_log(f"✅ [PLAY_CARD] Successfully moved card {card_id} from hand to discard pile for player {player_id}")
            return True
            
        except Exception as e:
            custom_log(f"❌ [PLAY_CARD] Error handling play card action: {e}", level="ERROR")
            return False  
    
    def _handle_same_rank_play(self, user_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle same rank play action - validates rank match and stores the play in same_rank_data for multiple players"""
        try:
            custom_log(f"🎮 [SAME_RANK_PLAY] Handling same rank play action for player {user_id}: {action_data}")
            
            # Extract card details from action_data
            card_id = action_data.get('card_id', 'unknown')
            
            # Get player and find the card to get its rank and suit
            player = self.game_state.players.get(user_id)
            if not player:
                custom_log(f"❌ [SAME_RANK_PLAY] Player {user_id} not found")
                return False
            
            # Find the card in player's hand
            played_card = None
            for card in player.hand:
                if card.card_id == card_id:
                    played_card = card
                    break
            
            if not played_card:
                custom_log(f"❌ [SAME_RANK_PLAY] Card {card_id} not found in player {user_id}'s hand")
                return False
            
            card_rank = played_card.rank
            card_suit = played_card.suit
            
            # Validate that this is actually a same rank play
            if not self._validate_same_rank_play(card_rank):
                custom_log(f"❌ [SAME_RANK_PLAY] Invalid same rank play: {card_rank} does not match last played card rank")
                
                # Apply penalty: draw a card from the draw pile
                penalty_card = self._apply_same_rank_penalty(user_id)
                if penalty_card:
                    custom_log(f"🎯 [SAME_RANK_PLAY] Applied penalty: player {user_id} drew card {penalty_card.card_id} from draw pile")
                else:
                    custom_log(f"⚠️ [SAME_RANK_PLAY] Failed to apply penalty: could not draw card for player {user_id}")
                
                return False
            
            # Check for special cards (Jack/Queen) and store data if applicable
            special_card_data = self._check_special_card(user_id, action_data)
            
            # Create play data structure
            play_data = {
                'player_id': user_id,
                'card_id': card_id,
                'rank': card_rank,      # Use 'rank' to match Card model
                'suit': card_suit,      # Use 'suit' to match Card model
                'timestamp': time.time(),
                'play_order': len(self.same_rank_data) + 1  # Track order of plays
            }
            
            # Store the play in same_rank_data
            self.same_rank_data[user_id] = play_data
            
            custom_log(f"🎮 [SAME_RANK_PLAY] Stored play data for player {user_id}: {play_data}")
            custom_log(f"🎮 [SAME_RANK_PLAY] Total same rank plays: {len(self.same_rank_data)}")
            
            # Log all current plays for debugging
            for pid, play in self.same_rank_data.items():
                custom_log(f"🎮 [SAME_RANK_PLAY] Player {pid}: {play['rank']} of {play['suit']} (order: {play['play_order']})")
            
            return True
            
        except Exception as e:
            custom_log(f"❌ [SAME_RANK_PLAY] Error handling same rank play action: {e}", level="ERROR")
            return False
    
    def _validate_same_rank_play(self, card_rank: str) -> bool:
        """Validate that the played card has the same rank as the last card in the discard pile"""
        try:
            # Check if there are any cards in the discard pile
            if not self.game_state.discard_pile:
                custom_log(f"❌ [VALIDATE_SAME_RANK] No cards in discard pile to compare against")
                return False
            
            # Get the last card from the discard pile
            last_card = self.game_state.discard_pile[-1]
            last_card_rank = last_card.rank
            
            custom_log(f"🎯 [VALIDATE_SAME_RANK] Comparing played card rank '{card_rank}' with last played card rank '{last_card_rank}'")
            
            # Handle special case: first card of the game (no previous card to match)
            if len(self.game_state.discard_pile) == 1:
                custom_log(f"🎯 [VALIDATE_SAME_RANK] First card of the game - no rank matching required")
                return True
            
            # Check if ranks match (case-insensitive for safety)
            if card_rank.lower() == last_card_rank.lower():
                custom_log(f"✅ [VALIDATE_SAME_RANK] Rank match confirmed: {card_rank} matches {last_card_rank}")
                return True
            else:
                custom_log(f"❌ [VALIDATE_SAME_RANK] Rank mismatch: {card_rank} does not match {last_card_rank}")
                return False
                
        except Exception as e:
            custom_log(f"❌ [VALIDATE_SAME_RANK] Error validating same rank play: {e}", level="ERROR")
            return False
    
    def _apply_same_rank_penalty(self, player_id: str) -> Optional[Card]:
        """Apply penalty for invalid same rank play - draw a card from the draw pile"""
        try:
            custom_log(f"🎯 [SAME_RANK_PENALTY] Applying penalty for player {player_id}")
            
            # Check if draw pile has cards
            if not self.game_state.draw_pile:
                custom_log(f"❌ [SAME_RANK_PENALTY] Draw pile is empty - cannot apply penalty")
                return None
            
            # Get player object
            player = self._get_player(player_id)
            if not player:
                custom_log(f"❌ [SAME_RANK_PENALTY] Player {player_id} not found")
                return None
            
            # Draw penalty card from draw pile
            penalty_card = self.game_state.draw_pile.pop()  # Remove last card
            custom_log(f"🎯 [SAME_RANK_PENALTY] Drew penalty card {penalty_card.card_id} from draw pile. Remaining: {len(self.game_state.draw_pile)}")
            
            # Add penalty card to player's hand
            player.add_card_to_hand(penalty_card)
            custom_log(f"🎯 [SAME_RANK_PENALTY] Added penalty card {penalty_card.card_id} to player {player_id}'s hand. New hand size: {len(player.hand)}")
            
            # Update player status to indicate they received a penalty
            success = self.update_player_state_and_send(
                player_id=player_id,
                new_status=PlayerStatus.WAITING  # Reset to waiting after penalty
            )
            
            if success:
                custom_log(f"🎯 [SAME_RANK_PENALTY] Updated player {player_id} status to WAITING after penalty")
            else:
                custom_log(f"⚠️ [SAME_RANK_PENALTY] Failed to update player {player_id} status after penalty")
            
            return penalty_card
            
        except Exception as e:
            custom_log(f"❌ [SAME_RANK_PENALTY] Error applying penalty for player {player_id}: {e}", level="ERROR")
            return None
    
    def _check_special_card(self, player_id: str, action_data: Dict[str, Any]) -> None:
        """Check if a played card has special powers (Jack/Queen) and set player status accordingly"""
        try:
            # Extract card details from action_data
            card_id = action_data.get('card_id', 'unknown')
            card_rank = action_data.get('rank', 'unknown')
            card_suit = action_data.get('suit', 'unknown')
            
            custom_log(f"🎮 [SPECIAL_CARD] Checking card: {card_rank} of {card_suit} (ID: {card_id})")
            
            if card_rank == 'jack':
                custom_log(f"🎭 [SPECIAL_CARD] Jack played! Suit: {card_suit} - Player can switch any two cards between players")
                
                # Store special card data for jack
                self.special_card_data[player_id] = {
                    'player_id': player_id,
                    'card_id': card_id,
                    'rank': card_rank,
                    'suit': card_suit,
                    'special_power': 'jack_swap',
                    'timestamp': time.time(),
                    'description': 'Can switch any two cards between players'
                }
                custom_log(f"🎭 [SPECIAL_CARD] Stored jack data for player {player_id}")
                
            elif card_rank == 'queen':
                custom_log(f"👑 [SPECIAL_CARD] Queen played! Suit: {card_suit} - Player can look at one card from any player's hand")
                
                # Store special card data for queen
                self.special_card_data[player_id] = {
                    'player_id': player_id,
                    'card_id': card_id,
                    'rank': card_rank,
                    'suit': card_suit,
                    'special_power': 'queen_peek',
                    'timestamp': time.time(),
                    'description': 'Can look at one card from any player\'s hand'
                }
                custom_log(f"👑 [SPECIAL_CARD] Stored queen data for player {player_id}")
                
            else:
                custom_log(f"🃏 [SPECIAL_CARD] Regular card played: {card_rank} of {card_suit} - no special powers")
                # No special card data to store for regular cards
                
            # Log current special card data status
            custom_log(f"🎮 [SPECIAL_CARD] Total special cards active: {len(self.special_card_data)}")
            for pid, special_data in self.special_card_data.items():
                custom_log(f"🎮 [SPECIAL_CARD] Player {pid}: {special_data['special_power']} - {special_data['rank']} of {special_data['suit']}")
                
        except Exception as e:
            custom_log(f"❌ [SPECIAL_CARD] Error checking special card: {e}", level="ERROR")
    