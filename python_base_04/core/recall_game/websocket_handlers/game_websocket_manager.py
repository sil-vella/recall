"""
Recall Game WebSocket Manager

This module provides WebSocket communication for the Recall game,
integrating with the existing WebSocket architecture through app_manager.
"""

from typing import Dict, Any, Optional, List
from flask_socketio import SocketIO, emit, join_room, leave_room
from ..models.game_state import GameState, GameStateManager
from ..models.player import HumanPlayer, ComputerPlayer
from ..game_logic.game_logic_engine import GameLogicEngine
from tools.logger.custom_logging import custom_log
import json
import time


class RecallGameWebSocketManager:
    """WebSocket manager for Recall game communication"""
    
    def __init__(self, app_manager=None):
        self.app_manager = app_manager
        self.websocket_manager = None
        self.game_state_manager = GameStateManager()
        self.game_logic_engine = GameLogicEngine()
        self.player_sessions = {}  # socket_id -> player_id
        self.game_sessions = {}    # game_id -> socket_ids
        self.active_games = {}     # game_id -> GameState
        
        # Initialize WebSocket manager from app_manager if available
        if app_manager:
            self.websocket_manager = app_manager.get_websocket_manager()
            self._register_game_handlers()
    
    def initialize(self, app_manager):
        """Initialize the WebSocket manager with app_manager"""
        self.app_manager = app_manager
        self.websocket_manager = app_manager.get_websocket_manager()
        self._register_game_handlers()
        custom_log("RecallGameWebSocketManager initialized with app_manager")
    
    def _register_game_handlers(self):
        """Register Recall game-specific WebSocket event handlers"""
        if not self.websocket_manager:
            custom_log("Warning: WebSocket manager not available")
            return
        
        # Register game-specific handlers with the existing WebSocket manager
        self.websocket_manager.register_handler('recall_join_game', self._handle_join_game)
        self.websocket_manager.register_handler('recall_leave_game', self._handle_leave_game)
        self.websocket_manager.register_handler('recall_player_action', self._handle_player_action)
        self.websocket_manager.register_handler('recall_call_recall', self._handle_call_recall)
        self.websocket_manager.register_handler('recall_play_out_of_turn', self._handle_play_out_of_turn)
        self.websocket_manager.register_handler('recall_use_special_power', self._handle_use_special_power)
        
        custom_log("Recall game WebSocket handlers registered")
    
    def _handle_join_game(self, data):
        """Handle player joining a game"""
        try:
            session_id = data.get('session_id')
            game_id = data.get('game_id')
            player_name = data.get('player_name', 'Anonymous')
            player_type = data.get('player_type', 'human')
            
            if not all([session_id, game_id]):
                self._emit_error(session_id, 'Game ID and session ID required')
                return False
            
            # Get or create game
            game_state = self.game_state_manager.get_game(game_id)
            if not game_state:
                game_state = GameState(game_id, max_players=4)
                self.game_state_manager.active_games[game_id] = game_state
            
            # Create player
            if player_type == 'human':
                player = HumanPlayer(f"player_{len(game_state.players)}", player_name)
            else:
                difficulty = data.get('difficulty', 'medium')
                player = ComputerPlayer(f"player_{len(game_state.players)}", player_name, difficulty)
            
            # Add player to game
            if game_state.add_player(player):
                self.player_sessions[session_id] = player.player_id
                
                # Join game room using existing WebSocket manager
                if self.websocket_manager:
                    self.websocket_manager.join_room(game_id, session_id, player.player_id)
                
                # Track game session
                if game_id not in self.game_sessions:
                    self.game_sessions[game_id] = []
                self.game_sessions[game_id].append(session_id)
                
                # Emit success
                self._emit_to_session(session_id, 'recall_game_joined', {
                    'game_id': game_id,
                    'player_id': player.player_id,
                    'player_name': player.name,
                    'game_state': game_state.to_dict()
                })
                
                # Broadcast to other players
                self._broadcast_to_game(game_id, 'recall_player_joined', {
                    'player_id': player.player_id,
                    'player_name': player.name,
                    'player_type': player.player_type.value
                }, exclude_session=session_id)
                
                # Start game if enough players
                if len(game_state.players) >= 2 and game_state.phase.value == "waiting_for_players":
                    self._start_game(game_id)
                
                custom_log(f"Player {player.player_id} joined game {game_id}")
                return True
            else:
                self._emit_error(session_id, 'Game is full')
                return False
        
        except Exception as e:
            custom_log(f"Error in _handle_join_game: {str(e)}", level="ERROR")
            self._emit_error(session_id, f'Error joining game: {str(e)}')
            return False
    
    def _handle_leave_game(self, data):
        """Handle player leaving a game"""
        try:
            session_id = data.get('session_id')
            game_id = data.get('game_id')
            player_id = self.player_sessions.get(session_id)
            
            if game_id and player_id:
                self._remove_player_from_game(game_id, player_id, session_id)
                self._emit_to_session(session_id, 'recall_game_left', {'game_id': game_id})
                return True
            else:
                self._emit_error(session_id, 'Invalid game or player data')
                return False
        
        except Exception as e:
            custom_log(f"Error in _handle_leave_game: {str(e)}", level="ERROR")
            self._emit_error(session_id, f'Error leaving game: {str(e)}')
            return False
    
    def _handle_player_action(self, data):
        """Handle player action through declarative rules"""
        try:
            session_id = data.get('session_id')
            game_id = data.get('game_id')
            action_type = data.get('action_type')
            card_id = data.get('card_id')
            
            player_id = self.player_sessions.get(session_id)
            
            if not all([game_id, action_type, player_id]):
                self._emit_error(session_id, 'Missing required data')
                return False
            
            game_state = self.game_state_manager.get_game(game_id)
            if not game_state:
                self._emit_error(session_id, 'Game not found')
                return False
            
            # Process action through declarative rules
            action_data = {
                'action_type': action_type,
                'player_id': player_id,
                'card_id': card_id,
                'game_id': game_id
            }
            
            result = self.game_logic_engine.process_player_action(game_state, action_data)
            
            if result.get('error'):
                self._emit_error(session_id, result.get('error'))
                return False
            else:
                # Update game state
                self._update_game_state(game_id, result)
                
                # Broadcast to all players in game
                self._broadcast_to_game(game_id, 'recall_game_update', {
                    'action_result': result,
                    'game_state': game_state.to_dict()
                })
                
                # Handle computer player turns
                self._handle_computer_turns(game_id)
                
                custom_log(f"Player action processed: {action_type} by {player_id}")
                return True
        
        except Exception as e:
            custom_log(f"Error in _handle_player_action: {str(e)}", level="ERROR")
            self._emit_error(session_id, f'Error processing action: {str(e)}')
            return False
    
    def _handle_call_recall(self, data):
        """Handle player calling Recall"""
        try:
            session_id = data.get('session_id')
            game_id = data.get('game_id')
            player_id = self.player_sessions.get(session_id)
            
            if not all([game_id, player_id]):
                self._emit_error(session_id, 'Missing required data')
                return False
            
            game_state = self.game_state_manager.get_game(game_id)
            if not game_state:
                self._emit_error(session_id, 'Game not found')
                return False
            
            result = game_state.call_recall(player_id)
            
            if result.get('error'):
                self._emit_error(session_id, result.get('error'))
                return False
            else:
                # Broadcast Recall call
                self._broadcast_to_game(game_id, 'recall_called', {
                    'player_id': player_id,
                    'game_state': game_state.to_dict()
                })
                
                # End game after Recall
                self._end_game(game_id)
                
                custom_log(f"Recall called by player {player_id}")
                return True
        
        except Exception as e:
            custom_log(f"Error in _handle_call_recall: {str(e)}", level="ERROR")
            self._emit_error(session_id, f'Error calling Recall: {str(e)}')
            return False
    
    def _handle_play_out_of_turn(self, data):
        """Handle out-of-turn card play"""
        try:
            session_id = data.get('session_id')
            game_id = data.get('game_id')
            card_id = data.get('card_id')
            player_id = self.player_sessions.get(session_id)
            
            if not all([game_id, card_id, player_id]):
                self._emit_error(session_id, 'Missing required data')
                return False
            
            game_state = self.game_state_manager.get_game(game_id)
            if not game_state:
                self._emit_error(session_id, 'Game not found')
                return False
            
            result = game_state.play_out_of_turn(player_id, card_id)
            
            if result.get('error'):
                self._emit_error(session_id, result.get('error'))
                return False
            else:
                # Broadcast out-of-turn play
                self._broadcast_to_game(game_id, 'recall_out_of_turn_play', {
                    'player_id': player_id,
                    'card_played': result.get('card_played'),
                    'game_state': game_state.to_dict()
                })
                
                custom_log(f"Out-of-turn play by player {player_id}")
                return True
        
        except Exception as e:
            custom_log(f"Error in _handle_play_out_of_turn: {str(e)}", level="ERROR")
            self._emit_error(session_id, f'Error playing out of turn: {str(e)}')
            return False
    
    def _handle_use_special_power(self, data):
        """Handle special power card usage"""
        try:
            session_id = data.get('session_id')
            game_id = data.get('game_id')
            power_type = data.get('power_type')
            target_data = data.get('target_data', {})
            player_id = self.player_sessions.get(session_id)
            
            if not all([game_id, power_type, player_id]):
                self._emit_error(session_id, 'Missing required data')
                return False
            
            game_state = self.game_state_manager.get_game(game_id)
            if not game_state:
                self._emit_error(session_id, 'Game not found')
                return False
            
            # Process special power
            result = self._process_special_power(game_state, player_id, power_type, target_data)
            
            if result.get('error'):
                self._emit_error(session_id, result.get('error'))
                return False
            else:
                # Broadcast special power usage
                self._broadcast_to_game(game_id, 'recall_special_power_used', {
                    'player_id': player_id,
                    'power_type': power_type,
                    'result': result,
                    'game_state': game_state.to_dict()
                })
                
                custom_log(f"Special power used by player {player_id}: {power_type}")
                return True
        
        except Exception as e:
            custom_log(f"Error in _handle_use_special_power: {str(e)}", level="ERROR")
            self._emit_error(session_id, f'Error using special power: {str(e)}')
            return False
    
    def _process_special_power(self, game_state: GameState, player_id: str, power_type: str, target_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process a special power card effect"""
        player = game_state.players.get(player_id)
        if not player:
            return {'error': 'Player not found'}
        
        if power_type == "peek_at_card":
            target_player_id = target_data.get('target_player_id')
            card_position = target_data.get('card_position')
            
            target_player = game_state.players.get(target_player_id)
            if not target_player or card_position >= len(target_player.hand):
                return {'error': 'Invalid target'}
            
            card = target_player.hand[card_position]
            return {
                'success': True,
                'card_revealed': card.to_dict(),
                'target_player_id': target_player_id
            }
        
        elif power_type == "switch_cards":
            card1_data = target_data.get('card1')
            card2_data = target_data.get('card2')
            
            # Implement card switching logic
            return {
                'success': True,
                'cards_switched': [card1_data, card2_data]
            }
        
        elif power_type == "steal_card":
            target_player_id = target_data.get('target_player_id')
            card_position = target_data.get('card_position')
            
            target_player = game_state.players.get(target_player_id)
            if not target_player or card_position >= len(target_player.hand):
                return {'error': 'Invalid target'}
            
            stolen_card = target_player.hand.pop(card_position)
            player.add_card_to_hand(stolen_card)
            
            return {
                'success': True,
                'card_stolen': stolen_card.to_dict(),
                'target_player_id': target_player_id
            }
        
        return {'error': 'Unknown power type'}
    
    def _start_game(self, game_id: str):
        """Start a game"""
        game_state = self.game_state_manager.get_game(game_id)
        if not game_state:
            return
        
        try:
            game_state.start_game()
            
            # Broadcast game start
            self._broadcast_to_game(game_id, 'recall_game_started', {
                'game_state': game_state.to_dict()
            })
            
            # Handle computer player turns
            self._handle_computer_turns(game_id)
            
            custom_log(f"Game {game_id} started")
        
        except Exception as e:
            custom_log(f"Error starting game {game_id}: {str(e)}", level="ERROR")
            self._broadcast_to_game(game_id, 'recall_error', {'message': f'Error starting game: {str(e)}'})
    
    def _end_game(self, game_id: str):
        """End a game and determine winner"""
        game_state = self.game_state_manager.get_game(game_id)
        if not game_state:
            return
        
        try:
            result = game_state.end_game()
            
            # Broadcast game end
            self._broadcast_to_game(game_id, 'recall_game_ended', {
                'winner': result.get('winner'),
                'final_scores': result.get('final_scores'),
                'game_state': game_state.to_dict()
            })
            
            custom_log(f"Game {game_id} ended, winner: {result.get('winner')}")
        
        except Exception as e:
            custom_log(f"Error ending game {game_id}: {str(e)}", level="ERROR")
            self._broadcast_to_game(game_id, 'recall_error', {'message': f'Error ending game: {str(e)}'})
    
    def _handle_computer_turns(self, game_id: str):
        """Handle computer player turns"""
        game_state = self.game_state_manager.get_game(game_id)
        if not game_state:
            return
        
        current_player = game_state.get_current_player()
        if not current_player or current_player.player_type.value != 'computer':
            return
        
        # Simulate computer player decision
        decision = current_player.make_decision(game_state.to_dict())
        
        if decision.get('action_type') == 'play_card':
            # Simulate card play
            card_id = decision.get('card_id')
            if card_id:
                action_data = {
                    'action_type': 'play_card',
                    'player_id': current_player.player_id,
                    'card_id': card_id,
                    'game_id': game_id
                }
                
                result = self.game_logic_engine.process_player_action(game_state, action_data)
                self._update_game_state(game_id, result)
                
                # Broadcast computer action
                self._broadcast_to_game(game_id, 'recall_computer_action', {
                    'player_id': current_player.player_id,
                    'action': decision,
                    'game_state': game_state.to_dict()
                })
        
        elif decision.get('action_type') == 'call_recall':
            # Computer calls Recall
            result = game_state.call_recall(current_player.player_id)
            
            self._broadcast_to_game(game_id, 'recall_computer_recall', {
                'player_id': current_player.player_id,
                'game_state': game_state.to_dict()
            })
            
            self._end_game(game_id)
    
    def _update_game_state(self, game_id: str, result: Dict[str, Any]):
        """Update game state based on action result"""
        game_state = self.game_state_manager.get_game(game_id)
        if not game_state:
            return
        
        # Apply effects from result
        effects = result.get('effects', [])
        for effect in effects:
            if effect.get('type') == 'next_player':
                game_state.next_player()
    
    def _remove_player_from_game(self, game_id: str, player_id: str, session_id: str):
        """Remove a player from a game"""
        game_state = self.game_state_manager.get_game(game_id)
        if game_state:
            game_state.remove_player(player_id)
            
            # Remove socket from game session
            if game_id in self.game_sessions and session_id in self.game_sessions[game_id]:
                self.game_sessions[game_id].remove(session_id)
            
            # Leave room using existing WebSocket manager
            if self.websocket_manager:
                self.websocket_manager.leave_room(game_id, session_id)
            
            # Broadcast player left
            self._broadcast_to_game(game_id, 'recall_player_left', {
                'player_id': player_id
            })
            
            custom_log(f"Player {player_id} left game {game_id}")
    
    def _emit_to_session(self, session_id: str, event: str, data: Dict[str, Any]):
        """Emit event to a specific session"""
        if self.websocket_manager:
            self.websocket_manager.send_to_session(session_id, event, data)
    
    def _emit_error(self, session_id: str, message: str):
        """Emit error to a specific session"""
        self._emit_to_session(session_id, 'recall_error', {'message': message})
    
    def _broadcast_to_game(self, game_id: str, event: str, data: Dict[str, Any], exclude_session: str = None):
        """Broadcast event to all players in a game"""
        if self.websocket_manager:
            # Get all sessions in the game room
            room_members = self.websocket_manager.get_room_members(game_id)
            
            for session_id in room_members:
                if session_id != exclude_session:
                    self.websocket_manager.send_to_session(session_id, event, data)
    
    def get_game_state(self, game_id: str) -> Optional[Dict[str, Any]]:
        """Get the current state of a game"""
        game_state = self.game_state_manager.get_game(game_id)
        return game_state.to_dict() if game_state else None
    
    def get_active_games(self) -> Dict[str, Any]:
        """Get all active games"""
        return {
            game_id: game_state.to_dict()
            for game_id, game_state in self.game_state_manager.get_all_games().items()
        }
    
    def cleanup_game(self, game_id: str):
        """Clean up a game and its resources"""
        try:
            # Remove game from state manager
            self.game_state_manager.remove_game(game_id)
            
            # Clean up sessions
            if game_id in self.game_sessions:
                for session_id in self.game_sessions[game_id]:
                    if session_id in self.player_sessions:
                        del self.player_sessions[session_id]
                del self.game_sessions[game_id]
            
            custom_log(f"Game {game_id} cleaned up")
        
        except Exception as e:
            custom_log(f"Error cleaning up game {game_id}: {str(e)}", level="ERROR") 