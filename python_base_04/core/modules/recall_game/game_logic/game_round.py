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
from ..utils.computer_player_factory import ComputerPlayerFactory 

LOGGING_SWITCH = True

class GameRound:
    """Manages a single round of gameplay in the Recall game"""
    
    def __init__(self, game_state: GameState):
        self.game_state = game_state
        self.round_number = 1
        self.round_start_time = None
        self.round_end_time = None
        self.current_turn_start_time = None
        self._computer_player_factory = None  # YAML-based computer player factory
        # self.turn_timeout_seconds = 30  # 30 seconds per turn - DEPRECATED: Now using Config.RECALL_PLAYER_ACTION_TIMEOUT
        self.actions_performed = []

        self.same_rank_data = {} # player_id -> same_rank_data
        self.special_card_data = [] # chronological list of special cards
        custom_log(f"DEBUG: GameRound instance created - special_card_data initialized", level="INFO", isOn=LOGGING_SWITCH)
        self.same_rank_timer = None  # Timer for same rank window
        self.special_card_timer = None  # Timer for special card window
        self.special_card_players = []  # List of players who played special cards
        
        # Turn-based timers for drawing and playing phases
        self.draw_phase_timer = None  # Timer for drawing phase (10 seconds)
        self.play_phase_timer = None  # Timer for playing phase (10 seconds)
        self.current_turn_player_id = None  # Track which player's turn it is

        self.pending_events = [] # List of pending events to process before ending round

        self.round_status = "waiting"  # waiting, active, paused, completed
        
        # Timed rounds configuration
        self.timed_rounds_enabled = False
        self.round_time_limit_seconds = 300  # 5 minutes default
        self.round_time_remaining = None
        
        # Load player action timeout from config
        from utils.config.config import Config
        self.player_action_timeout = Config.RECALL_PLAYER_ACTION_TIMEOUT
        custom_log(f"GameRound initialized with player action timeout: {self.player_action_timeout} seconds", level="INFO", isOn=LOGGING_SWITCH)
    
    def _send_error_to_player(self, player_id: str, message: str):
        """Send error message to a player using the coordinator"""
        try:
            # Get session_id from game_state
            session_id = self.game_state.player_sessions.get(player_id)
            if not session_id:
                custom_log(f"No session found for player {player_id}, cannot send error", level="WARNING", isOn=LOGGING_SWITCH)
                return
            
            # Get coordinator from app_manager
            if self.game_state.app_manager:
                coordinator = getattr(self.game_state.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    custom_log(f"Sending error to player {player_id} via session {session_id}: {message}", level="INFO", isOn=LOGGING_SWITCH)
                    coordinator._send_error(session_id, message)
                else:
                    custom_log("No coordinator found, cannot send error", level="WARNING", isOn=LOGGING_SWITCH)
            else:
                custom_log("No app_manager found, cannot send error", level="WARNING", isOn=LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"Error sending error message to player: {e}", level="ERROR", isOn=LOGGING_SWITCH)
        
    def start_turn(self) -> Dict[str, Any]:
        """Start a new round of gameplay"""
        try:
            # Cancel any running timers from the previous turn
            # BUT: Do NOT cancel special card timer if we're still processing special cards
            # The special cards window should complete before starting a new turn
            self.cancel_same_rank_timer()
            if self.game_state.phase != GamePhase.SPECIAL_PLAY_WINDOW:
                self.cancel_special_card_timer()
                custom_log("All timers cancelled at start of new turn (except special card timer if processing)", level="INFO", isOn=LOGGING_SWITCH)
            else:
                custom_log("WARNING: Starting new turn while still in SPECIAL_PLAY_WINDOW phase - this should not happen", level="WARNING", isOn=LOGGING_SWITCH)
                custom_log("Cancelling special card timer and forcing cleanup", level="WARNING", isOn=LOGGING_SWITCH)
                self.cancel_special_card_timer()
            self._cancel_draw_phase_timer()
            self._cancel_play_phase_timer()
            
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
                    
                    # Start draw phase timer (10 seconds)
                    self._start_draw_phase_timer(self.game_state.current_player_id)
                    
                    # Note: Computer player detection is now handled in _move_to_next_player
                    # to avoid duplicate processing
            
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

    def _start_draw_phase_timer(self, player_id: str):
        """Start the 10-second timer for the drawing phase"""
        try:
            self._cancel_draw_phase_timer()
            self.current_turn_player_id = player_id
            self.draw_phase_timer = threading.Timer(
                self.player_action_timeout,
                self._on_draw_phase_timeout
            )
            self.draw_phase_timer.start()
            custom_log(
                f"Started {self.player_action_timeout}-second draw phase timer for player {player_id}",
                level="INFO",
                isOn=LOGGING_SWITCH
            )
        except Exception as e:
            custom_log(f"Error starting draw phase timer: {e}", level="ERROR", isOn=LOGGING_SWITCH)

    def _cancel_draw_phase_timer(self):
        """Cancel the draw phase timer if it's running"""
        try:
            if self.draw_phase_timer and self.draw_phase_timer.is_alive():
                self.draw_phase_timer.cancel()
                self.draw_phase_timer = None
                custom_log("Cancelled draw phase timer", level="DEBUG", isOn=LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"Error cancelling draw phase timer: {e}", level="ERROR", isOn=LOGGING_SWITCH)

    def _on_draw_phase_timeout(self):
        """Called when draw phase timer expires - player didn't draw in time"""
        try:
            if not self.current_turn_player_id:
                return
            
            player_id = self.current_turn_player_id
            custom_log(
                f"Draw phase timeout for player {player_id} - {self.player_action_timeout} seconds expired",
                level="WARNING",
                isOn=LOGGING_SWITCH
            )
            
            # Send timeout error to the player
            self._send_error_to_player(
                player_id,
                f'Draw phase timeout - you have {self.player_action_timeout} seconds to draw a card'
            )
            
            # Clean up timer state
            self.current_turn_player_id = None
            self.draw_phase_timer = None
            
            # Move to next player (existing logic handles status changes)
            custom_log(f"Moving to next player after draw timeout", level="INFO", isOn=LOGGING_SWITCH)
            self._move_to_next_player()
            
        except Exception as e:
            custom_log(f"Error in draw phase timeout handler: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)

    def _start_play_phase_timer(self, player_id: str):
        """Start the 10-second timer for the playing phase"""
        try:
            self._cancel_play_phase_timer()
            self.current_turn_player_id = player_id
            self.play_phase_timer = threading.Timer(
                self.player_action_timeout,
                self._on_play_phase_timeout
            )
            self.play_phase_timer.start()
            custom_log(
                f"Started {self.player_action_timeout}-second play phase timer for player {player_id}",
                level="INFO",
                isOn=LOGGING_SWITCH
            )
        except Exception as e:
            custom_log(f"Error starting play phase timer: {e}", level="ERROR", isOn=LOGGING_SWITCH)

    def _cancel_play_phase_timer(self):
        """Cancel the play phase timer if it's running"""
        try:
            if self.play_phase_timer and self.play_phase_timer.is_alive():
                self.play_phase_timer.cancel()
                self.play_phase_timer = None
                custom_log("Cancelled play phase timer", level="DEBUG", isOn=LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"Error cancelling play phase timer: {e}", level="ERROR", isOn=LOGGING_SWITCH)

    def _on_play_phase_timeout(self):
        """Called when play phase timer expires - player didn't play in time"""
        try:
            if not self.current_turn_player_id:
                return
            
            player_id = self.current_turn_player_id
            custom_log(
                f"Play phase timeout for player {player_id} - {self.player_action_timeout} seconds expired",
                level="WARNING",
                isOn=LOGGING_SWITCH
            )
            
            # Send timeout error to the player
            self._send_error_to_player(
                player_id,
                f'Play phase timeout - you have {self.player_action_timeout} seconds to play a card'
            )
            
            # Clear drawn card state (keeps card in hand but removes "drawn" status)
            player = self.game_state.players.get(player_id)
            if player:
                player.clear_drawn_card()
                custom_log(f"Cleared drawn card state for player {player_id} after play timeout", level="INFO", isOn=LOGGING_SWITCH)
            
            # Clean up timer state
            self.current_turn_player_id = None
            self.play_phase_timer = None
            
            # Move to next player (existing logic handles status changes)
            custom_log(f"Moving to next player after play timeout", level="INFO", isOn=LOGGING_SWITCH)
            self._move_to_next_player()
            
        except Exception as e:
            custom_log(f"Error in play phase timeout handler: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)

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
                # Cancel play phase timer before moving to next player
                self._cancel_play_phase_timer()
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
            # DO NOT move to next player if we're still processing special cards
            # The special cards window must complete first
            if self.game_state.phase == GamePhase.SPECIAL_PLAY_WINDOW:
                custom_log("WARNING: Attempted to move to next player while in SPECIAL_PLAY_WINDOW - skipping", level="WARNING", isOn=LOGGING_SWITCH)
                custom_log(f"Special card data length: {len(self.special_card_data) if self.special_card_data else 0}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"Special card players length: {len(self.special_card_players) if hasattr(self, 'special_card_players') else 0}", level="INFO", isOn=LOGGING_SWITCH)
                return
            
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
            
            # Check if the next player is a computer player and handle automatically
            next_player = self.game_state.players.get(next_player_id)
            if next_player and hasattr(next_player, 'player_type') and next_player.player_type.value == 'computer':
                custom_log(f"Computer player detected: {next_player_id} - triggering automatic turn processing", level="INFO", isOn=LOGGING_SWITCH)
                self._handle_computer_player_turn(next_player)
            else:
                # Send turn started event to human player
                self.start_turn()
            
        except Exception as e:
            pass
    
    def _handle_computer_player_turn(self, computer_player):
        """Handle automatic turn processing for computer players"""
        try:
            custom_log(f"=== COMPUTER TURN START === Player: {computer_player.player_id}, Hand size: {len(computer_player.hand)}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Initialize computer player factory if not already done
            if self._computer_player_factory is None:
                try:
                    config_path = "core/modules/recall_game/config/computer_player_config.yaml"
                    self._computer_player_factory = ComputerPlayerFactory.from_file(config_path)
                    custom_log("Computer player factory initialized with YAML config", level="INFO", isOn=LOGGING_SWITCH)
                except Exception as e:
                    custom_log(f"Failed to load computer player config, using default behavior: {e}", level="ERROR", isOn=LOGGING_SWITCH)
                    # Continue with default behavior if YAML loading fails
            
            # Check current status to determine what action to take
            current_status = computer_player.status.value if hasattr(computer_player.status, 'value') else str(computer_player.status)
            custom_log(f"Computer player {computer_player.player_id} current status: {current_status}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Only call start_turn if the player is in 'ready' or 'waiting' status
            # This prevents resetting the status after a successful draw
            if current_status in ['ready', 'waiting']:
                custom_log(f"Starting turn for computer player {computer_player.player_id}", level="INFO", isOn=LOGGING_SWITCH)
                self.start_turn()
            
            # Get computer player difficulty and current event
            difficulty = getattr(computer_player, 'difficulty', 'medium')
            current_event = self._get_current_computer_event(computer_player)
            
            custom_log(f"Computer player {computer_player.player_id} - Difficulty: {difficulty}, Event: {current_event}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Handle play_card event for computer players
            if current_event == 'play_card':
                custom_log(f"🎯 Computer player {computer_player.player_id} needs to play a card", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"🎯 Computer player {computer_player.player_id} current hand size: {len(computer_player.hand)}", level="INFO", isOn=LOGGING_SWITCH)
                
                # Get available cards from computer player's hand
                available_cards = [card.card_id for card in computer_player.hand if card is not None]
                custom_log(f"🎯 Computer player {computer_player.player_id} available cards: {available_cards}", level="INFO", isOn=LOGGING_SWITCH)
                
                if not available_cards:
                    custom_log(f"❌ Computer player {computer_player.player_id} has no cards to play - moving to next player", level="WARNING", isOn=LOGGING_SWITCH)
                    self._move_to_next_player()
                    return
                
                # Use YAML-based computer player factory for play card decision
                if self._computer_player_factory is not None:
                    custom_log(f"🎯 Getting play card decision for {computer_player.player_id}", level="INFO", isOn=LOGGING_SWITCH)
                    decision = self._computer_player_factory.get_play_card_decision(difficulty, self.game_state.to_dict(), available_cards)
                    custom_log(f"✅ Computer play card decision: {decision}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Execute the play card decision
                    custom_log(f"🎯 Executing play card decision for {computer_player.player_id}", level="INFO", isOn=LOGGING_SWITCH)
                    self._execute_computer_decision_yaml(decision, computer_player, 'play_card')
                else:
                    custom_log(f"❌ Computer player factory not available for play card decision", level="ERROR", isOn=LOGGING_SWITCH)
                    self._move_to_next_player()
                custom_log(f"🎯 Play card event handling complete for {computer_player.player_id}", level="INFO", isOn=LOGGING_SWITCH)
                return
            
            # Use YAML-based computer player factory for decision making
            if self._computer_player_factory is not None:
                custom_log(f"Calling _handle_computer_action_with_yaml for {computer_player.player_id}", level="INFO", isOn=LOGGING_SWITCH)
                self._handle_computer_action_with_yaml(computer_player, difficulty, current_event)
            else:
                # Fallback to original logic if YAML not available
                self._handle_computer_action(computer_player, difficulty, current_event)
            
            custom_log(f"=== COMPUTER TURN END === Player: {computer_player.player_id}, Hand size: {len(computer_player.hand)}", level="INFO", isOn=LOGGING_SWITCH)
            
        except Exception as e:
            custom_log(f"Error in _handle_computer_player_turn: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            # Fallback: move to next player if computer turn fails
            self._move_to_next_player()
    
    def _get_current_computer_event(self, computer_player):
        """Determine what event/action the computer player needs to perform"""
        try:
            player_status = computer_player.status.value if hasattr(computer_player.status, 'value') else str(computer_player.status)
            
            # Map player status to event names (same as frontend)
            if player_status == 'drawing_card':
                return 'draw_card'
            elif player_status == 'playing_card':
                return 'play_card'
            elif player_status == 'same_rank_window':
                return 'same_rank_play'
            elif player_status == 'jack_swap':
                return 'jack_swap'
            elif player_status == 'queen_peek':
                return 'queen_peek'
            else:
                custom_log(f"Unknown player status for event mapping: {player_status}", level="WARNING", isOn=LOGGING_SWITCH)
                return 'draw_card'  # Default to drawing a card
        except Exception as e:
            custom_log(f"Error getting current computer event: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return 'draw_card'
    
    def _handle_computer_action_with_yaml(self, computer_player, difficulty, event_name):
        """Handle computer action using YAML-based configuration"""
        try:
            custom_log(f"Handling computer action with YAML - Player: {computer_player.player_id}, Difficulty: {difficulty}, Event: {event_name}", level="INFO", isOn=LOGGING_SWITCH)
            
            if self._computer_player_factory is None:
                custom_log("Computer player factory not initialized", level="ERROR", isOn=LOGGING_SWITCH)
                self._move_to_next_player()
                return
            
            # Get decision from YAML-based factory
            game_state_dict = self._get_game_state_dict()
            decision = None
            
            if event_name == 'draw_card':
                decision = self._computer_player_factory.get_draw_card_decision(difficulty, game_state_dict)
            elif event_name == 'play_card':
                # Get available cards from computer player's hand
                available_cards = [card.card_id for card in computer_player.hand]
                decision = self._computer_player_factory.get_play_card_decision(difficulty, game_state_dict, available_cards)
            else:
                custom_log(f"Unknown event for computer action: {event_name}", level="WARNING", isOn=LOGGING_SWITCH)
                self._move_to_next_player()
                return
            
            custom_log(f"Computer decision: {decision}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Execute decision with delay from YAML config
            delay_seconds = decision.get('delay_seconds', 1.0)
            def delayed_execution():
                self._execute_computer_decision_yaml(decision, computer_player, event_name)
            
            timer = threading.Timer(delay_seconds, delayed_execution)
            timer.start()
            
        except Exception as e:
            custom_log(f"Error in _handle_computer_action_with_yaml: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            self._move_to_next_player()
    
    def _execute_computer_decision_yaml(self, decision, computer_player, event_name):
        """Execute computer player decision based on YAML configuration"""
        try:
            custom_log(f"Executing computer decision: {decision}", level="INFO", isOn=LOGGING_SWITCH)
            
            if event_name == 'draw_card':
                source = decision.get('source', 'deck')
                custom_log(f"Computer drawing from {source} pile", level="INFO", isOn=LOGGING_SWITCH)
                
                # Use existing _route_action logic (same as human players)
                action_data = {
                    'source': source,
                    'player_id': computer_player.player_id
                }
                success = self._route_action('draw_from_deck', computer_player.player_id, action_data)
                if not success:
                    custom_log(f"Computer player {computer_player.player_id} failed to draw card", level="ERROR", isOn=LOGGING_SWITCH)
                    self._move_to_next_player()
                # Note: After successful draw, _handle_draw_from_pile sets status to PLAYING_CARD
                # The next turn will detect this and handle play_card event
            
            elif event_name == 'play_card':
                card_id = decision.get('card_id')
                if card_id:
                    custom_log(f"Computer playing card: {card_id}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Use existing _route_action logic (same as human players)
                    action_data = {
                        'card_id': card_id,
                        'player_id': computer_player.player_id
                    }
                    success = self._route_action('play_card', computer_player.player_id, action_data)
                    if not success:
                        custom_log(f"Computer player {computer_player.player_id} failed to play card {card_id}", level="ERROR", isOn=LOGGING_SWITCH)
                        self._move_to_next_player()
                    else:
                        custom_log(f"Computer player {computer_player.player_id} successfully played card {card_id}", level="INFO", isOn=LOGGING_SWITCH)
                        # Note: Do NOT call _move_to_next_player() here - let the same rank window timer handle turn progression
                        # The _route_action already triggered _handle_same_rank_window which will handle the turn flow
                else:
                    custom_log(f"No card selected for computer play", level="WARNING", isOn=LOGGING_SWITCH)
                    self._move_to_next_player()
            
            else:
                custom_log(f"Unknown event for computer decision execution: {event_name}", level="WARNING", isOn=LOGGING_SWITCH)
                self._move_to_next_player()
            
        except Exception as e:
            custom_log(f"Error executing computer decision: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            self._move_to_next_player()
    
    def _get_game_state_dict(self):
        """Convert game state to dictionary for YAML factory"""
        try:
            return {
                'current_player_id': self.game_state.current_player_id,
                'phase': self.game_state.phase.value,
                'players': {pid: {
                    'id': player.player_id,
                    'name': player.name,
                    'status': player.status.value if hasattr(player.status, 'value') else str(player.status),
                    'hand': [card.card_id for card in player.hand if card is not None],
                    'points': getattr(player, 'points', 0)
                } for pid, player in self.game_state.players.items()},
                'discard_pile': [card.card_id for card in self.game_state.discard_pile if card is not None],
                'draw_pile_count': len(self.game_state.draw_pile)
            }
        except Exception as e:
            custom_log(f"Error converting game state to dict: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return {}

    def _handle_computer_action(self, computer_player, difficulty, event_name):
        """Handle computer action using declarative switch case approach"""
        try:
            custom_log(f"Handling computer action - Player: {computer_player.player_id}, Difficulty: {difficulty}, Event: {event_name}", level="INFO", isOn=LOGGING_SWITCH)
            
            # TODO: Load and parse declarative YAML configuration
            # The YAML will define:
            # - Decision trees for each event type
            # - Difficulty-based behavior variations
            # - Card selection strategies
            # - Special card usage patterns
            
            custom_log(f"Declarative YAML configuration will be implemented here", level="INFO", isOn=LOGGING_SWITCH)
            
            # Wire directly to existing action handlers - computers perform the same actions
            if event_name == 'draw_card':
                # TODO: Use YAML to determine draw source (deck vs discard)
                import threading
                def delayed_draw():
                    action_data = {
                        'source': 'deck',
                        'player_id': computer_player.player_id
                    }
                    success = self._route_action('draw_from_deck', computer_player.player_id, action_data)
                    if not success:
                        custom_log(f"Computer player {computer_player.player_id} failed to draw card", level="ERROR", isOn=LOGGING_SWITCH)
                        self._move_to_next_player()
                timer = threading.Timer(1.0, delayed_draw)  # 1 second delay
                timer.start()
                
            elif event_name == 'play_card':
                # TODO: Use YAML to determine which card to play
                import threading
                def delayed_play():
                    # TODO: Get card ID from YAML configuration
                    # For now, just move to next player (placeholder for card selection logic)
                    self._move_to_next_player()
                timer = threading.Timer(1.0, delayed_play)  # 1 second delay
                timer.start()
                
            elif event_name == 'same_rank_play':
                # TODO: Use YAML to determine same rank play decision
                import threading
                def delayed_same_rank():
                    # TODO: Get card ID from YAML configuration
                    # For now, just move to next player (placeholder for same rank logic)
                    self._move_to_next_player()
                timer = threading.Timer(1.0, delayed_same_rank)  # 1 second delay
                timer.start()
                
            elif event_name == 'jack_swap':
                # TODO: Use YAML to determine Jack swap targets
                import threading
                def delayed_jack_swap():
                    # TODO: Get swap targets from YAML configuration
                    # For now, just move to next player (placeholder for Jack swap logic)
                    self._move_to_next_player()
                timer = threading.Timer(1.0, delayed_jack_swap)  # 1 second delay
                timer.start()
                
            elif event_name == 'queen_peek':
                # TODO: Use YAML to determine Queen peek target
                import threading
                def delayed_queen_peek():
                    # TODO: Get peek target from YAML configuration
                    # For now, just move to next player (placeholder for Queen peek logic)
                    self._move_to_next_player()
                timer = threading.Timer(1.0, delayed_queen_peek)  # 1 second delay
                timer.start()
                
            else:
                custom_log(f"Unknown event for computer action: {event_name}", level="WARNING", isOn=LOGGING_SWITCH)
                self._move_to_next_player()
                
        except Exception as e:
            custom_log(f"Error in _handle_computer_action: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            self._move_to_next_player()
    
    def _execute_computer_decision(self, computer_player, decision):
        """Execute the computer player's decision"""
        try:
            action = decision.get('action')
            player_id = computer_player.player_id
            
            if action == 'call_recall':
                custom_log(f"Computer player {player_id} calling recall", level="INFO", isOn=LOGGING_SWITCH)
                # TODO: Implement call_recall logic - route to call_recall handler
                # For now, just move to next player
                self._move_to_next_player()
                
            elif action == 'play_card':
                card_index = decision.get('card_index', 0)
                custom_log(f"Computer player {player_id} playing card at index {card_index}", level="INFO", isOn=LOGGING_SWITCH)
                
                # Get the card from the computer player's hand
                if card_index < len(computer_player.hand):
                    card_to_play = computer_player.hand[card_index]
                    card_id = card_to_play.card_id
                    
                    # Simulate the play_card action
                    action_data = {
                        'card_id': card_id,
                        'player_id': player_id
                    }
                    
                    # Route to the play_card handler
                    success = self._route_action('play_card', player_id, action_data)
                    if success:
                        custom_log(f"Computer player {player_id} successfully played card {card_id}", level="INFO", isOn=LOGGING_SWITCH)
                    else:
                        custom_log(f"Computer player {player_id} failed to play card {card_id}", level="ERROR", isOn=LOGGING_SWITCH)
                        self._move_to_next_player()
                else:
                    custom_log(f"Computer player {player_id} invalid card index {card_index}", level="ERROR", isOn=LOGGING_SWITCH)
                    self._move_to_next_player()
            else:
                custom_log(f"Computer player {player_id} unknown action: {action}", level="WARNING", isOn=LOGGING_SWITCH)
                self._move_to_next_player()
                
        except Exception as e:
            custom_log(f"Error in _execute_computer_decision: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            self._move_to_next_player()
    
    
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
            # Get websocket_manager from app_manager (since we removed self.websocket_manager)
            websocket_manager = None
            if self.game_state.app_manager:
                websocket_manager = self.game_state.app_manager.get_websocket_manager()
            
            session_data = websocket_manager.get_session_data(session_id) if websocket_manager else {}
            return str(session_data.get('user_id') or data.get('user_id') or data.get('player_id') or session_id)
        except Exception as e:
            custom_log(f"Error in _extract_user_id: {e}", level="ERROR", isOn=LOGGING_SWITCH)
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
            elif action == 'draw_from_pile':
                # Handle both normal draws and collection draws from discard pile
                custom_log(f"=== PILE CONTENTS BEFORE DRAW ===", isOn=LOGGING_SWITCH)
                custom_log(f"Draw Pile Count: {len(self.game_state.draw_pile)}", isOn=LOGGING_SWITCH)
                custom_log(f"Draw Pile Top 3: {[card.card_id for card in self.game_state.draw_pile[:3]]}", isOn=LOGGING_SWITCH)
                custom_log(f"Discard Pile Count: {len(self.game_state.discard_pile)}", isOn=LOGGING_SWITCH)
                custom_log(f"Discard Pile Top 3: {[card.card_id for card in self.game_state.discard_pile[:3]]}", isOn=LOGGING_SWITCH)
                custom_log(f"=================================", isOn=LOGGING_SWITCH)
                return self._handle_draw_from_pile(user_id, action_data)
            elif action == 'play_card':
                custom_log(f"🎯 PLAY_CARD: Starting play_card action for {user_id}", level="INFO", isOn=LOGGING_SWITCH)
                play_result = self._handle_play_card(user_id, action_data)
                custom_log(f"🎯 PLAY_CARD: _handle_play_card result: {play_result}", level="INFO", isOn=LOGGING_SWITCH)
                if play_result:
                    # Only trigger same rank window if the play succeeded
                    # Note: _handle_play_card already calls _check_special_card internally
                    custom_log(f"🎯 PLAY_CARD: Play succeeded, calling _handle_same_rank_window for {user_id}", level="INFO", isOn=LOGGING_SWITCH)
                    same_rank_data = self._handle_same_rank_window(action_data)
                    custom_log(f"🎯 PLAY_CARD: _handle_same_rank_window result: {same_rank_data}", level="INFO", isOn=LOGGING_SWITCH)
                else:
                    # Play failed - restore player status to playing_card so they can retry
                    custom_log(f"🎯 PLAY_CARD: Play failed for {user_id}, restoring status", level="INFO", isOn=LOGGING_SWITCH)
                    player = self.game_state.players.get(user_id)
                    if player:
                        player.set_status(PlayerStatus.PLAYING_CARD)
                        custom_log(f"Play failed - restored player {user_id} status to PLAYING_CARD", level="INFO", isOn=LOGGING_SWITCH)
                        
                        # Manually trigger game state players update to ensure frontend gets the status change
                        if hasattr(self.game_state, '_track_change'):
                            self.game_state._track_change('players')
                            self.game_state._send_changes_if_needed()
                            custom_log(f"Manually triggered players state update after status restore", level="INFO", isOn=LOGGING_SWITCH)
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
            custom_log(f"Exception in _route_action: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            custom_log(f"Action: {action}, User: {user_id}", level="ERROR", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)
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
            
            return action_result
            
        except Exception as e:
            custom_log(f"Error in on_player_action: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            return False

    def _handle_same_rank_window(self, action_data: Dict[str, Any]) -> bool:
        """Handle same rank window action - sets all players to same_rank_window status"""
        try:
            custom_log("🔄 SAME_RANK: Starting same rank window - setting all players to SAME_RANK_WINDOW status", level="INFO", isOn=LOGGING_SWITCH)
            
            # Set game state phase to SAME_RANK_WINDOW
            self.game_state.phase = GamePhase.SAME_RANK_WINDOW
            custom_log("🔄 SAME_RANK: Set game phase to SAME_RANK_WINDOW", level="INFO", isOn=LOGGING_SWITCH)
            
            # Update all players' status to SAME_RANK_WINDOW efficiently (single game state update)
            updated_count = self.game_state.update_all_players_status(PlayerStatus.SAME_RANK_WINDOW, filter_active=True)
            custom_log(f"🔄 SAME_RANK: Updated {updated_count} players' status to SAME_RANK_WINDOW", level="INFO", isOn=LOGGING_SWITCH)
            
            # Set 5-second timer to automatically end same rank window
            self._start_same_rank_timer()
            custom_log("🔄 SAME_RANK: Started same rank timer", level="INFO", isOn=LOGGING_SWITCH)
            
            return True
            
        except Exception as e:
            custom_log(f"❌ SAME_RANK: Error in _handle_same_rank_window: {e}", level="ERROR", isOn=LOGGING_SWITCH)
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
                
                # Get the player and clear their cards_to_peek (Queen peek timer expired)
                player = self._get_player(player_id)
                if player and player.cards_to_peek:
                    player.clear_cards_to_peek()
                    custom_log(f"Cleared cards_to_peek for player {player_id} (Queen peek timer expired)", level="INFO", isOn=LOGGING_SWITCH)
                
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
                # COLLECTION DRAW from discard pile
                # Phase restrictions: cannot collect during same_rank_window or initial_peek
                if (self.game_state.phase == GamePhase.SAME_RANK_WINDOW or 
                    self.game_state.phase == GamePhase.INITIAL_PEEK):
                    phase_name = "same rank window" if self.game_state.phase == GamePhase.SAME_RANK_WINDOW else "initial peek"
                    custom_log(f"Cannot collect during {phase_name} phase", level="INFO", isOn=LOGGING_SWITCH)
                    
                    self._send_error_to_player(player_id, f'Cannot collect cards during {phase_name} phase')
                    return False
                
                # Get top card to check collection rank match
                top_discard_card = self.game_state.get_top_discard_card()
                if not top_discard_card:
                    custom_log(f"No cards in discard pile", level="INFO", isOn=LOGGING_SWITCH)
                    
                    self._send_error_to_player(player_id, 'Discard pile is empty')
                    return False
                
                # Validate collection rank match
                if top_discard_card.rank != player.collection_rank:
                    custom_log(
                        f"Card rank {top_discard_card.rank} doesn't match player collection rank {player.collection_rank}", 
                        level="INFO", 
                        isOn=LOGGING_SWITCH
                    )
                    
                    # Send error to player
                    self._send_error_to_player(
                        player_id,
                        'You can only collect cards from the discard pile that match your collection rank'
                    )
                    return False
                
                # SUCCESS - Draw from discard pile
                drawn_card = self.game_state.draw_from_discard_pile()
                if not drawn_card:
                    custom_log(f"Failed to remove card from discard pile", level="ERROR", isOn=LOGGING_SWITCH)
                    return False
                
                # Add to hand (NOT as drawn card)
                player.add_card_to_hand(drawn_card, is_drawn_card=False)
                
                # Add to collection_rank_cards
                player.collection_rank_cards.append(drawn_card)
                player.collection_rank = drawn_card.rank
                player._track_change('collection_rank_cards')
                player._track_change('collection_rank')
                player._send_changes_if_needed()
                
                # NO status change - player continues in current state
                # NO drawn_card property set
                custom_log(
                    f"Player {player_id} collected {drawn_card.rank} of {drawn_card.suit} from discard pile",
                    level="INFO",
                    isOn=LOGGING_SWITCH
                )
                
                # Log pile contents after successful collection
                custom_log(f"=== PILE CONTENTS AFTER COLLECTION ===", isOn=LOGGING_SWITCH)
                custom_log(f"Discard Pile Count: {self.game_state.get_discard_pile_count()}", isOn=LOGGING_SWITCH)
                custom_log(f"Collected Card: {drawn_card.card_id}", isOn=LOGGING_SWITCH)
                custom_log(f"======================================", isOn=LOGGING_SWITCH)
                
                return True
            
            # For deck draws: Add card to hand, set drawn_card property, and change status
            # Add card to player's hand (drawn cards always go to the end)
            custom_log(f"BEFORE add_card_to_hand: Player {player_id} hand size: {len(player.hand)}", level="INFO", isOn=LOGGING_SWITCH)
            player.add_card_to_hand(drawn_card, is_drawn_card=True)
            custom_log(f"AFTER add_card_to_hand: Player {player_id} hand size: {len(player.hand)}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Set the drawn card property
            player.set_drawn_card(drawn_card)
            
            # Change player status from DRAWING_CARD to PLAYING_CARD after successful draw
            player.set_status(PlayerStatus.PLAYING_CARD)
            custom_log(f"Player {player_id} status changed from DRAWING_CARD to PLAYING_CARD", level="INFO", isOn=LOGGING_SWITCH)
            
            # Check if this is a computer player and continue their turn
            if hasattr(player, 'player_type') and player.player_type.value == 'computer':
                custom_log(f"Computer player {player_id} drew card successfully, continuing with play_card action", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"Computer player {player_id} status before continuation: {player.status.value if hasattr(player.status, 'value') else str(player.status)}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"Computer player {player_id} hand size after draw: {len(player.hand)}", level="INFO", isOn=LOGGING_SWITCH)
                # Add a small delay to simulate thinking time
                import threading
                import time
                
                def continue_computer_turn():
                    time.sleep(0.5)  # 500ms delay
                    custom_log(f"🤖 CONTINUING computer turn for {player_id} after draw delay", level="INFO", isOn=LOGGING_SWITCH)
                    self._handle_computer_player_turn(player)
                
                # Start the continuation in a separate thread to avoid blocking
                continuation_thread = threading.Thread(target=continue_computer_turn)
                continuation_thread.daemon = True
                continuation_thread.start()
                custom_log(f"Computer player {player_id} continuation thread started", level="INFO", isOn=LOGGING_SWITCH)
            
            # Cancel draw phase timer and start play phase timer
            self._cancel_draw_phase_timer()
            self._start_play_phase_timer(player_id)
            
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
            custom_log(f"Error in _handle_draw_from_pile: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)
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
            
            # Check if card is in player's collection_rank_cards (cannot be played)
            for collection_card in player.collection_rank_cards:
                if hasattr(collection_card, 'card_id') and collection_card.card_id == card_id:
                    custom_log(f"Card {card_id} is a collection rank card and cannot be played by player {player_id}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Send error message to player
                    self._send_error_to_player(
                        player_id,
                        'This card is your collection rank and cannot be played. Choose another card.'
                    )
                    return False
            
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
            
            # Check if card is in player's collection_rank_cards (cannot be played for same rank)
            for collection_card in player.collection_rank_cards:
                if hasattr(collection_card, 'card_id') and collection_card.card_id == card_id:
                    custom_log(f"Card {card_id} is a collection rank card and cannot be played for same rank by player {user_id}", level="INFO", isOn=LOGGING_SWITCH)
                    
                    # Send error message to player
                    self._send_error_to_player(
                        user_id,
                        'This card is your collection rank and cannot be played for same rank. Choose another card.'
                    )
                    return False
            
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
            
            custom_log(f"🔍 SPECIAL_CARD: Checking special card for {player_id} - Card: {card_id}, Rank: {card_rank}, Suit: {card_suit}", level="INFO", isOn=LOGGING_SWITCH)
            
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

    def update_known_cards(self, event_type: str, acting_player_id: str, affected_card_ids: List[str], swap_data: Dict[str, str] = None):
        """Update all players' known_cards based on game events
        
        This method is called after any card play action to maintain accurate
        knowledge tracking for all players (both human and computer).
        
        Args:
            event_type: Type of event ('play_card', 'same_rank_play', 'jack_swap')
            acting_player_id: ID of the player who performed the action
            affected_card_ids: List of card IDs involved in the action
            swap_data: Optional dict for Jack swap with 'source_player_id' and 'target_player_id'
        """
        try:
            for player_id, player in self.game_state.players.items():
                difficulty = getattr(player, 'difficulty', 'medium')
                
                # Get remember probability based on difficulty
                remember_prob = self._get_remember_probability(difficulty)
                
                # Get player's known_cards
                known_cards = player.known_cards
                
                if event_type in ['play_card', 'same_rank_play']:
                    self._process_play_card_update(known_cards, affected_card_ids, remember_prob)
                elif event_type == 'jack_swap' and swap_data:
                    self._process_jack_swap_update(known_cards, affected_card_ids, swap_data, remember_prob)
                
                # Trigger state update for this player
                if hasattr(player, '_track_change'):
                    player._track_change('known_cards')
            
            custom_log(f"Updated known_cards for all players after {event_type}", level="INFO", isOn=LOGGING_SWITCH)
            
        except Exception as e:
            custom_log(f"Failed to update known_cards: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)

    def _get_remember_probability(self, difficulty: str) -> float:
        """Get remember probability based on difficulty"""
        difficulty_probs = {
            'easy': 0.70,
            'medium': 0.80,
            'hard': 0.90,
            'expert': 1.0
        }
        return difficulty_probs.get(difficulty.lower(), 0.80)

    def _process_play_card_update(self, known_cards: Dict[str, Any], affected_card_ids: List[str], remember_prob: float):
        """Process known_cards update for play_card or same_rank_play events"""
        import random
        if not affected_card_ids:
            return
        
        played_card_id = affected_card_ids[0]
        keys_to_remove = []
        
        # Iterate through each tracked player's cards
        for tracked_player_id, tracked_cards in list(known_cards.items()):
            if not isinstance(tracked_cards, dict):
                continue
            
            # Check card1
            card1 = tracked_cards.get('card1')
            card1_id = self._extract_card_id(card1)
            if card1_id == played_card_id:
                if random.random() <= remember_prob:
                    tracked_cards['card1'] = None
            
            # Check card2
            card2 = tracked_cards.get('card2')
            card2_id = self._extract_card_id(card2)
            if card2_id == played_card_id:
                if random.random() <= remember_prob:
                    tracked_cards['card2'] = None
            
            # If both cards are now None, mark for removal
            if tracked_cards.get('card1') is None and tracked_cards.get('card2') is None:
                keys_to_remove.append(tracked_player_id)
        
        # Remove empty entries
        for key in keys_to_remove:
            known_cards.pop(key, None)

    def _process_jack_swap_update(self, known_cards: Dict[str, Any], affected_card_ids: List[str], swap_data: Dict[str, str], remember_prob: float):
        """Process known_cards update for jack_swap event"""
        import random
        if len(affected_card_ids) < 2:
            return
        
        card_id1 = affected_card_ids[0]
        card_id2 = affected_card_ids[1]
        source_player_id = swap_data.get('source_player_id')
        target_player_id = swap_data.get('target_player_id')
        
        if not source_player_id or not target_player_id:
            return
        
        cards_to_move = {}
        keys_to_remove = []
        
        # Iterate through each tracked player's cards
        for tracked_player_id, tracked_cards in list(known_cards.items()):
            if not isinstance(tracked_cards, dict):
                continue
            
            # Check card1
            card1 = tracked_cards.get('card1')
            card1_id = self._extract_card_id(card1)
            if card1_id == card_id1 and tracked_player_id == source_player_id:
                if random.random() <= remember_prob:
                    cards_to_move[target_player_id] = {'card1': card1}
                    tracked_cards['card1'] = None
            elif card1_id == card_id2 and tracked_player_id == target_player_id:
                if random.random() <= remember_prob:
                    cards_to_move[source_player_id] = {'card1': card1}
                    tracked_cards['card1'] = None
            
            # Check card2
            card2 = tracked_cards.get('card2')
            card2_id = self._extract_card_id(card2)
            if card2_id == card_id1 and tracked_player_id == source_player_id:
                if random.random() <= remember_prob:
                    cards_to_move[target_player_id] = {'card2': card2}
                    tracked_cards['card2'] = None
            elif card2_id == card_id2 and tracked_player_id == target_player_id:
                if random.random() <= remember_prob:
                    cards_to_move[source_player_id] = {'card2': card2}
                    tracked_cards['card2'] = None
            
            # If both cards are now None, mark for removal
            if tracked_cards.get('card1') is None and tracked_cards.get('card2') is None:
                keys_to_remove.append(tracked_player_id)
        
        # Remove empty entries
        for key in keys_to_remove:
            known_cards.pop(key, None)
        
        # Add moved cards to new owners
        for new_owner_id, card_to_move in cards_to_move.items():
            if new_owner_id not in known_cards:
                known_cards[new_owner_id] = {'card1': None, 'card2': None}
            
            owner_cards = known_cards[new_owner_id]
            if owner_cards.get('card1') is None:
                owner_cards['card1'] = card_to_move.get('card1') or card_to_move.get('card2')
            elif owner_cards.get('card2') is None:
                owner_cards['card2'] = card_to_move.get('card1') or card_to_move.get('card2')

    def _extract_card_id(self, card: Any) -> Optional[str]:
        """Extract card ID from card object or string"""
        if card is None:
            return None
        if isinstance(card, str):
            return card
        if isinstance(card, dict):
            return card.get('cardId') or card.get('id')
        if hasattr(card, 'card_id'):
            return card.card_id
        return None

    