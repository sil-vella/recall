"""
Game Round for Recall Game

This module defines the GameRound class which serves as the entry point
for all gameplay during a round, managing round state and coordinating
with game actions.
"""

from typing import Dict, Any, Optional, List
from datetime import datetime
import time
import threading
from .game_state import GameState, GamePhase
from ..models.player import Player, PlayerStatus
from ..models.card import Card
from tools.logger.custom_logging import custom_log 

LOGGING_SWITCH = True

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
        self.special_card_data = [] # chronological list of special cards
        custom_log(f"DEBUG: GameRound instance created - special_card_data initialized", level="INFO", isOn=LOGGING_SWITCH)
        self.same_rank_timer = None  # Timer for same rank window
        self.special_card_timer = None  # Timer for special card window
        self.special_card_players = []  # List of players who played special cards

        self.pending_events = [] # List of pending events to process before ending round

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
            # Clear same rank data
            if self.same_rank_data:
                self.same_rank_data.clear()
            
            # Only clear special card data if we're not in the middle of processing special cards
            # This prevents clearing data during special card processing
            if self.special_card_data and self.game_state.phase not in [GamePhase.SPECIAL_PLAY_WINDOW]:
                custom_log(f"DEBUG: Clearing {len(self.special_card_data)} special cards in start_turn (phase: {self.game_state.phase})", level="INFO", isOn=LOGGING_SWITCH)
                self.special_card_data.clear()
                custom_log("Special card data cleared in start_turn (new turn)", level="INFO", isOn=LOGGING_SWITCH)
            elif self.special_card_data and self.game_state.phase == GamePhase.SPECIAL_PLAY_WINDOW:
                custom_log(f"DEBUG: NOT clearing {len(self.special_card_data)} special cards in start_turn (processing special cards)", level="INFO", isOn=LOGGING_SWITCH)
                custom_log("Special card data NOT cleared in start_turn (processing special cards)", level="INFO", isOn=LOGGING_SWITCH)
            else:
                custom_log("DEBUG: No special card data to clear in start_turn", level="INFO", isOn=LOGGING_SWITCH)
                
            # Initialize round state
            self.round_start_time = time.time()
            self.current_turn_start_time = self.round_start_time
            self.round_status = "active"
            self.actions_performed = []

            self.game_state.phase = GamePhase.PLAYER_TURN
            
            # Set current player status to drawing_card (they need to draw a card)
            if self.game_state.current_player_id:
                player = self.game_state.players.get(self.game_state.current_player_id)
                if player:
                    player.set_status(PlayerStatus.DRAWING_CARD)
                    custom_log(f"Player {self.game_state.current_player_id} status set to DRAWING_CARD", level="INFO", isOn=LOGGING_SWITCH)
            
            # Initialize timed rounds if enabled
            if self.timed_rounds_enabled:
                self.round_time_remaining = self.round_time_limit_seconds
            
            # Log round start
            self._log_action("round_started", {
                "round_number": self.round_number,
                "current_player": self.game_state.current_player_id,
                "player_count": len(self.game_state.players)
            })
            
                        # Update turn start time
            self.current_turn_start_time = time.time()
            
            # Send game state update to all players
            if self.game_state.app_manager:
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_game_state_update(self.game_state.game_id)
            
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
            return {"error": f"Failed to start round: {str(e)}"}

    def continue_turn(self):
        """Complete the current round after a player action"""
        try:
            custom_log(f"Continuing turn in phase: {self.game_state.phase}", level="INFO", isOn=LOGGING_SWITCH)
            if self.game_state.app_manager:
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_game_state_update(self.game_state.game_id)

            custom_log(f"Continued turn in phase: {self.game_state.phase}", level="INFO", isOn=LOGGING_SWITCH)

            if self.game_state.phase == GamePhase.TURN_PENDING_EVENTS:
                self._check_pending_events_before_ending_round()
                
            if self.game_state.phase == GamePhase.ENDING_ROUND:
                self._move_to_next_player()
            
            return True
            
        except Exception as e:
            return False
    
    def _check_pending_events_before_ending_round(self):
        """Check if we have pending events to process (like queen peek pause so the user can see the card)"""
        try:
            if not self.pending_events:
                custom_log("No pending events to process", level="DEBUG", isOn=LOGGING_SWITCH)
                self.game_state.phase = GamePhase.ENDING_ROUND
                return
            
            custom_log(f"Processing {len(self.pending_events)} pending events", level="INFO", isOn=LOGGING_SWITCH)
            
            # Process each pending event
            for event in self.pending_events:
                event_type = event.get('type')
                event_data = event.get('data')
                player_id = event.get('player_id')
                timestamp = event.get('timestamp')
                
                custom_log(f"Processing pending event: {event_type} for player {player_id}", level="DEBUG", isOn=LOGGING_SWITCH)
                
                # Construct handler method name by appending _handle to the event type
                handler_method_name = f"_handle_{event_type}"
                
                # Check if the handler method exists
                if hasattr(self, handler_method_name):
                    handler_method = getattr(self, handler_method_name)
                    
                    # Call the handler method with the event data
                    try:
                        result = handler_method(event_data, player_id)
                        custom_log(f"Handler {handler_method_name} executed successfully for player {player_id}", level="DEBUG", isOn=LOGGING_SWITCH)
                    except Exception as handler_error:
                        custom_log(f"Error in handler {handler_method_name} for player {player_id}: {handler_error}", level="ERROR", isOn=LOGGING_SWITCH)
                else:
                    custom_log(f"Handler method {handler_method_name} not found for event type {event_type}", level="WARNING", isOn=LOGGING_SWITCH)
            
            # Clear the pending events after processing
            self.pending_events.clear()
            custom_log("Cleared pending events after processing", level="DEBUG", isOn=LOGGING_SWITCH)
            
            self.continue_turn()
            
        except Exception as e:
            custom_log(f"Error in _check_pending_events_before_ending_round: {e}", level="ERROR", isOn=LOGGING_SWITCH)

    def _move_to_next_player(self):
        """Move to the next player in the game"""
        try:
            if not self.game_state.players:
                return
            
            # Get list of active player IDs
            active_player_ids = [pid for pid, player in self.game_state.players.items() if player.is_active]
            
            if not active_player_ids:
                return
            
            # Set current player status to ready before moving to next player
            if self.game_state.current_player_id:
                player = self.game_state.players.get(self.game_state.current_player_id)
                if player:
                    player.set_status(PlayerStatus.READY)
                    custom_log(f"Player {self.game_state.current_player_id} status set to READY", level="INFO", isOn=LOGGING_SWITCH)
            
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
            
            # Check if recall has been called
            if hasattr(self.game_state, 'recall_called_by') and self.game_state.recall_called_by:
                
                # Check if current player is the one who called recall
                if self.game_state.current_player_id == self.game_state.recall_called_by:
                    self._handle_end_of_match()
                    return
                else:
                    pass
            else:
                pass
            
            # Send turn started event to new player
            self.start_turn()
            
        except Exception as e:
            pass
    
    def _handle_end_of_match(self):
        """Handle the end of the match"""
        try:
            
            # Collect all player data for scoring
            player_results = {}
            
            for player_id, player in self.game_state.players.items():
                if not player.is_active:
                    continue
                    
                # Get hand cards (filter out None values for consistency)
                hand_cards = [card for card in player.hand if card is not None]
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
            for player_id, data in player_results.items():
                pass
            
            # Determine winner based on Recall game rules
            winner_data = self._determine_winner(player_results)
            
            # Set game phase to GAME_ENDED
            self.game_state.phase = GamePhase.GAME_ENDED
            custom_log(f"Game phase set to GAME_ENDED", level="INFO", isOn=LOGGING_SWITCH)
            
            # Set winner status and log results
            if winner_data['is_tie']:
                custom_log(f"Game ended in a tie: {winner_data.get('winners', [])}", level="INFO", isOn=LOGGING_SWITCH)
                # For ties, set all tied players to FINISHED status
                for winner_name in winner_data.get('winners', []):
                    for player_id, player in self.game_state.players.items():
                        if player.name == winner_name:
                            player.set_status(PlayerStatus.FINISHED)
                            custom_log(f"Player {player.name} set to FINISHED status (tie)", level="INFO", isOn=LOGGING_SWITCH)
            else:
                winner_id = winner_data.get('winner_id')
                winner_name = winner_data.get('winner_name')
                win_reason = winner_data.get('win_reason', 'unknown')
                
                custom_log(f"Game ended - Winner: {winner_name} (ID: {winner_id}) - Reason: {win_reason}", level="INFO", isOn=LOGGING_SWITCH)
                
                # Set winner status
                if winner_id and winner_id in self.game_state.players:
                    self.game_state.players[winner_id].set_status(PlayerStatus.WINNER)
                    custom_log(f"Player {winner_name} set to WINNER status", level="INFO", isOn=LOGGING_SWITCH)
                
                # Set all other players to FINISHED status
                for player_id, player in self.game_state.players.items():
                    if player_id != winner_id:
                        player.set_status(PlayerStatus.FINISHED)
                        custom_log(f"Player {player.name} set to FINISHED status", level="INFO", isOn=LOGGING_SWITCH)
            
            # TODO: Send results to all players
            
        except Exception as e:
            custom_log(f"Error in _handle_end_of_match: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)
    
    def _determine_winner(self, player_results: Dict[str, Any]) -> Dict[str, Any]:
        """Determine the winner based on Recall game rules"""
        try:
            # Rule 1: Check for player with 0 cards (automatic win)
            for player_id, data in player_results.items():
                if data['card_count'] == 0:
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
            
            # Rule 3: If only one player with lowest points, they win
            if len(lowest_point_players) == 1:
                winner_id, winner_data = lowest_point_players[0]
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
                
                # Check if recall caller is among the lowest point players
                for player_id, data in lowest_point_players:
                    if player_id == recall_caller_id:
                        return {
                            'is_tie': False,
                            'winner_id': player_id,
                            'winner_name': data['player_name'],
                            'win_reason': 'recall_caller_lowest_points',
                            'winners': []
                        }
            
            # Rule 5: Multiple players with lowest points, none are recall callers - TIE
            winner_names = [data['player_name'] for _, data in lowest_point_players]
            return {
                'is_tie': True,
                'winner_id': None,
                'winner_name': None,
                'win_reason': 'tie_lowest_points',
                'winners': winner_names
            }
            
        except Exception as e:
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
                return
                
            ws_manager = self.game_state.app_manager.get_websocket_manager()
            if not ws_manager:
                return
            
            current_player_id = self.game_state.current_player_id
            if not current_player_id:
                return
            
            # Get player session ID
            session_id = self._get_player_session_id(current_player_id)
            if not session_id:
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
            
        except Exception as e:
            pass
    
    def _get_player_session_id(self, player_id: str) -> Optional[str]:
        """Get session ID for a player"""
        try:
            # Access the player sessions directly from game state
            return self.game_state.get_player_session(player_id)
        except Exception as e:
            return None
    
    def _get_player(self, player_id: str) -> Optional[Player]:
        """Get player object from game state"""
        try:
            return self.game_state.players.get(player_id)
        except Exception as e:
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
            # Jack swap specific fields
            'first_card_id': data.get('first_card_id'),
            'first_player_id': data.get('first_player_id'),
            'second_card_id': data.get('second_card_id'),
            'second_player_id': data.get('second_player_id'),
            # Queen peek specific fields
            'queen_peek_card_id': data.get('card_id'),
            'queen_peek_player_id': data.get('player_id'),
            'ownerId': data.get('ownerId'),  # Card owner ID for queen peek
        }
    
    def _extract_user_id(self, session_id: str, data: Dict[str, Any]) -> str:
        """Extract user ID from session data or request data"""
        try:
            session_data = self.websocket_manager.get_session_data(session_id) if self.websocket_manager else {}
            return str(session_data.get('user_id') or data.get('user_id') or data.get('player_id') or session_id)
        except Exception as e:
            return session_id
    
    def _route_action(self, action: str, user_id: str, action_data: Dict[str, Any]) -> bool:
        """Route action to appropriate handler and return result"""
        try:
            custom_log("Routing action: " + action + " user_id: " + user_id + " action_data: " + str(action_data), isOn=LOGGING_SWITCH)
            if action == 'draw_from_deck':
                # Log pile contents before drawing
                custom_log(f"=== PILE CONTENTS BEFORE DRAW ===", isOn=LOGGING_SWITCH)
                custom_log(f"Draw Pile Count: {len(self.game_state.draw_pile)}", isOn=LOGGING_SWITCH)
                custom_log(f"Draw Pile Top 3: {[card.card_id for card in self.game_state.draw_pile[:3]]}", isOn=LOGGING_SWITCH)
                custom_log(f"Discard Pile Count: {len(self.game_state.discard_pile)}", isOn=LOGGING_SWITCH)
                custom_log(f"Discard Pile Top 3: {[card.card_id for card in self.game_state.discard_pile[:3]]}", isOn=LOGGING_SWITCH)
                custom_log(f"=================================", isOn=LOGGING_SWITCH)
                return self._handle_draw_from_pile(user_id, action_data)
            elif action == 'play_card':
                play_result = self._handle_play_card(user_id, action_data)
                # Note: _handle_play_card already calls _check_special_card internally
                same_rank_data = self._handle_same_rank_window(action_data)
                return play_result
            elif action == 'same_rank_play':
                return self._handle_same_rank_play(user_id, action_data)
            elif action == 'discard_card':
                return True  # Placeholder - will be False when implemented
            elif action == 'take_from_discard':
                return True  # Placeholder - will be False when implemented
            elif action == 'call_recall':
                return True  # Placeholder - will be False when implemented
            elif action == 'jack_swap':
                return self._handle_jack_swap(user_id, action_data)
            elif action == 'queen_peek':
                return self._handle_queen_peek(user_id, action_data)
            else:
                return False
        except Exception as e:
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
                    return {}
            else:
                return {}
        except Exception as e:
            return {}

    
    # =======================================================
    # Player Actions
    # =======================================================

    def on_player_action(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle player actions through the game round"""
        try:
            
            action = data.get('action') or data.get('action_type')
            if not action:
                custom_log(f"on_player_action: No action found in data: {data}", level="DEBUG", isOn=LOGGING_SWITCH)
                return False
                
            # Get player ID from session data or request data
            user_id = self._extract_user_id(session_id, data)
            custom_log(f"on_player_action: action={action}, user_id={user_id}", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Validate player exists before proceeding with any action
            if user_id not in self.game_state.players:
                custom_log(f"on_player_action: Player {user_id} not found in game state players: {list(self.game_state.players.keys())}", level="DEBUG", isOn=LOGGING_SWITCH)
                return False
            
            # Build action data for the round
            action_data = self._build_action_data(data)
            
            # Route to appropriate action handler based on action type and wait for completion
            action_result = self._route_action(action, user_id, action_data)
            
            # Update game state timestamp after successful action
            if action_result:
                self.game_state.last_action_time = time.time()
            
            # Return the round completion result
            return True
            
        except Exception as e:
            return False


    def _handle_same_rank_window(self, action_data: Dict[str, Any]) -> bool:
        """Handle same rank window action - sets all players to same_rank_window status"""
        try:
            custom_log("Starting same rank window - setting all players to SAME_RANK_WINDOW status", level="INFO", isOn=LOGGING_SWITCH)
            
            # Set game state phase to SAME_RANK_WINDOW
            self.game_state.phase = GamePhase.SAME_RANK_WINDOW
            
            # Update all players' status to SAME_RANK_WINDOW efficiently (single game state update)
            updated_count = self.game_state.update_all_players_status(PlayerStatus.SAME_RANK_WINDOW, filter_active=True)
            custom_log(f"Updated {updated_count} players' status to SAME_RANK_WINDOW", level="INFO", isOn=LOGGING_SWITCH)
            
            # Set 5-second timer to automatically end same rank window
            self._start_same_rank_timer()
            
            return True
            
        except Exception as e:
            custom_log(f"Error in _handle_same_rank_window: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return False
    
    def _start_same_rank_timer(self):
        """Start a 5-second timer for the same rank window"""
        try:
            import threading
            
            # Store timer reference for potential cancellation
            self.same_rank_timer = threading.Timer(5.0, self._end_same_rank_window)
            self.same_rank_timer.start()
            
        except Exception as e:
            pass
    
    def _end_same_rank_window(self):
        """End the same rank window and transition to ENDING_ROUND phase"""
        try:
            custom_log("Ending same rank window - resetting all players to WAITING status", level="INFO", isOn=LOGGING_SWITCH)
            
            # Log the same_rank_data before clearing it
            if self.same_rank_data:
                custom_log(f"Same rank plays recorded: {len(self.same_rank_data)} players", level="INFO", isOn=LOGGING_SWITCH)
                for player_id, play_data in self.same_rank_data.items():
                    custom_log(f"Player {player_id} played: {play_data.get('rank')} of {play_data.get('suit')}", level="INFO", isOn=LOGGING_SWITCH)
            else:
                custom_log("No same rank plays recorded", level="INFO", isOn=LOGGING_SWITCH)
            
            # Update all players' status to WAITING efficiently (single game state update)
            updated_count = self.game_state.update_all_players_status(PlayerStatus.WAITING, filter_active=True)
            custom_log(f"Updated {updated_count} players' status to WAITING", level="INFO", isOn=LOGGING_SWITCH)
            
            # Check if any player has no cards left (automatic win condition)
            for player_id, player in self.game_state.players.items():
                if not player.is_active:
                    continue
                
                # Count actual cards (excluding None/blank slots)
                actual_cards = [card for card in player.hand if card is not None]
                card_count = len(actual_cards)
                
                if card_count == 0:
                    custom_log(f"Player {player_id} ({player.name}) has no cards left - triggering end of match", level="INFO", isOn=LOGGING_SWITCH)
                    self._handle_end_of_match()
                    return  # Exit early since game is ending
                        
            # Clear same_rank_data after changing game phase using custom method
            self.game_state.clear_same_rank_data()
            
            # Send game state update to all players
            if self.game_state.app_manager:
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_game_state_update(self.game_state.game_id)

            # Check for special cards and handle them
            self._handle_special_cards_window()
            
        except Exception as e:
            pass
    
    def cancel_same_rank_timer(self):
        """Cancel the same rank window timer if it's running"""
        try:
            if self.same_rank_timer and self.same_rank_timer.is_alive():
                self.same_rank_timer.cancel()
                self.same_rank_timer = None
            else:
                pass
        except Exception as e:
            pass

    def _handle_special_cards_window(self):
        """Handle special cards window - process each player's special card with 10-second timer"""
        try:
            # Check if we have any special cards played
            if not self.special_card_data:
                custom_log("No special cards played in this round - transitioning directly to ENDING_ROUND", level="INFO", isOn=LOGGING_SWITCH)
                # No special cards, go directly to ENDING_ROUND
                self.game_state.phase = GamePhase.ENDING_ROUND
                custom_log("Game phase changed to ENDING_ROUND (no special cards)", level="INFO", isOn=LOGGING_SWITCH)
                # Continue with normal turn flow since there are no special cards to process
                self.continue_turn()
                return
            
            # We have special cards, transition to SPECIAL_PLAY_WINDOW
            self.game_state.phase = GamePhase.SPECIAL_PLAY_WINDOW
            custom_log("Game phase changed to SPECIAL_PLAY_WINDOW (special cards found)", level="INFO", isOn=LOGGING_SWITCH)
            
            custom_log(f"=== SPECIAL CARDS WINDOW ===", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"DEBUG: special_card_data length: {len(self.special_card_data) if self.special_card_data else 0}", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"DEBUG: Current game phase: {self.game_state.phase}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Count total special cards (now stored chronologically)
            total_special_cards = len(self.special_card_data)
            custom_log(f"Found {total_special_cards} special cards played in chronological order", level="INFO", isOn=LOGGING_SWITCH)
            
            # Log details of all special cards in chronological order
            for i, card in enumerate(self.special_card_data):
                custom_log(f"  {i+1}. Player {card['player_id']}: {card['rank']} of {card['suit']} ({card['special_power']})", level="INFO", isOn=LOGGING_SWITCH)
            
            # Create a working copy for processing (we'll remove cards as we process them)
            self.special_card_players = self.special_card_data.copy()
            
            custom_log(f"Starting special card processing with {len(self.special_card_players)} cards", level="INFO", isOn=LOGGING_SWITCH)
                     
            # Start processing the first player's special card
            self._process_next_special_card()
            
        except Exception as e:
            custom_log(f"Error in _handle_special_cards_window: {e}", level="ERROR", isOn=LOGGING_SWITCH)
    
    def _process_next_special_card(self):
        """Process the next player's special card with 10-second timer"""
        try:
            # Check if we've processed all special cards (list is empty)
            if not self.special_card_players:
                custom_log("All special cards processed - transitioning to ENDING_ROUND", level="INFO", isOn=LOGGING_SWITCH)
                self._end_special_cards_window()
                return
            
            # Get the first special card data (chronological order)
            special_data = self.special_card_players[0]
            player_id = special_data.get('player_id', 'unknown')
            
            card_rank = special_data.get('rank', 'unknown')
            card_suit = special_data.get('suit', 'unknown')
            special_power = special_data.get('special_power', 'unknown')
            description = special_data.get('description', 'No description')
            
            custom_log(f"Processing special card for player {player_id}: {card_rank} of {card_suit}", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"  Special Power: {special_power}", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"  Description: {description}", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"  Remaining cards to process: {len(self.special_card_players)}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Set player status based on special power
            if special_power == 'jack_swap':
                # Use the efficient batch update method to set player status
                self.game_state.update_players_status_by_ids([player_id], PlayerStatus.JACK_SWAP)
                custom_log(f"Player {player_id} status set to JACK_SWAP - 10 second timer started", level="INFO", isOn=LOGGING_SWITCH)
            elif special_power == 'queen_peek':
                # Use the efficient batch update method to set player status
                self.game_state.update_players_status_by_ids([player_id], PlayerStatus.QUEEN_PEEK)
                custom_log(f"Player {player_id} status set to PEEKING - 10 second timer started", level="INFO", isOn=LOGGING_SWITCH)
            else:
                custom_log(f"Unknown special power: {special_power} for player {player_id}", level="WARNING", isOn=LOGGING_SWITCH)
                # Remove this card and move to next
                self.special_card_players.pop(0)
            
            # Start 10-second timer for this player's special card play
            self.special_card_timer = threading.Timer(10.0, self._on_special_card_timer_expired)
            self.special_card_timer.start()
            custom_log(f"10-second timer started for player {player_id}'s {special_power}", level="INFO", isOn=LOGGING_SWITCH)
            
        except Exception as e:
            custom_log(f"Error in _process_next_special_card: {e}", level="ERROR", isOn=LOGGING_SWITCH)
    
    def _on_special_card_timer_expired(self):
        """Called when the special card timer expires - move to next player or end window"""
        try:
            # Reset current player's status to WAITING (if there are still cards to process)
            if self.special_card_players:
                special_data = self.special_card_players[0]
                player_id = special_data.get('player_id', 'unknown')
                self.game_state.update_players_status_by_ids([player_id], PlayerStatus.WAITING)
                custom_log(f"Player {player_id} special card timer expired - status reset to WAITING", level="INFO", isOn=LOGGING_SWITCH)
                
                # Remove the processed card from the list
                self.special_card_players.pop(0)
                custom_log(f"Removed processed card from list. Remaining cards: {len(self.special_card_players)}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Process next special card or end window
            self._process_next_special_card()
            
        except Exception as e:
            custom_log(f"Error in _on_special_card_timer_expired: {e}", level="ERROR", isOn=LOGGING_SWITCH)
    
    def _end_special_cards_window(self):
        """End the special cards window and transition to ENDING_ROUND"""
        try:
            # Cancel any running timer
            self.cancel_special_card_timer()
            
            # Clear special card data
            if self.special_card_data:
                self.special_card_data.clear()
                custom_log("Special card data cleared", level="INFO", isOn=LOGGING_SWITCH)
            
            # Reset special card processing variables
            self.special_card_players = []
            
            # Transition to ENDING_ROUND phase
            self.game_state.phase = GamePhase.TURN_PENDING_EVENTS
  
            # Now that special cards window is complete, continue with normal turn flow
            # This will move to the next player since we're no longer in SPECIAL_PLAY_WINDOW
            self.continue_turn()
            
        except Exception as e:
            custom_log(f"Error in _end_special_cards_window: {e}", level="ERROR", isOn=LOGGING_SWITCH)
    
    def cancel_special_card_timer(self):
        """Cancel the special card timer if it's running"""
        try:
            if hasattr(self, 'special_card_timer') and self.special_card_timer and self.special_card_timer.is_alive():
                self.special_card_timer.cancel()
                self.special_card_timer = None
                custom_log("Special card timer cancelled", level="INFO", isOn=LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"Error cancelling special card timer: {e}", level="ERROR", isOn=LOGGING_SWITCH)

    def _handle_draw_from_pile(self, player_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle drawing a card from the deck or discard pile"""
        try:
            custom_log(f"_handle_draw_from_pile called for player {player_id} with action_data {action_data}", isOn=LOGGING_SWITCH)
            # Get the source pile (deck or discard)
            source = action_data.get('source')
            if not source:
                return False
            
            # Validate source
            if source not in ['deck', 'discard']:
                return False
            
            # Player validation already done in on_player_action
            player = self._get_player(player_id)
            if not player:
                return False
            
            # Draw card based on source using custom methods with auto change detection
            drawn_card = None
            
            if source == 'deck':
                # Draw from draw pile using custom method
                drawn_card = self.game_state.draw_from_draw_pile()
                if not drawn_card:
                    custom_log(f"Failed to draw from draw pile for player {player_id}", level="ERROR", isOn=LOGGING_SWITCH)
                    return False
                
                # Check if draw pile is now empty (special game logic)
                if self.game_state.is_draw_pile_empty():
                    custom_log("Draw pile is now empty", level="INFO", isOn=LOGGING_SWITCH)
                
            elif source == 'discard':
                # Take from discard pile using custom method
                drawn_card = self.game_state.draw_from_discard_pile()
                if not drawn_card:
                    custom_log(f"Failed to draw from discard pile for player {player_id}", level="ERROR", isOn=LOGGING_SWITCH)
                    return False
            
            # Add card to player's hand (drawn cards always go to the end)
            player.add_card_to_hand(drawn_card, is_drawn_card=True)
            
            # Set the drawn card property
            player.set_drawn_card(drawn_card)
            
            # Change player status from DRAWING_CARD to PLAYING_CARD after successful draw
            player.set_status(PlayerStatus.PLAYING_CARD)
            custom_log(f"Player {player_id} status changed from DRAWING_CARD to PLAYING_CARD", level="INFO", isOn=LOGGING_SWITCH)
            
            # Log pile contents after successful draw using helper methods
            custom_log(f"=== PILE CONTENTS AFTER DRAW ===", isOn=LOGGING_SWITCH)
            custom_log(f"Draw Pile Count: {self.game_state.get_draw_pile_count()}", isOn=LOGGING_SWITCH)
            custom_log(f"Draw Pile Top 3: {[card.card_id for card in self.game_state.draw_pile[:3]]}", isOn=LOGGING_SWITCH)
            custom_log(f"Discard Pile Count: {self.game_state.get_discard_pile_count()}", isOn=LOGGING_SWITCH)
            custom_log(f"Discard Pile Top 3: {[card.card_id for card in self.game_state.discard_pile[:3]]}", isOn=LOGGING_SWITCH)
            custom_log(f"Drawn Card: {drawn_card.card_id if drawn_card else 'None'}", isOn=LOGGING_SWITCH)
            custom_log(f"=================================", isOn=LOGGING_SWITCH)
            
            return True
            
        except Exception as e:
            return False

    def _handle_play_card(self, player_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle playing a card from the player's hand"""
        try:
            
            # Extract key information from action_data
            card_id = action_data.get('card_id', 'unknown')
            game_id = action_data.get('game_id', 'unknown')
            
            # Player validation already done in on_player_action
            player = self._get_player(player_id)
            if not player:
                return False
            
            # Find the card in the player's hand
            card_to_play = None
            card_index = -1
            
            for i, card in enumerate(player.hand):
                if card is not None and card.card_id == card_id:
                    card_to_play = card
                    card_index = i
                    break
            
            if not card_to_play:
                custom_log(f"Card {card_id} not found in player {player_id} hand", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            custom_log(f"Found card {card_id} at index {card_index} in player {player_id} hand", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Handle drawn card repositioning BEFORE removing the played card
            drawn_card = player.get_drawn_card()
            drawn_card_original_index = -1
            
            if drawn_card and drawn_card.card_id != card_id:
                # The played card was NOT the drawn card, so we need to reposition the drawn card
                # Find the drawn card in the hand BEFORE removing the played card
                for i, card in enumerate(player.hand):
                    if card is not None and card.card_id == drawn_card.card_id:
                        drawn_card_original_index = i
                        break
            
            # Use the proper method to remove card with change detection
            custom_log(f"About to call remove_card_from_hand for card {card_id}", level="DEBUG", isOn=LOGGING_SWITCH)
            try:
                removed_card = player.remove_card_from_hand(card_id)
                if not removed_card:
                    custom_log(f"Failed to remove card {card_id} from player {player_id} hand", level="ERROR", isOn=LOGGING_SWITCH)
                    return False
                custom_log(f"Successfully removed card {card_id} from player {player_id} hand", level="DEBUG", isOn=LOGGING_SWITCH)
            except Exception as e:
                custom_log(f"Exception in remove_card_from_hand: {e}", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Add card to discard pile using custom method with auto change detection
            if not self.game_state.add_to_discard_pile(removed_card):
                custom_log(f"Failed to add card {card_id} to discard pile", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Handle drawn card repositioning with smart blank slot system
            if drawn_card and drawn_card.card_id != card_id:
                # The drawn card should fill the blank slot left by the played card
                # The blank slot is at card_index (where the played card was)
                custom_log(f"Repositioning drawn card {drawn_card.card_id} to index {card_index}", level="DEBUG", isOn=LOGGING_SWITCH)
                
                # First, find and remove the drawn card from its original position
                original_index = None
                for i, card in enumerate(player.hand):
                    if card is not None and card.card_id == drawn_card.card_id:
                        original_index = i
                        break
                
                if original_index is not None:
                    # Apply smart blank slot logic to the original position
                    should_keep_original_slot = player._should_create_blank_slot_at_index(original_index)
                    
                    if should_keep_original_slot:
                        player.hand[original_index] = None  # Create blank slot
                        custom_log(f"Created blank slot at original position {original_index}", level="DEBUG", isOn=LOGGING_SWITCH)
                    else:
                        player.hand.pop(original_index)  # Remove entirely
                        custom_log(f"Removed card entirely from original position {original_index}", level="DEBUG", isOn=LOGGING_SWITCH)
                        # Adjust target index if we removed a card before it
                        if original_index < card_index:
                            card_index -= 1
                
                # Apply smart blank slot logic to the target position
                should_place_in_slot = player._should_create_blank_slot_at_index(card_index)
                
                if should_place_in_slot:
                    # Place it in the blank slot left by the played card
                    player.hand[card_index] = drawn_card  # Store the Card object, not just the ID
                    custom_log(f"Placed drawn card in blank slot at index {card_index}", level="DEBUG", isOn=LOGGING_SWITCH)
                else:
                    # The slot shouldn't exist, so append the drawn card to the end
                    player.hand.append(drawn_card)  # Store the Card object, not just the ID
                    custom_log(f"Appended drawn card to end of hand (slot {card_index} shouldn't exist)", level="DEBUG", isOn=LOGGING_SWITCH)
                
                # IMPORTANT: After repositioning, the drawn card becomes a regular hand card
                # Clear the drawn card property since it's no longer "drawn"
                player.clear_drawn_card()
                
                # Manually trigger change detection for hand modification
                if hasattr(player, '_track_change'):
                    player._track_change('hand')
                    player._send_changes_if_needed()
                
                custom_log(f"After repositioning: hand slots = {[card.card_id if card else 'None' for card in player.hand]}", level="DEBUG", isOn=LOGGING_SWITCH)
                
            elif drawn_card and drawn_card.card_id == card_id:
                # Clear the drawn card property since it's now in the discard pile
                player.clear_drawn_card()
            else:
                pass
            
            # Log pile contents after successful play
            custom_log(f"=== PILE CONTENTS AFTER PLAY ===", isOn=LOGGING_SWITCH)
            custom_log(f"Draw Pile Count: {len(self.game_state.draw_pile)}", isOn=LOGGING_SWITCH)
            custom_log(f"Draw Pile Top 3: {[card.card_id for card in self.game_state.draw_pile[:3]]}", isOn=LOGGING_SWITCH)
            custom_log(f"Discard Pile Count: {len(self.game_state.discard_pile)}", isOn=LOGGING_SWITCH)
            custom_log(f"Discard Pile Top 3: {[card.card_id for card in self.game_state.discard_pile[:3]]}", isOn=LOGGING_SWITCH)
            custom_log(f"Played Card: {card_to_play.card_id if card_to_play else 'None'}", isOn=LOGGING_SWITCH)
            custom_log(f"=================================", isOn=LOGGING_SWITCH)
            
            # Check if the played card has special powers (Jack/Queen)
            self._check_special_card(player_id, {
                'card_id': card_id,
                'rank': card_to_play.rank,
                'suit': card_to_play.suit
            })
            
            return True
            
        except Exception as e:
            return False  
    
    def _handle_same_rank_play(self, user_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle same rank play action - validates rank match and stores the play in same_rank_data for multiple players"""
        try:
            
            # Extract card details from action_data
            card_id = action_data.get('card_id', 'unknown')
            
            # Get player and find the card to get its rank and suit
            player = self.game_state.players.get(user_id)
            if not player:
                return False
            
            # Find the card in player's hand
            played_card = None
            for card in player.hand:
                if card is not None and card.card_id == card_id:
                    played_card = card
                    break
            
            if not played_card:
                custom_log(f"Card {card_id} not found in player {user_id} hand for same rank play", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            custom_log(f"Found card {card_id} for same rank play in player {user_id} hand", level="DEBUG", isOn=LOGGING_SWITCH)
            
            card_rank = played_card.rank
            card_suit = played_card.suit
            
            # Validate that this is actually a same rank play
            if not self._validate_same_rank_play(card_rank):
                
                # Apply penalty: draw a card from the draw pile
                penalty_card = self._apply_same_rank_penalty(user_id)
                if penalty_card:
                    pass
                else:
                    pass
                
                return False
            
            # SUCCESSFUL SAME RANK PLAY - Remove card from hand and add to discard pile
            # Use the proper method to remove card with change detection
            custom_log(f"About to call remove_card_from_hand for same rank play card {card_id}", level="DEBUG", isOn=LOGGING_SWITCH)
            try:
                removed_card = player.remove_card_from_hand(card_id)
                if not removed_card:
                    custom_log(f"Failed to remove card {card_id} from player {user_id} hand", level="ERROR", isOn=LOGGING_SWITCH)
                    return False
                custom_log(f"Successfully removed same rank play card {card_id} from player {user_id} hand", level="DEBUG", isOn=LOGGING_SWITCH)
            except Exception as e:
                custom_log(f"Exception in remove_card_from_hand for same rank play: {e}", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Add card to discard pile using custom method with auto change detection
            if not self.game_state.add_to_discard_pile(removed_card):
                custom_log(f"Failed to add card {card_id} to discard pile", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            custom_log(f"✅ Same rank play successful: {user_id} played {card_rank} of {card_suit} - card moved to discard pile", level="INFO", isOn=LOGGING_SWITCH)
            
            # Check for special cards (Jack/Queen) and store data if applicable
            # Pass the correct card data structure to _check_special_card
            card_data = {
                'card_id': card_id,
                'rank': card_rank,
                'suit': card_suit
            }
            self._check_special_card(user_id, card_data)
            
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
            
            # Log all current plays for debugging
            for pid, play in self.same_rank_data.items():
                pass
            
            return True
            
        except Exception as e:
            return False
    
    def _validate_same_rank_play(self, card_rank: str) -> bool:
        """Validate that the played card has the same rank as the last card in the discard pile"""
        try:
            # Check if there are any cards in the discard pile
            if not self.game_state.discard_pile:
                custom_log(f"Same rank validation failed: No cards in discard pile", level="DEBUG", isOn=LOGGING_SWITCH)
                return False
            
            # Get the last card from the discard pile
            last_card = self.game_state.discard_pile[-1]
            last_card_rank = last_card.rank
            
            custom_log(f"Same rank validation: played_card_rank='{card_rank}', last_card_rank='{last_card_rank}'", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Handle special case: first card of the game (no previous card to match)
            if len(self.game_state.discard_pile) == 1:
                custom_log(f"Same rank validation: First card of game, allowing play", level="DEBUG", isOn=LOGGING_SWITCH)
                return True
            
            # Check if ranks match (case-insensitive for safety)
            if card_rank.lower() == last_card_rank.lower():
                custom_log(f"Same rank validation: Ranks match, allowing play", level="DEBUG", isOn=LOGGING_SWITCH)
                return True
            else:
                custom_log(f"Same rank validation: Ranks don't match, denying play", level="DEBUG", isOn=LOGGING_SWITCH)
                return False
                
        except Exception as e:
            custom_log(f"Same rank validation error: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return False
    
    def _apply_same_rank_penalty(self, player_id: str) -> Optional[Card]:
        """Apply penalty for invalid same rank play - draw a card from the draw pile"""
        try:
            
            # Check if draw pile has cards
            if not self.game_state.draw_pile:
                return None
            
            # Get player object
            player = self._get_player(player_id)
            if not player:
                return None
            
            # Draw penalty card from draw pile using custom method with auto change detection
            penalty_card = self.game_state.draw_from_draw_pile()
            if not penalty_card:
                custom_log(f"Failed to draw penalty card from draw pile for player {player_id}", level="ERROR", isOn=LOGGING_SWITCH)
                return None
            
            # Add penalty card to player's hand
            player.add_card_to_hand(penalty_card, is_penalty_card=True)
            
            # Update player status to indicate they received a penalty
            player.set_status(PlayerStatus.WAITING)  # Reset to waiting after penalty
            custom_log(f"Player {player_id} status reset to WAITING after penalty", level="INFO", isOn=LOGGING_SWITCH)
            
            return penalty_card
            
        except Exception as e:
            return None
    
    def _check_special_card(self, player_id: str, action_data: Dict[str, Any]) -> None:
        """Check if a played card has special powers (Jack/Queen) and set player status accordingly"""
        try:
            # Extract card details from action_data
            card_id = action_data.get('card_id', 'unknown')
            card_rank = action_data.get('rank', 'unknown')
            card_suit = action_data.get('suit', 'unknown')
            
            if card_rank == 'jack':
                # Store special card data chronologically (not grouped by player)
                special_card_info = {
                    'player_id': player_id,
                    'card_id': card_id,
                    'rank': card_rank,
                    'suit': card_suit,
                    'special_power': 'jack_swap',
                    'timestamp': time.time(),
                    'description': 'Can switch any two cards between players'
                }
                custom_log(f"DEBUG: special_card_data length before adding Jack: {len(self.special_card_data)}", level="INFO", isOn=LOGGING_SWITCH)
                self.special_card_data.append(special_card_info)
                custom_log(f"DEBUG: special_card_data length after adding Jack: {len(self.special_card_data)}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"Added Jack special card for player {player_id}: {card_rank} of {card_suit} (chronological order)", level="INFO", isOn=LOGGING_SWITCH)
                
            elif card_rank == 'queen':
                # Store special card data chronologically (not grouped by player)
                special_card_info = {
                    'player_id': player_id,
                    'card_id': card_id,
                    'rank': card_rank,
                    'suit': card_suit,
                    'special_power': 'queen_peek',
                    'timestamp': time.time(),
                    'description': 'Can look at one card from any player\'s hand'
                }
                custom_log(f"DEBUG: special_card_data length before adding Queen: {len(self.special_card_data)}", level="INFO", isOn=LOGGING_SWITCH)
                self.special_card_data.append(special_card_info)
                custom_log(f"DEBUG: special_card_data length after adding Queen: {len(self.special_card_data)}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"Added Queen special card for player {player_id}: {card_rank} of {card_suit} (chronological order)", level="INFO", isOn=LOGGING_SWITCH)
                
            else:
                pass
                
        except Exception as e:
            custom_log(f"Error in _check_special_card: {e}", level="ERROR", isOn=LOGGING_SWITCH)

    def _handle_jack_swap(self, user_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle Jack swap action - swap two cards between players"""
        try:
            custom_log(f"Handling Jack swap for player {user_id} with data: {action_data}", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Extract card information from action data
            first_card_id = action_data.get('first_card_id')
            first_player_id = action_data.get('first_player_id')
            second_card_id = action_data.get('second_card_id')
            second_player_id = action_data.get('second_player_id')
            
            # Validate required data
            if not all([first_card_id, first_player_id, second_card_id, second_player_id]):
                custom_log(f"Invalid Jack swap data - missing required fields", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Validate both players exist
            if first_player_id not in self.game_state.players or second_player_id not in self.game_state.players:
                custom_log(f"Invalid Jack swap - one or both players not found", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Get player objects
            first_player = self.game_state.players[first_player_id]
            second_player = self.game_state.players[second_player_id]
            
            # Find the cards in each player's hand
            first_card = None
            first_card_index = None
            second_card = None
            second_card_index = None
            
            # Find first card
            for i, card in enumerate(first_player.hand):
                if card is not None and card.card_id == first_card_id:
                    first_card = card
                    first_card_index = i
                    break
            
            # Find second card
            for i, card in enumerate(second_player.hand):
                if card is not None and card.card_id == second_card_id:
                    second_card = card
                    second_card_index = i
                    break
            
            # Validate cards found
            if not first_card or not second_card:
                custom_log(f"Invalid Jack swap - one or both cards not found in players' hands", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Perform the swap
            first_player.hand[first_card_index] = second_card
            second_player.hand[second_card_index] = first_card
            
            # Update card ownership
            first_card.owner_id = first_player_id
            second_card.owner_id = second_player_id
            
            custom_log(f"Successfully swapped cards: {first_card.card_id} <-> {second_card.card_id}", level="INFO", isOn=LOGGING_SWITCH)
            custom_log(f"Player {first_player_id} now has: {[card.card_id if card else None for card in first_player.hand]}", level="DEBUG", isOn=LOGGING_SWITCH)
            custom_log(f"Player {second_player_id} now has: {[card.card_id if card else None for card in second_player.hand]}", level="DEBUG", isOn=LOGGING_SWITCH)
            
            return True
            
        except Exception as e:
            custom_log(f"Error in _handle_jack_swap: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return False

    def _handle_queen_peek(self, user_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle Queen peek action - peek at any one card from any player"""
        try:
            custom_log(f"Handling Queen peek for player {user_id} with data: {action_data}", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Extract data from action
            card_id = action_data.get('card_id')
            owner_id = action_data.get('ownerId')  # Note: using ownerId as per frontend changes
            
            if not card_id or not owner_id:
                custom_log(f"Missing required data for queen peek: card_id={card_id}, ownerId={owner_id}", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Find the target player and card
            target_player = self._get_player(owner_id)
            if not target_player:
                custom_log(f"Target player {owner_id} not found for queen peek", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Find the card in the target player's hand
            target_card = None
            for card in target_player.hand:
                if card and card.card_id == card_id:
                    target_card = card
                    break
            
            if not target_card:
                custom_log(f"Card {card_id} not found in target player {owner_id} hand", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Get the current player (the one doing the peek)
            current_player = self._get_player(user_id)
            if not current_player:
                custom_log(f"Current player {user_id} not found for queen peek", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Clear any existing cards from previous peeks
            current_player.clear_cards_to_peek()
            
            # Add the card to the current player's cards_to_peek list
            current_player.add_card_to_peek(target_card)
            custom_log(f"Added card {card_id} to player {user_id} cards_to_peek list", level="DEBUG", isOn=LOGGING_SWITCH)
            
            # Set player status to PEEKING
            current_player.set_status(PlayerStatus.PEEKING)
            custom_log(f"Set player {user_id} status to PEEKING", level="DEBUG", isOn=LOGGING_SWITCH)
            
            return True
            
        except Exception as e:
            custom_log(f"Error in _handle_queen_peek: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return False

    