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
            # Clear same rank data
            if self.same_rank_data:
                } plays")
                self.same_rank_data.clear()
            
            # Clear special card data
            if self.special_card_data:
                } cards")
                self.special_card_data.clear()
                
            # Initialize round state
            self.round_start_time = time.time()
            self.current_turn_start_time = self.round_start_time
            self.round_status = "active"
            self.actions_performed = []

            self.game_state.phase = GamePhase.PLAYER_TURN
            # Initialize timed rounds if enabled
            if self.timed_rounds_enabled:
                self.round_time_remaining = self.round_time_limit_seconds
                # Log round start
            self._log_action("round_started", {
                "round_number": self.round_number,
                "current_player": self.game_state.current_player_id,
                "player_count": len(self.game_state.players)
            })
            
            # Log actions_performed at round start
            } actions")
            
                        # Update turn start time
            self.current_turn_start_time = time.time()
            
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
            self._move_to_next_player()
            
            return True
            
        except Exception as e:
            return False
    
    def _move_to_next_player(self):
        """Move to the next player in the game"""
        try:
            if not self.game_state.players:
                return
            
            # Get list of active player IDs
            active_player_ids = [pid for pid, player in self.game_state.players.items() if player.is_active]
            
            if not active_player_ids:
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
            
            # Check if recall has been called
            if hasattr(self.game_state, 'recall_called_by') and self.game_state.recall_called_by:
                # Check if current player is the one who called recall
                if self.game_state.current_player_id == self.game_state.recall_called_by:
                    self._handle_end_of_match()
                    return
                else:
                    else:
                # Send turn started event to new player
            self.start_turn()
            
            # Send state update to Flutter for turn change using GameStateManager methods directly
            game_state_manager = self._get_game_state_manager()
            if game_state_manager:
                # Auto-send game_state_updated event (handled by _to_flutter_game_data)
                game_state_manager._to_flutter_game_data(self.game_state, auto_send_event=True)
                except Exception as e:
            def _handle_end_of_match(self):
        """Handle the end of the match"""
        try:
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
                
                : {card_count} cards, {total_points} points")
            
            # Log all results
            } players:")
            for player_id, data in player_results.items():
                # Determine winner based on Recall game rules
            winner_data = self._determine_winner(player_results)
            
            # Log winner
            if winner_data['is_tie']:
                }")
            else:
                ")
            
            # TODO: Send results to all players
            # TODO: Update game state to ended
            
        except Exception as e:
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
            
            }")
            
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
            }")
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
        }
    
    def _extract_user_id(self, session_id: str, data: Dict[str, Any]) -> str:
        """Extract user ID from session data or request data"""
        try:
            session_data = self.websocket_manager.get_session_data(session_id) if self.websocket_manager else {}
            return str(session_data.get('user_id') or data.get('player_id') or session_id)
        except Exception as e:
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
                return True  # Placeholder - will be False when implemented
            elif action == 'take_from_discard':
                return True  # Placeholder - will be False when implemented
            elif action == 'call_recall':
                return True  # Placeholder - will be False when implemented
            else:
                return False
        except Exception as e:
            return False
    
    def _get_game_state_manager(self):
        """Get the GameStateManager instance from app_manager"""
        try:
            if hasattr(self.game_state, 'app_manager') and self.game_state.app_manager:
                game_state_manager = getattr(self.game_state.app_manager, 'game_state_manager', None)
                if game_state_manager:
                    return game_state_manager
                else:
                    return None
            else:
                return None
        except Exception as e:
            return None
    

    # =======================================================
    # Player Actions
    # =======================================================

    def on_player_action(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle player actions through the game round"""
        try:
            action = data.get('action') or data.get('action_type')
            if not action:
                return False
                
            # Get player ID from session data or request data
            user_id = self._extract_user_id(session_id, data)
            
            # Validate player exists before proceeding with any action
            if user_id not in self.game_state.players:
                return False
            
            # Build action data for the round
            action_data = self._build_action_data(data)
            
            # Route to appropriate action handler based on action type and wait for completion
            action_result = self._route_action(action, user_id, action_data)
            
            # Log the action result
            # Update game state timestamp after successful action
            if action_result:
                self.game_state.last_action_time = time.time()
                # Send state update to Flutter using GameStateManager methods directly
                game_state_manager = self._get_game_state_manager()
                if game_state_manager:
                    # Auto-send game_state_updated event (handled by _to_flutter_game_data)
                    game_state_manager._to_flutter_game_data(self.game_state, auto_send_event=True)
                    
                    # Auto-send player-specific state update using _to_flutter_player_data
                    if user_id in self.game_state.players:
                        player = self.game_state.players[user_id]
                        game_state_manager._to_flutter_player_data(
                            player, 
                            is_current=(user_id == self.game_state.current_player_id),
                            auto_send_event=True,
                            game_id=self.game_state.game_id
                        )
                        # Return the round completion result
            return action_result
            
        except Exception as e:
            return False


    def _handle_same_rank_window(self, action_data: Dict[str, Any]) -> bool:
        """Handle same rank window action - sets all players to same_rank_window status"""
        try:
            # Set game state phase to SAME_RANK_WINDOW
            self.game_state.phase = GamePhase.SAME_RANK_WINDOW
            # Set 5-second timer to automatically end same rank window
            self._start_same_rank_timer()
            
            return True
            
        except Exception as e:
            return False
    
    def _start_same_rank_timer(self):
        """Start a 5-second timer for the same rank window"""
        try:
            import threading
            
            # Store timer reference for potential cancellation
            self.same_rank_timer = threading.Timer(5.0, self._end_same_rank_window)
            self.same_rank_timer.start()
            
            except Exception as e:
            def _end_same_rank_window(self):
        """End the same rank window and transition to ENDING_ROUND phase"""
        try:
            # Log the same_rank_data before clearing it
            if self.same_rank_data:
                for player_id, play_data in self.same_rank_data.items():
                    ")
                }")
            else:
                # Set game state to ENDING_ROUND
            self.game_state.phase = GamePhase.ENDING_ROUND
            # Clear same_rank_data after changing game phase
            if self.same_rank_data:
                } plays")
                self.same_rank_data.clear()
            else:
                self.continue_turn()
            
            # Send state update to Flutter for same rank window end using GameStateManager methods directly
            game_state_manager = self._get_game_state_manager()
            if game_state_manager:
                # Auto-send game_state_updated event (handled by _to_flutter_game_data)
                game_state_manager._to_flutter_game_data(self.game_state, auto_send_event=True)
                except Exception as e:
            def cancel_same_rank_timer(self):
        """Cancel the same rank window timer if it's running"""
        try:
            if self.same_rank_timer and self.same_rank_timer.is_alive():
                self.same_rank_timer.cancel()
                self.same_rank_timer = None
                else:
                except Exception as e:
            def _handle_draw_from_pile(self, player_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle drawing a card from the deck or discard pile"""
        try:
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
            
            # Draw card based on source
            drawn_card = None
            
            if source == 'deck':
                # Draw from draw pile (remove last card)
                if not self.game_state.draw_pile:
                    return False
                
                drawn_card = self.game_state.draw_pile.pop()  # Remove last card
                }")
                
                # Check if draw pile is now empty (special game logic)
                if len(self.game_state.draw_pile) == 0:
                    # TODO: Implement special logic for empty draw pile (e.g., game end conditions)
                
            elif source == 'discard':
                # Take from discard pile (remove last card)
                if not self.game_state.discard_pile:
                    return False
                
                drawn_card = self.game_state.discard_pile.pop()  # Remove last card
                }")
            
            if not drawn_card:
                return False
            
            # Add card to player's hand
            player.add_card_to_hand(drawn_card)
            
            # Set the drawn card property
            player.set_drawn_card(drawn_card)
            
            # Game state timestamp update already done in on_player_action
            
            # Log the action
            return True
            
        except Exception as e:
            return False

    def _handle_play_card(self, player_id: str, action_data: Dict[str, Any]) -> bool:
        """Handle playing a card from the player's hand"""
        try:
            # Log the complete payload for debugging
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
                if card.card_id == card_id:
                    card_to_play = card
                    card_index = i
                    break
            
            if not card_to_play:
                return False
            
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
                
                # Remove card from player's hand
            removed_card = player.hand.pop(card_index)
            }")
            
            # Add card to discard pile
            self.game_state.discard_pile.append(removed_card)
            }")
            
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
                to index {card_index}")
                
                # IMPORTANT: After repositioning, the drawn card becomes a regular hand card
                # Clear the drawn card property since it's no longer "drawn"
                player.clear_drawn_card()
                elif drawn_card and drawn_card.card_id == card_id:
                # The played card WAS the drawn card, so no repositioning needed
                # Clear the drawn card property since it's now in the discard pile
                player.clear_drawn_card()
                else:
                # No drawn card, so no repositioning needed
                # Game state timestamp update already done in on_player_action
            
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
                if card.card_id == card_id:
                    played_card = card
                    break
            
            if not played_card:
                return False
            
            card_rank = played_card.rank
            card_suit = played_card.suit
            
            # Validate that this is actually a same rank play
            if not self._validate_same_rank_play(card_rank):
                # Apply penalty: draw a card from the draw pile
                penalty_card = self._apply_same_rank_penalty(user_id)
                if penalty_card:
                    else:
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
            
            }")
            
            # Log all current plays for debugging
            for pid, play in self.same_rank_data.items():
                ")
            
            return True
            
        except Exception as e:
            return False
    
    def _validate_same_rank_play(self, card_rank: str) -> bool:
        """Validate that the played card has the same rank as the last card in the discard pile"""
        try:
            # Check if there are any cards in the discard pile
            if not self.game_state.discard_pile:
                return False
            
            # Get the last card from the discard pile
            last_card = self.game_state.discard_pile[-1]
            last_card_rank = last_card.rank
            
            # Handle special case: first card of the game (no previous card to match)
            if len(self.game_state.discard_pile) == 1:
                return True
            
            # Check if ranks match (case-insensitive for safety)
            if card_rank.lower() == last_card_rank.lower():
                return True
            else:
                return False
                
        except Exception as e:
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
            
            # Draw penalty card from draw pile
            penalty_card = self.game_state.draw_pile.pop()  # Remove last card
            }")
            
            # Add penalty card to player's hand
            player.add_card_to_hand(penalty_card)
            }")
     
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
            
            ")
            
            if card_rank == 'jack':
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
                elif card_rank == 'queen':
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
                else:
                # No special card data to store for regular cards
                
            # Log current special card data status
            }")
            for pid, special_data in self.special_card_data.items():
                except Exception as e:
            