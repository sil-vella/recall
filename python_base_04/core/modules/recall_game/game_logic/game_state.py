"""
Game State Models for Recall Game

This module defines the game state management system for the Recall card game,
including game phases, state transitions, game logic, and WebSocket communication.
Consolidated from game_round.py and game_actions.py for simplicity.
"""

from typing import List, Dict, Any, Optional
from enum import Enum
from ..models.card import Card, CardDeck
from ..utils.deck_factory import DeckFactory
from ..models.player import Player, HumanPlayer, ComputerPlayer, PlayerType
from tools.logger.custom_logging import custom_log
from datetime import datetime
import time
import uuid


class GamePhase(Enum):
    """Game phases"""
    WAITING_FOR_PLAYERS = "waiting_for_players"
    DEALING_CARDS = "dealing_cards"
    PLAYER_TURN = "player_turn"
    OUT_OF_TURN_PLAY = "out_of_turn_play"
    RECALL_CALLED = "recall_called"
    GAME_ENDED = "game_ended"


class GameState:
    """Represents the current state of a Recall game"""
    
    def __init__(self, game_id: str, max_players: int = 4, min_players: int = 2, permission: str = 'public', app_manager=None):
        self.game_id = game_id
        self.max_players = max_players
        self.min_players = min_players
        self.permission = permission  # 'public' or 'private'
        self.app_manager = app_manager  # Reference to app manager for WebSocket access
        self.players = {}  # player_id -> Player
        self.current_player_id = None
        self.phase = GamePhase.WAITING_FOR_PLAYERS
        self.deck = CardDeck()
        self.discard_pile = []
        self.draw_pile = []
        self.pending_draws = {}  # player_id -> Card (drawn but not placed)
        self.out_of_turn_deadline = None  # timestamp until which out-of-turn is allowed
        self.out_of_turn_timeout_seconds = 5
        self.last_played_card = None
        self.recall_called_by = None
        self.game_start_time = None
        self.last_action_time = None
        self.game_ended = False
        self.winner = None
        self.game_history = []
        
        # Session tracking for individual player messaging
        self.player_sessions = {}  # player_id -> session_id
        self.session_players = {}  # session_id -> player_id
    
    def add_player(self, player: Player, session_id: str = None) -> bool:
        """Add a player to the game"""
        if len(self.players) >= self.max_players:
            return False
        
        self.players[player.player_id] = player
        
        # Track session mapping if session_id provided
        if session_id:
            self.player_sessions[player.player_id] = session_id
            self.session_players[session_id] = player.player_id
        
        return True
    
    def remove_player(self, player_id: str) -> bool:
        """Remove a player from the game"""
        if player_id in self.players:
            # Remove session mapping
            if player_id in self.player_sessions:
                session_id = self.player_sessions[player_id]
                del self.player_sessions[player_id]
                if session_id in self.session_players:
                    del self.session_players[session_id]
            
            del self.players[player_id]
            return True
        return False
    
    def get_player_session(self, player_id: str) -> Optional[str]:
        """Get session ID for a player"""
        return self.player_sessions.get(player_id)
    
    def get_session_player(self, session_id: str) -> Optional[str]:
        """Get player ID for a session"""
        return self.session_players.get(session_id)
    
    def update_player_session(self, player_id: str, session_id: str) -> bool:
        """Update session mapping for a player"""
        if player_id not in self.players:
            return False
        
        # Remove old mapping if exists
        if player_id in self.player_sessions:
            old_session_id = self.player_sessions[player_id]
            if old_session_id in self.session_players:
                del self.session_players[old_session_id]
        
        # Add new mapping
        self.player_sessions[player_id] = session_id
        self.session_players[session_id] = player_id
        return True
    
    def remove_session(self, session_id: str) -> Optional[str]:
        """Remove session mapping and return associated player_id"""
        if session_id in self.session_players:
            player_id = self.session_players[session_id]
            del self.session_players[session_id]
            if player_id in self.player_sessions:
                del self.player_sessions[player_id]
            return player_id
        return None
    

    
    def get_current_player(self) -> Optional[Player]:
        """Get the current player"""
        return self.players.get(self.current_player_id)
    

    
    def get_card_by_id(self, card_id: str) -> Optional[Card]:
        """Find a card by its ID anywhere in the game
        
        Searches through all game locations:
        - All player hands
        - Draw pile
        - Discard pile
        - Pending draws
        
        Args:
            card_id (str): The unique card ID to search for
            
        Returns:
            Optional[Card]: The card object if found, None otherwise
        """
        # Search in all player hands
        for player in self.players.values():
            for card in player.hand:
                if card.card_id == card_id:
                    return card
        
        # Search in draw pile
        for card in self.draw_pile:
            if card.card_id == card_id:
                return card
        
        # Search in discard pile
        for card in self.discard_pile:
            if card.card_id == card_id:
                return card
        
        # Search in pending draws
        for card in self.pending_draws.values():
            if card.card_id == card_id:
                return card
        
        # Card not found anywhere
        return None
    
    def find_card_location(self, card_id: str) -> Optional[Dict[str, Any]]:
        """Find a card and return its location information
        
        Args:
            card_id (str): The unique card ID to search for
            
        Returns:
            Optional[Dict[str, Any]]: Location info with keys:
                - 'card': The Card object
                - 'location_type': 'player_hand', 'draw_pile', 'discard_pile', 'pending_draw'
                - 'player_id': Player ID (if in player's possession)
                - 'index': Position in collection (if applicable)
        """
        # Search in all player hands
        for player_id, player in self.players.items():
            for index, card in enumerate(player.hand):
                if card.card_id == card_id:
                    return {
                        'card': card,
                        'location_type': 'player_hand',
                        'player_id': player_id,
                        'index': index
                    }
        
        # Search in draw pile
        for index, card in enumerate(self.draw_pile):
            if card.card_id == card_id:
                return {
                    'card': card,
                    'location_type': 'draw_pile',
                    'player_id': None,
                    'index': index
                }
        
        # Search in discard pile
        for index, card in enumerate(self.discard_pile):
            if card.card_id == card_id:
                return {
                    'card': card,
                    'location_type': 'discard_pile',
                    'player_id': None,
                    'index': index
                }
        
        # Search in pending draws
        for player_id, card in self.pending_draws.items():
            if card.card_id == card_id:
                return {
                    'card': card,
                    'location_type': 'pending_draw',
                    'player_id': player_id,
                    'index': None
                }
        
        # Card not found anywhere
        return None
    
    def get_actions(self):
        """Get the game actions handler"""
        from .game_actions import GameActions
        return GameActions(self)
    
    def get_round(self):
        """Get the game round handler"""
        from .game_round import GameRound
        return GameRound(self)
    



    

    
    def to_dict(self) -> Dict[str, Any]:
        """Convert game state to dictionary"""
        return {
            "game_id": self.game_id,
            "max_players": self.max_players,
            "players": {pid: player.to_dict() for pid, player in self.players.items()},
            "current_player_id": self.current_player_id,
            "phase": self.phase.value,
            "discard_pile": [card.to_dict() for card in self.discard_pile],
            "draw_pile_count": len(self.draw_pile),
            "last_played_card": self.last_played_card.to_dict() if self.last_played_card else None,
            "recall_called_by": self.recall_called_by,
            "game_start_time": self.game_start_time,
            "last_action_time": self.last_action_time,
            "game_ended": self.game_ended,
            "winner": self.winner,
            # Session tracking data
            "player_sessions": self.player_sessions,
            "session_players": self.session_players
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'GameState':
        """Create game state from dictionary"""
        game_state = cls(data["game_id"], data["max_players"])
        
        # Restore players
        for player_id, player_data in data.get("players", {}).items():
            if player_data["player_type"] == PlayerType.HUMAN.value:
                player = HumanPlayer.from_dict(player_data)
            else:
                player = ComputerPlayer.from_dict(player_data)
            game_state.players[player_id] = player
        
        game_state.current_player_id = data.get("current_player_id")
        game_state.phase = GamePhase(data.get("phase", "waiting_for_players"))
        game_state.recall_called_by = data.get("recall_called_by")
        game_state.game_start_time = data.get("game_start_time")
        game_state.last_action_time = data.get("last_action_time")
        game_state.game_ended = data.get("game_ended", False)
        game_state.winner = data.get("winner")
        
        # Restore session tracking data
        game_state.player_sessions = data.get("player_sessions", {})
        game_state.session_players = data.get("session_players", {})
        
        # Restore cards
        for card_data in data.get("discard_pile", []):
            card = Card.from_dict(card_data)
            game_state.discard_pile.append(card)
        
        if data.get("last_played_card"):
            game_state.last_played_card = Card.from_dict(data["last_played_card"])
        
        return game_state


# ========= GAME ROUND CLASS =========

class GameRound:
    """Manages a single round of gameplay in the Recall game"""
    
    def __init__(self, game_state: 'GameState'):
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

    def perform_action(self, player_id: str, action_type: str, action_data: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a specific game action"""
        try:
            custom_log(f"🎮 [GameRound] Executing action: {action_type} for player: {player_id}")
            
            if action_type == "play_card":
                card_id = action_data.get("card_id")
                if not card_id:
                    return {"error": "Missing card_id"}
                return self.game_state.get_actions().play_card(player_id, card_id)
            
            elif action_type == "play_out_of_turn":
                card_id = action_data.get("card_id")
                if not card_id:
                    return {"error": "Missing card_id"}
                return self.game_state.get_actions().play_out_of_turn(player_id, card_id)
            
            elif action_type == "draw_from_deck":
                return self.game_state.get_actions().draw_from_deck(player_id)
            
            elif action_type == "take_from_discard":
                return self.game_state.get_actions().take_from_discard(player_id)
            
            elif action_type == "place_drawn_card_replace":
                replace_card_id = action_data.get("replace_card_id")
                if not replace_card_id:
                    return {"error": "Missing replace_card_id"}
                return self.game_state.get_actions().place_drawn_card_replace(player_id, replace_card_id)
            
            elif action_type == "place_drawn_card_play":
                return self.game_state.get_actions().place_drawn_card_play(player_id)
            
            elif action_type == "initial_peek":
                indices = action_data.get("indices", [])
                if not indices:
                    return {"error": "Missing indices"}
                return self.game_state.get_actions().initial_peek(player_id, indices)
            
            elif action_type == "call_recall":
                return self.game_state.get_actions().call_recall(player_id)
            
            elif action_type == "end_game":
                return self.game_state.get_actions().end_game()
            
            else:
                return {"error": f"Unknown action type: {action_type}"}
                
        except Exception as e:
            custom_log(f"❌ [GameRound] Error executing action {action_type}: {e}", level="ERROR")
            return {"error": f"Action execution failed: {str(e)}"}

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

    def get_timed_rounds_status(self) -> Dict[str, Any]:
        """Get status of timed rounds"""
        return {
            "enabled": self.timed_rounds_enabled,
            "time_limit": self.round_time_limit_seconds,
            "time_remaining": self.round_time_remaining,
            "round_status": self.round_status
        }


# ========= GAME ACTIONS CLASS =========

class GameActions:
    """Handles all game actions and logic during gameplay"""
    
    def __init__(self, game_state: GameState):
        self.game_state = game_state
    
    def end_game(self) -> Dict[str, Any]:
        """End the game and determine winner"""
        # Allow scoring at recall or immediate end
        if self.game_state.phase not in (GamePhase.RECALL_CALLED, GamePhase.GAME_ENDED, GamePhase.PLAYER_TURN, GamePhase.OUT_OF_TURN_PLAY):
            return {"error": "Invalid phase for ending game"}
        return self._end_game_with_scoring()

    def start_game(self) -> Dict[str, Any]:
        """Start the game and deal cards"""
        # Check if we have enough players, add computer players if needed
        current_players = len(self.game_state.players)
        min_players = self.game_state.min_players
        
        if current_players < min_players:
            # Add computer players to reach minimum
            players_needed = min_players - current_players
            custom_log(f"🎮 Adding {players_needed} computer player(s) to reach minimum of {min_players}")
            
            for i in range(players_needed):
                computer_id = f"computer_{self.game_state.game_id}_{i}"
                computer_name = f"Computer_{i+1}"
                from ..models.player import ComputerPlayer
                computer_player = ComputerPlayer(computer_id, computer_name, difficulty="medium")
                self.game_state.add_player(computer_player)
                custom_log(f"✅ Added computer player: {computer_name} (ID: {computer_id})")
        
        self.game_state.phase = GamePhase.DEALING_CARDS
        self.game_state.game_start_time = time.time()
        
        # Build deterministic deck from factory, then deal
        from ..utils.deck_factory import DeckFactory
        factory = DeckFactory(self.game_state.game_id)
        self.game_state.deck.cards = factory.build_deck(
            include_jokers=True,  # Standard deck cards (including jokers, queens, jacks, kings)
        )
        self._deal_cards()
        
        # Set up draw and discard piles
        self._setup_piles()
        
        # Set first player and update player statuses
        player_ids = list(self.game_state.players.keys())
        self.game_state.current_player_id = player_ids[0]
        
        # Update player statuses
        for player_id, player in self.game_state.players.items():
            if player_id == self.game_state.current_player_id:
                player.set_drawing_card()  # Current player needs to draw a card first
            else:
                player.set_ready()    # Other players are ready
        
        self.game_state.phase = GamePhase.PLAYER_TURN
        self.game_state.last_action_time = time.time()
        
        return {
            "success": True,
            "game_started": True,
            "current_player": self.game_state.current_player_id,
            "phase": self.game_state.phase.value
        }

    def draw_from_deck(self, player_id: str) -> Dict[str, Any]:
        """Draw a card from the deck"""
        try:
            custom_log(f"🎮 [GameActions] Player {player_id} drawing from deck")
            
            # Check if it's the player's turn
            if self.game_state.current_player_id != player_id:
                return {"error": "Not your turn"}
            
            # Check if player is in drawing state
            player = self.game_state.players.get(player_id)
            if not player or player.status != PlayerStatus.DRAWING_CARD:
                return {"error": "Player not in drawing state"}
            
            # Check if draw pile has cards
            if not self.game_state.draw_pile:
                return {"error": "Draw pile is empty"}
            
            # Draw the top card
            drawn_card = self.game_state.draw_pile.pop(0)
            drawn_card.owner_id = player_id
            
            # Add to player's pending draws
            self.game_state.pending_draws[player_id] = drawn_card
            
            # Update player status to playing card
            player.set_playing_card()
            
            # Update game state
            self.game_state.last_action_time = time.time()
            
            custom_log(f"✅ Player {player_id} drew card: {drawn_card}")
            
            return {
                "success": True,
                "drawn_card": drawn_card.to_dict(),
                "player_status": player.status.value,
                "draw_pile_count": len(self.game_state.draw_pile)
            }
            
        except Exception as e:
            custom_log(f"❌ [GameActions] Error drawing from deck: {e}", level="ERROR")
            return {"error": f"Draw failed: {str(e)}"}

    def take_from_discard(self, player_id: str) -> Dict[str, Any]:
        """Take the top card from the discard pile"""
        try:
            custom_log(f"🎮 [GameActions] Player {player_id} taking from discard")
            
            # Check if it's the player's turn
            if self.game_state.current_player_id != player_id:
                return {"error": "Not your turn"}
            
            # Check if player is in drawing state
            player = self.game_state.players.get(player_id)
            if not player or player.status != PlayerStatus.DRAWING_CARD:
                return {"error": "Player not in drawing state"}
            
            # Check if discard pile has cards
            if not self.game_state.discard_pile:
                return {"error": "Discard pile is empty"}
            
            # Take the top card
            top_card = self.game_state.discard_pile.pop()
            top_card.owner_id = player_id
            
            # Add to player's pending draws
            self.game_state.pending_draws[player_id] = top_card
            
            # Update player status to playing card
            player.set_playing_card()
            
            # Update game state
            self.game_state.last_action_time = time.time()
            
            custom_log(f"✅ Player {player_id} took card from discard: {top_card}")
            
            return {
                "success": True,
                "taken_card": top_card.to_dict(),
                "player_status": player.status.value,
                "discard_pile_count": len(self.game_state.discard_pile)
            }
            
        except Exception as e:
            custom_log(f"❌ [GameActions] Error taking from discard: {e}", level="ERROR")
            return {"error": f"Take from discard failed: {str(e)}"}

    def play_card(self, player_id: str, card_id: str) -> Dict[str, Any]:
        """Play a card from the player's hand"""
        try:
            custom_log(f"🎮 [GameActions] Player {player_id} playing card: {card_id}")
            
            # Check if it's the player's turn
            if self.game_state.current_player_id != player_id:
                return {"error": "Not your turn"}
            
            # Check if player is in playing state
            player = self.game_state.players.get(player_id)
            if not player or player.status != PlayerStatus.PLAYING_CARD:
                return {"error": "Player not in playing state"}
            
            # Find the card in player's hand
            card = None
            card_index = None
            for i, c in enumerate(player.hand):
                if c.card_id == card_id:
                    card = c
                    card_index = i
                    break
            
            if not card:
                return {"error": "Card not found in hand"}
            
            # Remove card from hand
            player.hand.pop(card_index)
            
            # Add to discard pile
            self.game_state.discard_pile.append(card)
            
            # Update last played card
            self.game_state.last_played_card = card
            
            # Update game state
            self.game_state.last_action_time = time.time()
            
            # Move to next player's turn
            self._next_player_turn()
            
            custom_log(f"✅ Player {player_id} played card: {card}")
            
            return {
                "success": True,
                "played_card": card.to_dict(),
                "next_player": self.game_state.current_player_id,
                "discard_pile_count": len(self.game_state.discard_pile)
            }
            
        except Exception as e:
            custom_log(f"❌ [GameActions] Error playing card: {e}", level="ERROR")
            return {"error": f"Play card failed: {str(e)}"}

    def play_out_of_turn(self, player_id: str, card_id: str) -> Dict[str, Any]:
        """Play a card out of turn (same rank)"""
        try:
            custom_log(f"🎮 [GameActions] Player {player_id} playing out of turn: {card_id}")
            
            # Check if out-of-turn play is allowed
            if not self.game_state.out_of_turn_deadline or time.time() > self.game_state.out_of_turn_deadline:
                return {"error": "Out-of-turn play not allowed"}
            
            # Check if player has the card
            player = self.game_state.players.get(player_id)
            if not player:
                return {"error": "Player not found"}
            
            # Find the card in player's hand
            card = None
            card_index = None
            for i, c in enumerate(player.hand):
                if c.card_id == card_id:
                    card = c
                    card_index = i
                    break
            
            if not card:
                return {"error": "Card not found in hand"}
            
            # Check if card has same rank as last played card
            if not self.game_state.last_played_card or card.rank != self.game_state.last_played_card.rank:
                return {"error": "Card must have same rank for out-of-turn play"}
            
            # Remove card from hand
            player.hand.pop(card_index)
            
            # Add to discard pile
            self.game_state.discard_pile.append(card)
            
            # Update last played card
            self.game_state.last_played_card = card
            
            # Update game state
            self.game_state.last_action_time = time.time()
            
            # Move to next player's turn
            self._next_player_turn()
            
            custom_log(f"✅ Player {player_id} played out of turn: {card}")
            
            return {
                "success": True,
                "played_card": card.to_dict(),
                "next_player": self.game_state.current_player_id,
                "discard_pile_count": len(self.game_state.discard_pile)
            }
            
        except Exception as e:
            custom_log(f"❌ [GameActions] Error playing out of turn: {e}", level="ERROR")
            return {"error": f"Out-of-turn play failed: {str(e)}"}

    def place_drawn_card_replace(self, player_id: str, replace_card_id: str) -> Dict[str, Any]:
        """Place drawn card by replacing one in hand"""
        try:
            custom_log(f"🎮 [GameActions] Player {player_id} replacing card: {replace_card_id}")
            
            # Check if player has a pending draw
            if player_id not in self.game_state.pending_draws:
                return {"error": "No pending draw to place"}
            
            # Get the drawn card
            drawn_card = self.game_state.pending_draws[player_id]
            
            # Find the card to replace in player's hand
            player = self.game_state.players.get(player_id)
            if not player:
                return {"error": "Player not found"}
            
            card_index = None
            for i, c in enumerate(player.hand):
                if c.card_id == replace_card_id:
                    card_index = i
                    break
            
            if card_index is None:
                return {"error": "Card to replace not found in hand"}
            
            # Replace the card
            old_card = player.hand[card_index]
            player.hand[card_index] = drawn_card
            
            # Add old card to discard pile
            self.game_state.discard_pile.append(old_card)
            
            # Remove from pending draws
            del self.game_state.pending_draws[player_id]
            
            # Update game state
            self.game_state.last_action_time = time.time()
            
            # Move to next player's turn
            self._next_player_turn()
            
            custom_log(f"✅ Player {player_id} replaced card: {old_card} with drawn card: {drawn_card}")
            
            return {
                "success": True,
                "replaced_card": old_card.to_dict(),
                "drawn_card": drawn_card.to_dict(),
                "next_player": self.game_state.current_player_id
            }
            
        except Exception as e:
            custom_log(f"❌ [GameActions] Error replacing card: {e}", level="ERROR")
            return {"error": f"Replace card failed: {str(e)}"}

    def place_drawn_card_play(self, player_id: str) -> Dict[str, Any]:
        """Place drawn card by playing it directly"""
        try:
            custom_log(f"🎮 [GameActions] Player {player_id} playing drawn card")
            
            # Check if player has a pending draw
            if player_id not in self.game_state.pending_draws:
                return {"error": "No pending draw to place"}
            
            # Get the drawn card
            drawn_card = self.game_state.pending_draws[player_id]
            
            # Add to discard pile
            self.game_state.discard_pile.append(drawn_card)
            
            # Update last played card
            self.game_state.last_played_card = drawn_card
            
            # Remove from pending draws
            del self.game_state.pending_draws[player_id]
            
            # Update game state
            self.game_state.last_action_time = time.time()
            
            # Move to next player's turn
            self._next_player_turn()
            
            custom_log(f"✅ Player {player_id} played drawn card: {drawn_card}")
            
            return {
                "success": True,
                "played_card": drawn_card.to_dict(),
                "next_player": self.game_state.current_player_id,
                "discard_pile_count": len(self.game_state.discard_pile)
            }
            
        except Exception as e:
            custom_log(f"❌ [GameActions] Error playing drawn card: {e}", level="ERROR")
            return {"error": f"Play drawn card failed: {str(e)}"}

    def initial_peek(self, player_id: str, indices: List[int]) -> Dict[str, Any]:
        """Allow player to peek at initial cards"""
        try:
            custom_log(f"🎮 [GameActions] Player {player_id} peeking at indices: {indices}")
            
            # Check if player is in waiting state
            player = self.game_state.players.get(player_id)
            if not player or player.status != PlayerStatus.WAITING:
                return {"error": "Player not in waiting state"}
            
            # Check if player has peeks remaining
            if player.initial_peeks_remaining <= 0:
                return {"error": "No peeks remaining"}
            
            # Validate indices
            if not indices or len(indices) > 2 or any(i < 0 or i >= len(player.hand) for i in indices):
                return {"error": "Invalid indices for peeking"}
            
            # Peek at the cards
            peeked_cards = []
            for index in indices:
                card = player.hand[index]
                card.is_visible = True
                if card not in player.visible_cards:
                    player.visible_cards.append(card)
                peeked_cards.append(card.to_dict())
            
            # Decrease peeks remaining
            player.initial_peeks_remaining -= 1
            
            custom_log(f"✅ Player {player_id} peeked at {len(peeked_cards)} cards")
            
            return {
                "success": True,
                "peeked_cards": peeked_cards,
                "peeks_remaining": player.initial_peeks_remaining
            }
            
        except Exception as e:
            custom_log(f"❌ [GameActions] Error peeking: {e}", level="ERROR")
            return {"error": f"Peek failed: {str(e)}"}

    def call_recall(self, player_id: str) -> Dict[str, Any]:
        """Call recall to end the game"""
        try:
            custom_log(f"🎮 [GameActions] Player {player_id} calling recall")
            
            # Check if it's the player's turn
            if self.game_state.current_player_id != player_id:
                return {"error": "Not your turn"}
            
            # Check if player is in playing state
            player = self.game_state.players.get(player_id)
            if not player or player.status != PlayerStatus.PLAYING_CARD:
                return {"error": "Player not in playing state"}
            
            # Set recall called
            self.game_state.recall_called_by = player_id
            player.has_called_recall = True
            
            # Change game phase
            self.game_state.phase = GamePhase.RECALL_CALLED
            
            # Update game state
            self.game_state.last_action_time = time.time()
            
            custom_log(f"✅ Player {player_id} called recall")
            
            return {
                "success": True,
                "recall_called_by": player_id,
                "game_phase": self.game_state.phase.value
            }
            
        except Exception as e:
            custom_log(f"❌ [GameActions] Error calling recall: {e}", level="ERROR")
            return {"error": f"Call recall failed: {str(e)}"}

    def _end_game_with_scoring(self) -> Dict[str, Any]:
        """End the game and calculate final scores"""
        try:
            custom_log(f"🎮 [GameActions] Ending game with scoring")
            
            # Calculate scores for all players
            scores = {}
            for player_id, player in self.game_state.players.items():
                score = player.calculate_points()
                scores[player_id] = score
            
            # Find winner (lowest score, then fewest cards)
            winner_id = min(scores.keys(), key=lambda pid: (scores[pid], len(self.game_state.players[pid].hand)))
            
            # Update game state
            self.game_state.winner = winner_id
            self.game_state.phase = GamePhase.GAME_ENDED
            self.game_state.game_ended = True
            self.game_state.last_action_time = time.time()
            
            custom_log(f"✅ Game ended. Winner: {winner_id} with score: {scores[winner_id]}")
            
            return {
                "success": True,
                "game_ended": True,
                "winner": winner_id,
                "scores": scores,
                "final_phase": self.game_state.phase.value
            }
            
        except Exception as e:
            custom_log(f"❌ [GameActions] Error ending game: {e}", level="ERROR")
            return {"error": f"End game failed: {str(e)}"}

    # ========= Private Helper Methods =========
    
    def _deal_cards(self):
        """Deal 4 cards to each player"""
        for player in self.game_state.players.values():
            for _ in range(4):
                card = self.game_state.deck.draw_card()
                if card:
                    player.add_card_to_hand(card)
    
    def _setup_piles(self):
        """Set up draw and discard piles"""
        # Move remaining cards to draw pile
        self.game_state.draw_pile = self.game_state.deck.cards.copy()
        self.game_state.deck.cards = []
        
        # Start discard pile with first card from draw pile
        if self.game_state.draw_pile:
            first_card = self.game_state.draw_pile.pop(0)
            self.game_state.discard_pile.append(first_card)
    
    def _next_player_turn(self):
        """Move to the next player's turn"""
        player_ids = list(self.game_state.players.keys())
        if not player_ids:
            return
        
        current_index = player_ids.index(self.game_state.current_player_id)
        next_index = (current_index + 1) % len(player_ids)
        next_player_id = player_ids[next_index]
        
        # Update current player
        self.game_state.current_player_id = next_player_id
        
        # Update player statuses
        for player_id, player in self.game_state.players.items():
            if player_id == next_player_id:
                player.set_drawing_card()  # Next player needs to draw
            else:
                player.set_ready()  # Other players are ready
        
        custom_log(f"🔄 Turn moved to player: {next_player_id}")


class GameStateManager:
    """Manages multiple game states with integrated WebSocket communication"""
    
    def __init__(self):
        self.active_games = {}  # game_id -> GameState
        self.app_manager = None
        self.websocket_manager = None
        self.game_logic_engine = None
        self._initialized = False
    
    def initialize(self, app_manager, game_logic_engine) -> bool:
        """Initialize with WebSocket and game engine support"""
        try:
            self.app_manager = app_manager
            self.websocket_manager = app_manager.get_websocket_manager()
            self.game_logic_engine = game_logic_engine
            if not self.websocket_manager:
                custom_log("❌ WebSocket manager not available for GameStateManager", level="ERROR")
                return False
            
            # Register hook callbacks for automatic game creation
            self._register_hook_callbacks()
            
            self._initialized = True
            custom_log("✅ GameStateManager initialized with WebSocket support")
            return True
        except Exception as e:
            custom_log(f"❌ Failed to initialize GameStateManager: {e}", level="ERROR")
            return False
    
    def create_game(self, max_players: int = 4, min_players: int = 2, permission: str = 'public') -> str:
        """Create a new game"""
        game_id = str(uuid.uuid4())
        game_state = GameState(game_id, max_players, min_players, permission, self.app_manager)
        self.active_games[game_id] = game_state
        return game_id
    
    def create_game_with_id(self, game_id: str, max_players: int = 4, min_players: int = 2, permission: str = 'public') -> str:
        """Create a new game using a provided identifier (e.g., room_id).

        This aligns backend game identity with the room identifier used by the
        frontend so join/start flows can address the same id across the stack.
        If a game with this id already exists, it is returned unchanged.
        """
        # If already exists, no-op
        existing = self.active_games.get(game_id)
        if existing is not None:
            return game_id
        game_state = GameState(game_id, max_players, min_players, permission, self.app_manager)
        self.active_games[game_id] = game_state
        return game_id
    
    def get_game(self, game_id: str) -> Optional[GameState]:
        """Get a game by ID"""
        return self.active_games.get(game_id)
    
    def remove_game(self, game_id: str) -> bool:
        """Remove a game"""
        if game_id in self.active_games:
            del self.active_games[game_id]
            return True
        return False
    
    def get_all_games(self) -> Dict[str, GameState]:
        """Get all active games"""
        return self.active_games.copy()
    
    def get_available_games(self) -> List[Dict[str, Any]]:
        """Get all public games that are in the waiting for players phase and can be joined"""
        available_games = []
        total_games = len(self.active_games)
        public_games = 0
        private_games = 0
        
        for game_id, game in self.active_games.items():
            # Log game details for debugging
            custom_log(f"🎮 [DEBUG] Game {game_id}: phase={game.phase.value}, permission={game.permission}, players={len(game.players)}")
            
            # Only include PUBLIC games that are waiting for players
            if game.phase == GamePhase.WAITING_FOR_PLAYERS and game.permission == 'public':
                # Convert to Flutter-compatible format
                game_data = self._to_flutter_game_state(game)
                available_games.append(game_data)
                public_games += 1
            elif game.permission == 'private':
                private_games += 1
        
        custom_log(f"🎮 Found {len(available_games)} available PUBLIC games out of {total_games} total games ({public_games} public, {private_games} private)")
        return available_games
    
    # ========= WebSocket Event Handlers =========
    
    def on_join_game(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle player joining a game (now simplified since games are auto-created via hooks)"""
        try:
            game_id = data.get('game_id')
            player_name = data.get('player_name') or 'Player'
            player_type = data.get('player_type') or 'human'

            # Game should already exist (created via room_created hook)
            game = self.get_game(game_id)
            if not game:
                self._send_error(session_id, f'Game not found: {game_id} - games are auto-created when rooms are created')
                return False

            # Join the room (game and room have same ID)
            self.websocket_manager.join_room(game_id, session_id)

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)

            # Add player if not exists
            if user_id not in game.players:
                player = ComputerPlayer(user_id, player_name) if player_type == 'computer' else HumanPlayer(user_id, player_name)
                game.add_player(player, session_id)
                custom_log(f"✅ Added player {user_id} to game {game_id}")
            else:
                game.update_player_session(user_id, session_id)
                custom_log(f"✅ Updated session for player {user_id} in game {game_id}")

            # Broadcast join event
            payload = {
                'event_type': 'game_joined',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
                'player': self._to_flutter_player(game.players[user_id], user_id == game.current_player_id),
            }
            self._broadcast_event(game_id, payload)
            return True
        except Exception as e:
            custom_log(f"Error in on_join_game: {e}", level="ERROR")
            self._send_error(session_id, f'Join game failed: {str(e)}')
            return False

    def on_player_action(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle player actions through the game round"""
        try:
            game_id = data.get('game_id') or data.get('room_id')
            action = data.get('action') or data.get('action_type')
            if not game_id or not action:
                self._send_error(session_id, 'Missing game_id or action')
                return False
                
            game = self.get_game(game_id)
            if not game:
                self._send_error(session_id, f'Game not found: {game_id}')
                return False

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or data.get('player_id') or session_id)

            # Get the game round handler
            game_round = game.get_round()
            
            # Build action data for the round
            action_data = {
                'card_id': (data.get('card') or {}).get('card_id') or (data.get('card') or {}).get('id'),
                'replace_card_id': (data.get('replace_card') or {}).get('card_id') or data.get('replace_card_id'),
                'replace_index': data.get('replaceIndex'),
                'power_data': data.get('power_data'),
                'indices': data.get('indices', []),
            }

            # Process action through game round
            round_result = game_round.perform_action(user_id, action, action_data)

            if round_result.get('error'):
                self._send_action_result(game_id, user_id, round_result)
                return False
            
            # Send results and updates
            self._send_action_result(game_id, user_id, round_result)
            self._broadcast_game_action(game_id, action, {'action_type': action, 'player_id': user_id, 'result': round_result}, user_id)
            self._send_game_state_update(game_id)
            
            # If round ended, send round completion event
            if round_result.get('round_ended'):
                self._send_round_completion_event(game_id, round_result)
            
            return True
        except Exception as e:
            custom_log(f"Error in on_player_action: {e}", level="ERROR")
            self._send_error(session_id, f'Player action failed: {str(e)}')
            return False

    def on_start_match(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle game start through the game round"""
        try:
            custom_log(f"🎮 [START_MATCH] Starting match for session: {session_id}, data: {data}")
            
            game_id = data.get('game_id') or data.get('room_id')
            if not game_id:
                custom_log(f"❌ [START_MATCH] Missing game_id in data: {data}")
                self._send_error(session_id, 'Missing game_id')
                return False
            
            custom_log(f"🎮 [START_MATCH] Looking for game: {game_id}")
            game = self.get_game(game_id)
            if not game:
                custom_log(f"❌ [START_MATCH] Game not found: {game_id}")
                self._send_error(session_id, f'Game not found: {game_id}')
                return False

            custom_log(f"✅ [START_MATCH] Game found: {game_id}")
            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            custom_log(f"🎮 [START_MATCH] User ID: {user_id}")
            
            # First, start the game (deal cards, set up deck, etc.)
            custom_log(f"🎮 [START_MATCH] Getting game actions...")
            game_actions = game.get_actions()
            custom_log(f"🎮 [START_MATCH] Starting game...")
            game_start_result = game_actions.start_game()
            custom_log(f"🎮 [START_MATCH] Game start result: {game_start_result}")
            
            if game_start_result.get('error'):
                custom_log(f"❌ [START_MATCH] Game start failed: {game_start_result['error']}")
                self._send_error(session_id, f"Start match failed: {game_start_result['error']}")
                return False
            
            # Get the game round handler
            custom_log(f"🎮 [START_MATCH] Getting game round...")
            game_round = game.get_round()
            
            # Start the first round
            custom_log(f"🎮 [START_MATCH] Starting round...")
            round_result = game_round.start_round()
            custom_log(f"🎮 [START_MATCH] Round start result: {round_result}")
            
            if round_result.get('error'):
                custom_log(f"❌ [START_MATCH] Round start failed: {round_result['error']}")
                self._send_error(session_id, f"Start match failed: {round_result['error']}")
                return False
            
            # Send game started event to all players
            payload = {
                'event_type': 'game_started',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
                'started_by': user_id,
                'round_number': round_result.get('round_number'),
                'round_start_time': round_result.get('round_start_time'),
                'current_player': round_result.get('current_player'),
                'timestamp': datetime.now().isoformat()
            }
            self._send_to_all_players(game_id, 'game_started', payload)
            
            custom_log(f"🎮 Game {game_id} started by {user_id}, round {round_result.get('round_number')}")
            return True
            
        except Exception as e:
            custom_log(f"❌ [START_MATCH] Exception in on_start_match: {e}", level="ERROR")
            import traceback
            custom_log(f"❌ [START_MATCH] Traceback: {traceback.format_exc()}", level="ERROR")
            self._send_error(session_id, f'Start match failed: {str(e)}')
            return False

    # ========= WebSocket Helper Methods =========
    
    def _send_error(self, session_id: str, message: str):
        """Send error message to session"""
        if self.websocket_manager:
            self.websocket_manager.send_to_session(session_id, 'recall_error', {'message': message})

    def _broadcast_event(self, room_id: str, payload: Dict[str, Any]):
        """Broadcast event to room"""
        try:
            event_type = payload.get('event_type')
            if event_type and self.websocket_manager:
                event_payload = {k: v for k, v in payload.items() if k != 'event_type'}
                self.websocket_manager.socketio.emit(event_type, event_payload, room=room_id)
        except Exception as e:
            custom_log(f"❌ Error broadcasting event: {e}")

    def _send_to_player(self, game_id: str, player_id: str, event: str, data: dict) -> bool:
        """Send event to specific player"""
        try:
            game = self.get_game(game_id)
            if not game:
                return False
            session_id = game.get_player_session(player_id)
            if not session_id:
                return False
            self.websocket_manager.send_to_session(session_id, event, data)
            return True
        except Exception as e:
            custom_log(f"❌ Error sending to player: {e}")
            return False

    def _send_to_all_players(self, game_id: str, event: str, data: dict) -> bool:
        """Send event to all players in game"""
        try:
            game = self.get_game(game_id)
            if not game:
                return False
            for player_id, session_id in game.player_sessions.items():
                self.websocket_manager.send_to_session(session_id, event, data)
            return True
        except Exception as e:
            custom_log(f"❌ Error broadcasting to players: {e}")
            return False

    def _send_action_result(self, game_id: str, player_id: str, result: Dict[str, Any]):
        """Send action result to player"""
        data = {'event_type': 'action_result', 'game_id': game_id, 'action_result': result}
        self._send_to_player(game_id, player_id, 'action_result', data)

    def _broadcast_game_action(self, game_id: str, action_type: str, action_data: Dict[str, Any], exclude_player_id: str = None):
        """Broadcast game action to other players"""
        try:
            game = self.get_game(game_id)
            if not game:
                return
            data = {
                'event_type': 'game_action',
                'game_id': game_id,
                'action_type': action_type,
                'action_data': action_data,
                'game_state': self._to_flutter_game_state(game),
            }
            for player_id, session_id in game.player_sessions.items():
                if exclude_player_id and player_id == exclude_player_id:
                    continue
                self.websocket_manager.send_to_session(session_id, 'game_action', data)
        except Exception as e:
            custom_log(f"❌ Error broadcasting game action: {e}")

    def _send_game_state_update(self, game_id: str):
        """Send game state update to all players"""
        game = self.get_game(game_id)
        if game:
            payload = {
                'event_type': 'game_state_updated',
                'game_id': game_id,
                'game_state': self._to_flutter_game_state(game),
            }
            self._send_to_all_players(game_id, 'game_state_updated', payload)
    
    def _send_round_completion_event(self, game_id: str, round_result: Dict[str, Any]):
        """Send round completion event to all players"""
        try:
            payload = {
                'event_type': 'round_completed',
                'game_id': game_id,
                'round_number': round_result.get('round_number'),
                'round_duration': round_result.get('round_duration'),
                'winner': round_result.get('winner'),
                'final_action': round_result.get('final_action'),
                'game_phase': round_result.get('game_phase'),
                'timestamp': datetime.now().isoformat()
            }
            self._send_to_all_players(game_id, 'round_completed', payload)
            custom_log(f"🏁 Round completion event sent for game {game_id}")
        except Exception as e:
            custom_log(f"❌ Error sending round completion event: {e}", level="ERROR")

    def _send_recall_player_joined_events(self, room_id: str, user_id: str, session_id: str, game):
        """Send recall-specific events when a player joins a room"""
        try:
            # Convert game to Flutter format
            game_state = self._to_flutter_game_state(game)
            
            # 1. Send new_player_joined event to the room
            # Get the owner_id for this room from the WebSocket manager
            owner_id = self.websocket_manager.get_room_creator(room_id)
            
            room_payload = {
                'event_type': 'recall_new_player_joined',
                'room_id': room_id,
                'owner_id': owner_id,  # Include owner_id for ownership determination
                'joined_player': {
                    'user_id': user_id,
                    'session_id': session_id,
                    'name': f"Player_{user_id[:8]}",
                    'joined_at': datetime.now().isoformat()
                },
                'game_state': game_state,
                'timestamp': datetime.now().isoformat()
            }
            
            # Send as direct event to the room
            self.websocket_manager.socketio.emit('recall_new_player_joined', room_payload, room=room_id)
            custom_log(f"📡 [RECALL] recall_new_player_joined event sent to room {room_id} for player {user_id}")
            
            # 2. Send joined_games event to the joined user
            user_games = []
            for game_id, user_game in self.active_games.items():
                # Check if user is in this game
                if user_id in user_game.players:
                    user_game_state = self._to_flutter_game_state(user_game)
                    
                    # Get the owner_id for this room from the WebSocket manager
                    owner_id = self.websocket_manager.get_room_creator(game_id)
                    
                    user_games.append({
                        'game_id': game_id,
                        'room_id': game_id,  # Game ID is the same as room ID
                        'owner_id': owner_id,  # Include owner_id for ownership determination
                        'game_state': user_game_state,
                        'joined_at': datetime.now().isoformat()
                    })
            
            user_payload = {
                'event_type': 'recall_joined_games',
                'user_id': user_id,
                'session_id': session_id,
                'games': user_games,
                'total_games': len(user_games),
                'timestamp': datetime.now().isoformat()
            }
            
            # Send as direct event to the specific user's session
            self.websocket_manager.send_to_session(session_id, 'recall_joined_games', user_payload)
            custom_log(f"📡 [RECALL] recall_joined_games event sent to session {session_id} with {len(user_games)} games")
            
        except Exception as e:
            custom_log(f"❌ Error sending recall player joined events: {e}")


    def _to_flutter_card(self, card) -> Dict[str, Any]:
        """Convert card to Flutter format"""
        rank_mapping = {
            '2': 'two', '3': 'three', '4': 'four', '5': 'five',
            '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten'
        }
        return {
            'cardId': card.card_id,
            'suit': card.suit,
            'rank': rank_mapping.get(card.rank, card.rank),
            'points': card.points,
            'displayName': str(card),
            'color': 'red' if card.suit in ['hearts', 'diamonds'] else 'black',
        }

    def _to_flutter_player(self, player, is_current: bool = False) -> Dict[str, Any]:
        """Convert player to Flutter format"""
        return {
            'id': player.player_id,
            'name': player.name,
            'type': 'human' if player.player_type.value == 'human' else 'computer',
            'hand': [self._to_flutter_card(c) for c in player.hand],
            'visibleCards': [self._to_flutter_card(c) for c in player.visible_cards],
            'score': int(player.calculate_points()),
            'status': player.status.value,  # Use the player's actual status
            'isCurrentPlayer': is_current,
            'hasCalledRecall': bool(player.has_called_recall),
        }

    def _to_flutter_game_state(self, game: GameState) -> Dict[str, Any]:
        """Convert game state to Flutter format"""
        phase_mapping = {
            'waiting_for_players': 'waiting',
            'dealing_cards': 'setup',
            'player_turn': 'playing',
            'out_of_turn_play': 'out_of_turn',
            'recall_called': 'recall',
            'game_ended': 'finished',
        }
        
        current_player = None
        if game.current_player_id and game.current_player_id in game.players:
            current_player = self._to_flutter_player(game.players[game.current_player_id], True)

        return {
            'gameId': game.game_id,
            'gameName': f"Recall Game {game.game_id}",
            'players': [self._to_flutter_player(player, pid == game.current_player_id) for pid, player in game.players.items()],
            'currentPlayer': current_player,
            'phase': phase_mapping.get(game.phase.value, 'waiting'),
            'status': 'active' if game.phase.value in ['player_turn', 'out_of_turn_play', 'recall_called'] else 'inactive',
            'drawPile': [self._to_flutter_card(card) for card in game.draw_pile],
            'discardPile': [self._to_flutter_card(card) for card in game.discard_pile],
            'gameStartTime': datetime.fromtimestamp(game.game_start_time).isoformat() if game.game_start_time else None,
            'lastActivityTime': datetime.fromtimestamp(game.last_action_time).isoformat() if game.last_action_time else None,
            'winner': game.winner,
            'playerCount': len(game.players),
            'maxPlayers': game.max_players,
            'minPlayers': game.min_players,
            'activePlayerCount': len([p for p in game.players.values() if p.is_active]),
            'permission': game.permission,  # Include room permission
        }

    def cleanup_ended_games(self):
        """Remove games that have ended"""
        ended_games = []
        for game_id, game_state in self.active_games.items():
            if game_state.game_ended:
                ended_games.append(game_id)
        
        for game_id in ended_games:
            del self.active_games[game_id]
    
    def _register_hook_callbacks(self):
        """Register hook callbacks for automatic game creation"""
        try:
            # Register callback for room_created hook
            self.app_manager.register_hook_callback('room_created', self._on_room_created)
            custom_log("🎣 [HOOK] Registered room_created callback in GameStateManager")
            
            # Register callback for room_joined hook
            self.app_manager.register_hook_callback('room_joined', self._on_room_joined)
            custom_log("🎣 [HOOK] Registered room_joined callback in GameStateManager")
            
            # Register callback for room_closed hook
            self.app_manager.register_hook_callback('room_closed', self._on_room_closed)
            custom_log("🎣 [HOOK] Registered room_closed callback in GameStateManager")
            
            # Register callback for leave_room hook
            self.app_manager.register_hook_callback('leave_room', self._on_leave_room)
            custom_log("🎣 [HOOK] Registered leave_room callback in GameStateManager")
            
        except Exception as e:
            custom_log(f"❌ Error registering hook callbacks: {e}", level="ERROR")
    
    def _on_room_created(self, room_data: Dict[str, Any]):
        """Callback for room_created hook - automatically create game"""
        try:
            room_id = room_data.get('room_id')
            max_players = room_data.get('max_players', 4)
            min_players = room_data.get('min_players', 2)
            permission = room_data.get('permission', 'public')  # Extract room permission
            
            custom_log(f"🎮 [HOOK] Room created: {room_id}, creating game automatically with permission: {permission}")
            
            # Create game with room_id as game_id and room permission
            game_id = self.create_game_with_id(room_id, max_players=max_players, min_players=min_players, permission=permission)
            
            # Initialize game state (waiting for players)
            game = self.get_game(game_id)
            if game:
                game.phase = GamePhase.WAITING_FOR_PLAYERS
                custom_log(f"✅ Game {game_id} created and initialized for room {room_id} with permission: {permission}")
            else:
                custom_log(f"❌ Failed to create game for room {room_id}")
                
        except Exception as e:
            custom_log(f"❌ Error in _on_room_created callback: {e}", level="ERROR")
    
    def _on_room_joined(self, room_data: Dict[str, Any]):
        """Callback for room_joined hook - handle player joining existing game"""
        try:
            room_id = room_data.get('room_id')
            user_id = room_data.get('user_id')
            session_id = room_data.get('session_id')  # Get session_id from room_data
            current_size = room_data.get('current_size', 1)
            
            custom_log(f"🎮 [HOOK] Player {user_id} joined room {room_id}, session: {session_id}, current size: {current_size}")
            
            # Check if game exists for this room
            game = self.get_game(room_id)
            if not game:
                custom_log(f"⚠️ No game found for room {room_id}, this shouldn't happen")
                return
            
            # Add player to the game if they don't exist
            player_added = False
            if user_id not in game.players:
                # Create a human player for the user
                from ..models.player import HumanPlayer
                player = HumanPlayer(user_id, f"Player_{user_id[:8]}")
                game.add_player(player)
                player_added = True
                custom_log(f"✅ Added player {user_id} to game {room_id}")
            else:
                custom_log(f"ℹ️ Player {user_id} already exists in game {room_id}")
            
            # Set up session mapping for the player
            if session_id and user_id:
                game.update_player_session(user_id, session_id)
                custom_log(f"🔗 Session mapping created: session {session_id} -> player {user_id}")
            
            # Update room size in WebSocket manager (if player was newly added)
            if player_added:
                try:
                    from core.managers.websockets.websocket_manager import WebSocketManager
                    ws_manager = WebSocketManager.instance
                    if ws_manager:
                        ws_manager.update_room_size(room_id, 1)  # Increase room size by 1
                        custom_log(f"📊 Updated room {room_id} size after player {user_id} joined")
                except Exception as e:
                    custom_log(f"⚠️ Failed to update room size: {e}")
            
            # Update game state based on player count
            if current_size >= game.min_players and game.phase == GamePhase.WAITING_FOR_PLAYERS:
                custom_log(f"🎮 Room {room_id} has enough players ({current_size}), ready to start")
                # Game is ready but not started yet - will be started manually or via auto-start
            
            # 🎯 NEW: Send recall-specific events after player joins
            self._send_recall_player_joined_events(room_id, user_id, session_id, game)
            
        except Exception as e:
            custom_log(f"❌ Error in _on_room_joined callback: {e}", level="ERROR")
    
    def _on_room_closed(self, room_data: Dict[str, Any]):
        """Callback for room_closed hook - cleanup game when room is closed"""
        try:
            room_id = room_data.get('room_id')
            reason = room_data.get('reason', 'unknown')
            
            custom_log(f"🎮 [HOOK] Room closed: {room_id}, reason: {reason}, cleaning up game")
            
            # Remove game if it exists
            if room_id in self.active_games:
                del self.active_games[room_id]
                custom_log(f"✅ Game {room_id} removed due to room closure")
            else:
                custom_log(f"ℹ️ No game found for closed room {room_id}")
                
        except Exception as e:
            custom_log(f"❌ Error in _on_room_closed callback: {e}", level="ERROR")
    
    def _on_leave_room(self, room_data: Dict[str, Any]):
        """Callback for leave_room hook - handle player leaving game"""
        try:
            room_id = room_data.get('room_id')
            session_id = room_data.get('session_id')
            user_id = room_data.get('user_id')  # Get user_id from room_data
            
            custom_log(f"🎮 [HOOK] Player left room: {room_id}, session: {session_id}, user: {user_id}")
            
            # Check if game exists for this room
            game = self.get_game(room_id)
            if not game:
                custom_log(f"ℹ️ No game found for room {room_id}")
                return
            
            # Try to find player by session_id first
            player_id = None
            if session_id:
                player_id = game.get_session_player(session_id)
                if player_id:
                    custom_log(f"🔍 Found player {player_id} by session {session_id}")
            
            # Fallback: try to find player by user_id if session lookup failed
            if not player_id and user_id:
                if user_id in game.players:
                    player_id = user_id
                    custom_log(f"🔍 Found player {player_id} by user_id {user_id}")
            
            # Remove player if found
            if player_id:
                game.remove_player(player_id)
                custom_log(f"✅ Player {player_id} removed from game {room_id}")
                
                # Clean up session mapping
                if session_id:
                    game.remove_session(session_id)
                    custom_log(f"🧹 Session mapping cleaned up for session {session_id}")
                
                # Update room size in WebSocket manager
                try:
                    from core.managers.websockets.websocket_manager import WebSocketManager
                    ws_manager = WebSocketManager.instance
                    if ws_manager:
                        ws_manager.update_room_size(room_id, -1)  # Decrease room size by 1
                        custom_log(f"📊 Updated room {room_id} size after player {player_id} left")
                except Exception as e:
                    custom_log(f"⚠️ Failed to update room size: {e}")
                
                # Note: Game phase remains WAITING_FOR_PLAYERS even when empty
                # Games are only cleaned up when rooms are closed (via TTL or stale cleanup)
                custom_log(f"🎮 Game {room_id} now has {len(game.players)} players, but remains available for joining")
            else:
                custom_log(f"⚠️ No player found for session {session_id} or user {user_id} in game {room_id}")
            
        except Exception as e:
            custom_log(f"❌ Error in _on_leave_room callback: {e}", level="ERROR")