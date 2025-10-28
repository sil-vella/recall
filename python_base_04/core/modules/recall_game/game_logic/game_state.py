"""
Game State Models for Recall Game

This module defines the game state management system for the Recall card game,
including game phases, state transitions, game logic, and WebSocket communication.
"""

from typing import List, Dict, Any, Optional
from enum import Enum
from ..models.card import Card, CardDeck
from ..utils.deck_factory import DeckFactory
from ..models.player import Player, HumanPlayer, ComputerPlayer, PlayerType, PlayerStatus
from tools.logger.custom_logging import custom_log
from datetime import datetime
import time
import uuid
import threading

LOGGING_SWITCH = True

class GamePhase(Enum):
    """Game phases"""
    WAITING_FOR_PLAYERS = "waiting_for_players"
    DEALING_CARDS = "dealing_cards"
    INITIAL_PEEK = "initial_peek"
    PLAYER_TURN = "player_turn"
    SAME_RANK_WINDOW = "same_rank_window"
    SPECIAL_PLAY_WINDOW = "special_play_window"
    QUEEN_PEEK_WINDOW = "queen_peek_window"
    TURN_PENDING_EVENTS = "turn_pending_events"
    ENDING_ROUND = "ending_round"
    ENDING_TURN = "ending_turn"
    RECALL_CALLED = "recall_called"
    GAME_ENDED = "game_ended"


class GameState:
    """Represents the current state of a Recall game"""
    
    def __init__(self, game_id: str, max_players: int = 4, min_players: int = 4, permission: str = 'public', app_manager=None):
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
        
        # Auto-change detection for state updates
        self._change_tracking_enabled = True
        self._pending_changes = set()  # Track which properties have changed
        self._initialized = True  # Flag to prevent tracking during initialization
        self._previous_phase = None  # Track previous phase for transition detection
    
    def add_player(self, player: Player, session_id: str = None) -> bool:
        """Add a player to the game"""
        if len(self.players) >= self.max_players:
            return False
        
        self.players[player.player_id] = player
        
        # Set up auto-detection references for the player
        if hasattr(player, 'set_game_references') and self.app_manager:
            game_state_manager = getattr(self.app_manager, 'game_state_manager', None)
            if game_state_manager:
                player.set_game_references(game_state_manager, self.game_id)
        
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
    
    # ========= DISCARD PILE MANAGEMENT METHODS =========
    
    def add_to_discard_pile(self, card: Card) -> bool:
        """Add a card to the discard pile with automatic change detection"""
        try:
            self.discard_pile.append(card)
            
            # Manually trigger change detection for discard_pile
            if hasattr(self, '_track_change'):
                self._track_change('discard_pile')
                self._send_changes_if_needed()
            
            custom_log(f"Card {card.card_id} ({card.rank} of {card.suit}) added to discard pile", level="INFO")
            return True
        except Exception as e:
            custom_log(f"Failed to add card to discard pile: {e}", level="ERROR")
            return False
    
    def remove_from_discard_pile(self, card_id: str) -> Optional[Card]:
        """Remove a card from the discard pile by card_id with automatic change detection"""
        try:
            for i, card in enumerate(self.discard_pile):
                if card.card_id == card_id:
                    removed_card = self.discard_pile.pop(i)
                    
                    # Manually trigger change detection for discard_pile
                    if hasattr(self, '_track_change'):
                        self._track_change('discard_pile')
                        self._send_changes_if_needed()
                    
                    custom_log(f"Card {card_id} ({removed_card.rank} of {removed_card.suit}) removed from discard pile", level="INFO")
                    return removed_card
            
            custom_log(f"Card {card_id} not found in discard pile", level="WARNING")
            return None
        except Exception as e:
            custom_log(f"Failed to remove card from discard pile: {e}", level="ERROR")
            return None
    
    def get_top_discard_card(self) -> Optional[Card]:
        """Get the top card from the discard pile without removing it"""
        if self.discard_pile:
            return self.discard_pile[-1]
        return None
    
    def clear_discard_pile(self) -> List[Card]:
        """Clear the discard pile and return all cards with automatic change detection"""
        try:
            cleared_cards = self.discard_pile.copy()
            self.discard_pile.clear()
            
            # Manually trigger change detection for discard_pile
            if hasattr(self, '_track_change'):
                self._track_change('discard_pile')
                self._send_changes_if_needed()
            
            custom_log(f"Discard pile cleared, {len(cleared_cards)} cards removed", level="INFO")
            return cleared_cards
        except Exception as e:
            custom_log(f"Failed to clear discard pile: {e}", level="ERROR")
            return []
    
    # ========= DRAW PILE MANAGEMENT METHODS =========
    
    def draw_from_draw_pile(self) -> Optional[Card]:
        """Draw a card from the draw pile with automatic change detection"""
        try:
            if not self.draw_pile:
                custom_log("Cannot draw from empty draw pile", level="WARNING")
                return None
            
            drawn_card = self.draw_pile.pop()
            
            # Manually trigger change detection for draw_pile
            if hasattr(self, '_track_change'):
                self._track_change('draw_pile')
                self._send_changes_if_needed()
            
            custom_log(f"Card {drawn_card.card_id} ({drawn_card.rank} of {drawn_card.suit}) drawn from draw pile", level="INFO")
            return drawn_card
        except Exception as e:
            custom_log(f"Failed to draw from draw pile: {e}", level="ERROR")
            return None
    
    def draw_from_discard_pile(self) -> Optional[Card]:
        """Draw a card from the discard pile with automatic change detection"""
        try:
            if not self.discard_pile:
                custom_log("Cannot draw from empty discard pile", level="WARNING")
                return None
            
            drawn_card = self.discard_pile.pop()
            
            # Manually trigger change detection for discard_pile
            if hasattr(self, '_track_change'):
                self._track_change('discard_pile')
                self._send_changes_if_needed()
            
            custom_log(f"Card {drawn_card.card_id} ({drawn_card.rank} of {drawn_card.suit}) drawn from discard pile", level="INFO")
            return drawn_card
        except Exception as e:
            custom_log(f"Failed to draw from discard pile: {e}", level="ERROR")
            return None
    
    def add_to_draw_pile(self, card: Card) -> bool:
        """Add a card to the draw pile with automatic change detection"""
        try:
            self.draw_pile.append(card)
            
            # Manually trigger change detection for draw_pile
            if hasattr(self, '_track_change'):
                self._track_change('draw_pile')
                self._send_changes_if_needed()
            
            custom_log(f"Card {card.card_id} ({card.rank} of {card.suit}) added to draw pile", level="INFO")
            return True
        except Exception as e:
            custom_log(f"Failed to add card to draw pile: {e}", level="ERROR")
            return False
    
    def get_draw_pile_count(self) -> int:
        """Get the number of cards in the draw pile"""
        return len(self.draw_pile)
    
    def get_discard_pile_count(self) -> int:
        """Get the number of cards in the discard pile"""
        return len(self.discard_pile)
    
    def is_draw_pile_empty(self) -> bool:
        """Check if the draw pile is empty"""
        return len(self.draw_pile) == 0
    
    def is_discard_pile_empty(self) -> bool:
        """Check if the discard pile is empty"""
        return len(self.discard_pile) == 0

    # ========= PLAYER STATUS MANAGEMENT METHODS =========
    
    def update_all_players_status(self, status: PlayerStatus, filter_active: bool = True) -> int:
        """
        Update all players' status efficiently with a single game state update.
        
        This method updates the game_state.players property once, which triggers
        a single WebSocket update to the room instead of individual player updates.
        
        Args:
            status (PlayerStatus): The new status to set for all players
            filter_active (bool): If True, only update active players. If False, update all players.
            
        Returns:
            int: Number of players whose status was updated
        """
        try:
            updated_count = 0
            
            # Update each player's status directly (this will trigger individual change detection)
            for player_id, player in self.players.items():
                if not filter_active or player.is_active:
                    player.set_status(status)
                    updated_count += 1
                    custom_log(f"Player {player_id} status updated to {status.value}", level="INFO")
            
            # The individual player.set_status() calls will trigger their own change detection
            # and send individual player updates. The game_state.players property change
            # will also trigger a game state update, ensuring all clients get the latest data.
            
            custom_log(f"Updated {updated_count} players' status to {status.value}", level="INFO")
            return updated_count
            
        except Exception as e:
            custom_log(f"Failed to update all players status: {e}", level="ERROR")
            return 0
    
    def update_players_status_by_ids(self, player_ids: List[str], status: PlayerStatus) -> int:
        """
        Update specific players' status efficiently.
        
        Args:
            player_ids (List[str]): List of player IDs to update
            status (PlayerStatus): The new status to set
            
        Returns:
            int: Number of players whose status was updated
        """
        try:
            updated_count = 0
            
            for player_id in player_ids:
                if player_id in self.players:
                    player = self.players[player_id]
                    player.set_status(status)
                    updated_count += 1
                    custom_log(f"Player {player_id} status updated to {status.value}", level="INFO", isOn=LOGGING_SWITCH)
                else:
                    custom_log(f"Player {player_id} not found in game", level="WARNING", isOn=LOGGING_SWITCH)
            
            custom_log(f"Updated {updated_count} players' status to {status.value}", level="INFO", isOn=LOGGING_SWITCH)
            return updated_count
            
        except Exception as e:
            custom_log(f"Failed to update players status by IDs: {e}", level="ERROR")
            return 0

    def clear_same_rank_data(self) -> None:
        """
        Clear the same_rank_data list with auto-change detection.
        
        This method ensures that clearing the same_rank_data triggers
        the automatic change detection system for WebSocket updates.
        """
        try:
            if hasattr(self, 'same_rank_data') and self.same_rank_data:
                self.same_rank_data.clear()
                custom_log("Same rank data cleared via custom method", level="INFO", isOn=LOGGING_SWITCH)
            else:
                custom_log("Same rank data was already empty or doesn't exist", level="DEBUG", isOn=LOGGING_SWITCH)
        except Exception as e:
            custom_log(f"Error clearing same rank data: {e}", level="ERROR", isOn=LOGGING_SWITCH)

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
                if card is not None and card.card_id == card_id:
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
    
    def get_round(self):
        """Get the game round handler"""
        # Create a persistent GameRound instance if it doesn't exist
        if not hasattr(self, '_game_round_instance'):
            from .game_round import GameRound
            self._game_round_instance = GameRound(self)
        return self._game_round_instance
    
    # ========= AUTO-CHANGE DETECTION METHODS =========
    
    def __setattr__(self, name, value):
        """Override __setattr__ to automatically detect property changes"""
        # Skip tracking during initialization or for internal attributes
        if not hasattr(self, '_initialized') or not self._initialized:
            super().__setattr__(name, value)
            return
        
        # Skip tracking for internal change detection attributes
        if name.startswith('_') and name in ['_change_tracking_enabled', '_pending_changes', '_initialized']:
            super().__setattr__(name, value)
            return
        
        # Get current value for comparison
        current_value = getattr(self, name, None)
        
        # Special handling for phase changes - track previous phase
        if name == 'phase' and hasattr(self, '_previous_phase'):
            self._previous_phase = current_value
        
        # Set the new value
        super().__setattr__(name, value)
        
        # Track change if value actually changed and tracking is enabled
        if (self._change_tracking_enabled and 
            current_value != value and 
            name not in ['_change_tracking_enabled', '_pending_changes', '_initialized']):
            
            self._track_change(name)
            self._send_changes_if_needed()
    
    def _track_change(self, property_name: str):
        """Track that a property has changed"""
        if self._change_tracking_enabled:
            self._pending_changes.add(property_name)
            custom_log(f"📝 Tracking change for property: {property_name}", isOn=LOGGING_SWITCH)
            
            # Detect specific phase transitions
            if property_name == 'phase':
                self._detect_phase_transitions()
    
    def _detect_phase_transitions(self):
        """Detect and log specific phase transitions"""
        try:
            # Get the current and previous phases
            current_phase = self.phase
            previous_phase = self._previous_phase
            
            # Check for SPECIAL_PLAY_WINDOW to ENDING_ROUND transition
            if (current_phase == GamePhase.ENDING_ROUND and 
                previous_phase == GamePhase.SPECIAL_PLAY_WINDOW):
                
                custom_log(f"🎯 PHASE TRANSITION DETECTED: SPECIAL_PLAY_WINDOW → ENDING_ROUND", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"🎯 Game ID: {self.game_id}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"🎯 Previous phase: {previous_phase.value if previous_phase else 'None'}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"🎯 Current phase: {current_phase.value}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"🎯 Current player: {self.current_player_id}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"🎯 Player count: {len(self.players)}", level="INFO", isOn=LOGGING_SWITCH)
                custom_log(f"🎯 Timestamp: {datetime.now().isoformat()}", level="INFO", isOn=LOGGING_SWITCH)
                
        except Exception as e:
            custom_log(f"❌ Error in _detect_phase_transitions: {e}", level="ERROR", isOn=LOGGING_SWITCH)
    
    def _send_changes_if_needed(self):
        """Send state updates if there are pending changes"""
        try:
            custom_log(f"🔄 _send_changes_if_needed called with {len(self._pending_changes)} pending changes", isOn=LOGGING_SWITCH)
            
            if not self._change_tracking_enabled or not self._pending_changes:
                custom_log("❌ Change tracking disabled or no pending changes", isOn=LOGGING_SWITCH)
                return
            
            # Get coordinator and send partial update
            if self.app_manager:
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    changes_list = list(self._pending_changes)
                    custom_log(f"=== SENDING PARTIAL UPDATE ===", isOn=LOGGING_SWITCH)
                    custom_log(f"Game ID: {self.game_id}", isOn=LOGGING_SWITCH)
                    custom_log(f"Changed properties: {changes_list}", isOn=LOGGING_SWITCH)
                    custom_log(f"==============================", isOn=LOGGING_SWITCH)
                    
                    coordinator._send_game_state_partial_update(self.game_id, changes_list)
                    custom_log(f"✅ Partial update sent successfully for properties: {changes_list}", isOn=LOGGING_SWITCH)
                else:
                    custom_log("❌ No coordinator found - cannot send partial update", isOn=LOGGING_SWITCH)
            else:
                custom_log("❌ No app_manager found - cannot send partial update", isOn=LOGGING_SWITCH)
            
            # Clear pending changes
            self._pending_changes.clear()
            custom_log(f"✅ Cleared pending changes", isOn=LOGGING_SWITCH)
            
        except Exception as e:
            custom_log(f"❌ Error in _send_changes_if_needed: {e}", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"❌ Traceback: {traceback.format_exc()}", isOn=LOGGING_SWITCH)
    
    def enable_change_tracking(self):
        """Enable automatic change tracking"""
        self._change_tracking_enabled = True
    
    def disable_change_tracking(self):
        """Disable automatic change tracking"""
        self._change_tracking_enabled = False
    



    

    
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
                return False
            
            # Register hook callbacks for automatic game creation
            self._register_hook_callbacks()
            
            self._initialized = True
            return True
        except Exception as e:
            return False
    
    def create_game(self, max_players: int = 4, min_players: int = 4, permission: str = 'public') -> str:
        """Create a new game"""
        game_id = str(uuid.uuid4())
        game_state = GameState(game_id, max_players, min_players, permission, self.app_manager)
        self.active_games[game_id] = game_state
        return game_id
    
    def create_game_with_id(self, game_id: str, max_players: int = 4, min_players: int = 4, permission: str = 'public') -> str:
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
            
            # Only include PUBLIC games that are waiting for players
            if game.phase == GamePhase.WAITING_FOR_PLAYERS and game.permission == 'public':
                # Convert to Flutter-compatible format using GameStateManager's method
                game_data = self._to_flutter_game_data(game)
                available_games.append(game_data)
                public_games += 1
            elif game.permission == 'private':
                private_games += 1
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
                # Use the coordinator to send error message
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, f'Game not found: {game_id} - games are auto-created when rooms are created')
                    else:
                        pass
                else:
                    pass
                return False

            # Join the room (game and room have same ID)
            self.websocket_manager.join_room(game_id, session_id)

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)

            # Add player if not exists
            if user_id not in game.players:
                player = ComputerPlayer(user_id, player_name) if player_type == 'computer' else HumanPlayer(user_id, player_name)
                game.add_player(player, session_id)
            else:
                game.update_player_session(user_id, session_id)

            # Broadcast join event using coordinator
            payload = {
                'event_type': 'game_joined',
                'game_id': game_id,
                'game_state': None,  # Will be set by coordinator
                'player': self._to_flutter_player_data(game.players[user_id], user_id == game.current_player_id),
            }
            
            # Get game state using GameStateManager's method
            payload['game_state'] = self._to_flutter_game_data(game)
            
            # Use the coordinator to broadcast the event
            if hasattr(self, 'app_manager') and self.app_manager:
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._broadcast_event(game_id, payload)
                else:
                    pass
            else:
                pass
            
            return True
            
        except Exception as e:
            # Use the coordinator to send error message
            if hasattr(self, 'app_manager') and self.app_manager:
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_error(session_id, f'Join game failed: {str(e)}')
                else:
                    pass
            else:
                pass
            return False

    def on_start_match(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle game start through the game round"""
        try:
            
            game_id = data.get('game_id') or data.get('room_id')
            if not game_id:
                # Use the coordinator to send error message
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, 'Missing game_id')
                    else:
                        pass
                else:
                    pass
                return False
            game = self.get_game(game_id)
            if not game:
                # Use the coordinator to send error message
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, f'Game not found: {game_id}')
                    else:
                        pass
                else:
                    pass
                return False
            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            
            # Check if we have enough players, add computer players if needed
            current_players = len(game.players)
            min_players = game.min_players
            
            if current_players < min_players:
                # Add computer players to reach minimum
                players_needed = min_players - current_players
                
                for i in range(players_needed):
                    computer_id = f"computer_{game.game_id}_{i}"
                    computer_name = f"Computer_{i+1}"
                    from ..models.player import ComputerPlayer
                    computer_player = ComputerPlayer(computer_id, computer_name, difficulty="medium")
                    game.add_player(computer_player)
            
            game.phase = GamePhase.DEALING_CARDS
            game.game_start_time = time.time()
            
            # Build deck from factory (normal or testing based on TESTING_SWITCH), then deal
            from ..utils.deck_factory import get_deck_factory
            factory = get_deck_factory(game.game_id)
            game.deck.cards = factory.build_deck(
                include_jokers=True,  # Standard deck cards (including jokers, queens, jacks, kings)
            )
            self._deal_cards(game)
            
            # Set up draw and discard piles
            self._setup_piles(game)
            
            # Set first player
            player_ids = list(game.players.keys())
            game.current_player_id = player_ids[0]
            
            game.phase = GamePhase.PLAYER_TURN
            game.last_action_time = time.time()
            game_round = game.get_round()
            
            # Update all players' status to READY efficiently (single game state update)
            updated_count = game.update_all_players_status(PlayerStatus.READY, filter_active=True)
            custom_log(f"Updated {updated_count} players' status to READY for game start", level="INFO", isOn=LOGGING_SWITCH)
            
            initial_peek_result = self.initial_peek(game)
                        
        except Exception as e:
            custom_log(f"Failed to handle start match: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
            return False
            
    # ========= CONSOLIDATED GAME START HELPER METHODS =========
    
    def _process_ai_initial_peeks(self, game: GameState):
        """Process AI player initial peeks - select 2 random cards and store in known_cards"""
        try:
            import random
            
            for player_id, player in game.players.items():
                if player.player_type == PlayerType.COMPUTER:
                    # Get player's hand (list of Card objects or None)
                    hand = [card for card in player.hand if card is not None]
                    
                    if len(hand) < 2:
                        continue
                    
                    # Select 2 random cards
                    selected_cards = random.sample(hand, 2)
                    
                    # AI Decision Logic: Determine which card should be marked as collection rank
                    selected_card_for_collection = self._select_card_for_collection(selected_cards[0], selected_cards[1], random)
                    
                    # Determine which card is NOT the collection card
                    non_collection_card = selected_cards[1] if selected_card_for_collection == selected_cards[0] else selected_cards[0]
                    
                    # Store only the non-collection card in known_cards with full card data
                    card_data = non_collection_card.to_dict()
                    card_id = card_data['card_id']
                    player.known_cards[player_id] = {
                        card_id: card_data
                    }
                    
                    # Add the selected Card object to the player's collection_rank_cards list
                    player.collection_rank_cards.append(selected_card_for_collection)
                    
                    # Update player's collection_rank to match the selected card's rank
                    player.collection_rank = selected_card_for_collection.rank
                    
                    # Manually trigger change detection for this player's known_cards and collection_rank_cards update
                    if hasattr(player, '_track_change'):
                        player._track_change('known_cards')
                        player._track_change('collection_rank_cards')
                        player._send_changes_if_needed()
                    
                    custom_log(f"AI {player.name} peeked at 2 random cards and triggered state update", level="INFO", isOn=LOGGING_SWITCH)
                    custom_log(f"AI {player.name} selected {selected_card_for_collection.rank} of {selected_card_for_collection.suit} for collection ({selected_card_for_collection.points} points)", level="INFO", isOn=LOGGING_SWITCH)
                    custom_log(f"AI {player.name} collection_rank_cards now has {len(player.collection_rank_cards)} cards: {[card.card_id for card in player.collection_rank_cards if isinstance(card, Card)]}", level="INFO", isOn=LOGGING_SWITCH)
            
        except Exception as e:
            custom_log(f"Failed to process AI initial peeks: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)

    def _select_card_for_collection(self, card1, card2, random):
        """AI Decision Logic: Select which card should be marked as collection rank
        Priority: Least points first, then by rank order (ace, number, king, queen, jack)
        """
        points1 = card1.points or 0
        points2 = card2.points or 0
        rank1 = card1.rank or ''
        rank2 = card2.rank or ''
        
        # If points are different, select the one with least points
        if points1 != points2:
            return card1 if points1 < points2 else card2
        
        # If points are the same, use priority order: ace, number, king, queen, jack
        priority1 = self._get_card_priority(rank1)
        priority2 = self._get_card_priority(rank2)
        
        if priority1 != priority2:
            return card1 if priority1 < priority2 else card2
        
        # If both cards have same rank, random pick
        return card1 if random.choice([True, False]) else card2

    def _get_card_priority(self, rank):
        """Get priority value for card rank (lower = higher priority)"""
        if rank == 'ace':
            return 1  # Highest priority
        elif rank in ['2', '3', '4', '5', '6', '7', '8', '9', '10']:
            return 2  # Numbers
        elif rank == 'king':
            return 3  # Kings
        elif rank == 'queen':
            return 4  # Queens
        elif rank == 'jack':
            return 5  # Jacks (lowest priority)
        else:
            return 6  # Unknown ranks (lowest)

    def initial_peek(self, game: GameState):
        """Handle initial peek for the game - set all players to INITIAL_PEEK status with 10-second timer"""
        try:
            # Set game phase to INITIAL_PEEK
            game.phase = GamePhase.INITIAL_PEEK
            
            # Set all players to INITIAL_PEEK status
            updated_count = game.update_all_players_status(PlayerStatus.INITIAL_PEEK, filter_active=True)
            
            custom_log(f"Initial peek phase started - {updated_count} players set to INITIAL_PEEK status", level="INFO", isOn=LOGGING_SWITCH)
            
            # Process AI initial peeks immediately
            self._process_ai_initial_peeks(game)
            
            # Start threaded timer for 10 seconds
            timer_thread = threading.Timer(10.0, self._initial_peek_timeout, args=[game])
            timer_thread.daemon = True  # Allow program to exit even if timer is running
            timer_thread.start()
            
            custom_log("Initial peek timer started - 10 seconds until game begins", level="INFO", isOn=LOGGING_SWITCH)
            
            return {
                "success": True,
                "message": f"Initial peek phase started for {updated_count} players - 10 second timer active",
                "updated_count": updated_count,
                "timer_duration": 10
            }
            
        except Exception as e:
            custom_log(f"Failed to handle initial peek: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
            return {"error": f"Failed to handle initial peek: {str(e)}"}
    
    def _initial_peek_timeout(self, game: GameState):
        """Called when initial peek timer expires - transition to game start"""
        try:
            custom_log("Initial peek timer expired - transitioning to game start", level="INFO", isOn=LOGGING_SWITCH)
            
            # Clear cards_to_peek for all players (peek phase is over)
            cleared_count = 0
            for player in game.players.values():
                if player.cards_to_peek:
                    player.clear_cards_to_peek()
                    cleared_count += 1
            custom_log(f"Cleared cards_to_peek for {cleared_count} players", level="INFO", isOn=LOGGING_SWITCH)
            
            # Set all players back to WAITING status
            updated_count = game.update_all_players_status(PlayerStatus.WAITING, filter_active=True)
            custom_log(f"Set {updated_count} players back to WAITING status", level="INFO", isOn=LOGGING_SWITCH)
            
            # Check each human player - if they didn't peek, randomly select collection rank
            for player_id, player in game.players.items():
                if player.player_type == PlayerType.HUMAN:
                    # Check if player has known_cards (means they peeked)
                    has_player_known_cards = player_id in player.known_cards
                    
                    if not has_player_known_cards and len(player.hand) > 0:
                        # Player never peeked - randomly select 1 card from hand
                        import random
                        random_card = random.choice([card for card in player.hand if card is not None])
                        player.collection_rank_cards.append(random_card)
                        
                        # Update player's collection_rank to match the selected card's rank
                        player.collection_rank = random_card.rank
                        
                        # Manually trigger change detection
                        if hasattr(player, '_track_change'):
                            player._track_change('collection_rank_cards')
                            player._send_changes_if_needed()
                        
                        custom_log(f"Human {player.name} never peeked - randomly selected {random_card.rank} of {random_card.suit} for collection", level="INFO", isOn=LOGGING_SWITCH)
            
            # Transition to PLAYER_TURN phase
            game.phase = GamePhase.PLAYER_TURN
            custom_log(f"Game phase transitioned to {game.phase.value}", level="INFO", isOn=LOGGING_SWITCH)
            
            game_round = game.get_round()
            custom_log("Starting game round turn", level="INFO", isOn=LOGGING_SWITCH)
            start_turn_result = game_round.start_turn()

        except Exception as e:
            custom_log(f"Failed to handle initial peek timeout: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
            return False
            
    def on_completed_initial_peek(self, session_id: str, data: Dict[str, Any]) -> bool:
        """
        Handle completed initial peek for the game.
        
        This method:
        1. Gets the player who completed the peek
        2. Receives card IDs from frontend (2 card IDs the player peeked at)
        3. Uses get_card_by_id() to find the full card data for each ID
        4. Adds the cards to player's cards_to_peek list (sent with full data)
        5. Triggers change detection to send updated cards_to_peek to frontend
        6. Sets player status to WAITING
        
        Note: Hand cards remain as ID-only. The cards_to_peek list contains the full
        card data for the peeked cards, which will be merged with hand in frontend.
        """
        try:
            custom_log("Completed initial peek", level="INFO", isOn=LOGGING_SWITCH)
            
            # Get game_id
            game_id = data.get('game_id') or data.get('room_id')
            if not game_id:
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, 'Missing game_id')
                return False
            
            # Get card_ids from payload
            card_ids = data.get('card_ids', [])
            if not card_ids or len(card_ids) != 2:
                custom_log(f"Invalid card_ids: {card_ids}. Expected 2 card IDs.", level="ERROR", isOn=LOGGING_SWITCH)
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, 'Invalid card_ids: must provide exactly 2 card IDs')
                return False
            
            # Get game
            game = self.get_game(game_id)
            if not game:
                if hasattr(self, 'app_manager') and self.app_manager:
                    coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                    if coordinator:
                        coordinator._send_error(session_id, f'Game not found: {game_id}')
                return False
            
            # Get user_id from session
            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id or session_data.get('player_id'))
            custom_log(f"Completed initial peek - user_id: {user_id}, card_ids: {card_ids}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Get player
            player = game.players.get(user_id)
            if not player:
                custom_log(f"Player {user_id} not found in game {game_id}", level="ERROR", isOn=LOGGING_SWITCH)
                return False
            
            # Clear any existing cards from previous peeks
            player.clear_cards_to_peek()
            
            # For each card ID, find the full card data and add to cards_to_peek
            # Use trigger_update=False to batch the updates (only send one update after all cards added)
            cards_updated = 0
            for card_id in card_ids:
                # Use get_card_by_id to find the full card data
                card_data = game.get_card_by_id(card_id)
                if not card_data:
                    custom_log(f"Card {card_id} not found in game", level="ERROR", isOn=LOGGING_SWITCH)
                    continue
                
                # Add the card to the cards_to_peek list WITHOUT triggering immediate update (batch operation)
                player.add_card_to_peek(card_data, trigger_update=False)
                cards_updated += 1
                custom_log(f"Added card {card_id} to player's cards_to_peek list", level="DEBUG", isOn=LOGGING_SWITCH)
            
            if cards_updated != 2:
                custom_log(f"Warning: Only added {cards_updated} out of 2 cards to cards_to_peek", level="WARNING", isOn=LOGGING_SWITCH)
            
            custom_log(f"Player {user_id} peeked at {cards_updated} cards: {card_ids}", level="INFO", isOn=LOGGING_SWITCH)
            
            # Store peeked cards in known_cards (card-ID-based structure)
            player.known_cards[player.player_id] = {}
            for card in player.cards_to_peek:
                if card:
                    card_data = card.to_dict()
                    card_id = card_data['card_id']
                    player.known_cards[player.player_id][card_id] = card_data
            
            custom_log(f"Human player {player.name} stored {len(player.cards_to_peek)} cards in known_cards", level="INFO", isOn=LOGGING_SWITCH)
            
            # Auto-select collection rank card for human player (same logic as AI)
            peeked_cards = player.cards_to_peek
            if len(peeked_cards) >= 2:
                import random
                selected_card_for_collection = self._select_card_for_collection(peeked_cards[0], peeked_cards[1], random)
                player.collection_rank_cards.append(selected_card_for_collection)
                
                # Update player's collection_rank to match the selected card's rank
                player.collection_rank = selected_card_for_collection.rank
                
                # Manually trigger change detection
                if hasattr(player, '_track_change'):
                    player._track_change('collection_rank_cards')
                
                custom_log(f"Human {player.name} selected {selected_card_for_collection.rank} of {selected_card_for_collection.suit} for collection ({selected_card_for_collection.points} points)", level="INFO", isOn=LOGGING_SWITCH)
            
            # Manually trigger change detection ONCE after all cards have been added
            if hasattr(player, '_track_change'):
                player._track_change('cards_to_peek')
                player._send_changes_if_needed()
            
            # Set player status to WAITING
            completed_peek = game.update_players_status_by_ids([user_id], PlayerStatus.WAITING)
            custom_log(f"Completed initial peek - {completed_peek} players set to WAITING status", level="INFO", isOn=LOGGING_SWITCH)

            return True
        except Exception as e:
            custom_log(f"Failed to handle completed initial peek: {str(e)}", level="ERROR", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)
            return False
    
    def _deal_cards(self, game: GameState):
        """Deal 4 cards to each player, excluding jokers from initial hands - moved from GameActions"""
        
        # Check if predefined hands are enabled
        from ..utils.predefined_hands_loader import PredefinedHandsLoader
        hands_loader = PredefinedHandsLoader()
        config = hands_loader.load_config()
        
        if config['enabled']:
            custom_log("Using PREDEFINED HANDS for testing", level="WARNING", isOn=LOGGING_SWITCH)
            self._deal_predefined_cards(game, config['hands'])
            return
        
        # Step 1: Separate jokers from non-joker cards
        joker_cards = [card for card in game.deck.cards if card.rank == 'joker']
        non_joker_cards = [card for card in game.deck.cards if card.rank != 'joker']
        
        custom_log(f"Separated {len(joker_cards)} jokers from {len(non_joker_cards)} non-joker cards", 
                   level="INFO", isOn=LOGGING_SWITCH)
        
        # Step 2: Deal 4 cards to each player from non-joker cards only
        # Create a temporary deck with only non-joker cards
        game.deck.cards = non_joker_cards.copy()
        
        for player in game.players.values():
            for _ in range(4):
                card = game.deck.draw_card()
                if card:
                    player.add_card_to_hand(card)
        
        # Step 3: Combine remaining cards with jokers
        remaining_cards = game.deck.cards + joker_cards
        
        # Step 4: Shuffle the combined deck
        import random
        random.shuffle(remaining_cards)
        
        # Update the deck with shuffled cards (including jokers)
        game.deck.cards = remaining_cards
        
        custom_log(f"Card dealing complete. {len(remaining_cards)} cards remaining (including {len(joker_cards)} jokers)", 
                   level="INFO", isOn=LOGGING_SWITCH)
    
    def _deal_predefined_cards(self, game: GameState, predefined_hands: dict):
        """Deal predefined cards to players for testing"""
        
        # Get all cards from deck for matching
        all_cards = game.deck.cards.copy()
        
        # Separate jokers for later
        joker_cards = [card for card in all_cards if card.rank == 'joker']
        non_joker_cards = [card for card in all_cards if card.rank != 'joker']
        
        player_list = list(game.players.values())
        
        for player_idx, player in enumerate(player_list):
            player_key = f"player_{player_idx}"
            
            if player_key in predefined_hands:
                # Deal predefined cards for this player
                for card_spec in predefined_hands[player_key]:
                    # Find matching card in deck
                    matching_card = next(
                        (card for card in non_joker_cards 
                         if card.rank == card_spec['rank'] and card.suit == card_spec['suit']),
                        None
                    )
                    
                    if matching_card:
                        non_joker_cards.remove(matching_card)
                        player.add_card_to_hand(matching_card)
                        custom_log(f"Dealt predefined card {matching_card.rank} of {matching_card.suit} to {player.name}", level="INFO", isOn=LOGGING_SWITCH)
                    else:
                        custom_log(f"Warning: Could not find card {card_spec['rank']} of {card_spec['suit']}", level="WARNING", isOn=LOGGING_SWITCH)
            else:
                # No predefined hand for this player, deal random cards
                for _ in range(4):
                    if non_joker_cards:
                        card = non_joker_cards.pop(0)
                        player.add_card_to_hand(card)
        
        # Combine remaining cards with jokers and shuffle
        remaining_cards = non_joker_cards + joker_cards
        import random
        random.shuffle(remaining_cards)
        game.deck.cards = remaining_cards
        
        custom_log(f"Predefined card dealing complete. {len(remaining_cards)} cards remaining", 
                  level="INFO", isOn=LOGGING_SWITCH)
        
        # Store initial discard card spec for later use in _setup_piles
        # This will be used when setting up the discard pile
        from ..utils.predefined_hands_loader import PredefinedHandsLoader
        hands_loader = PredefinedHandsLoader()
        config = hands_loader.load_config()
        if config.get('enabled') and 'initial_discard' in config:
            game._predefined_initial_discard = config['initial_discard']
            custom_log(f"Stored predefined initial discard card: {config['initial_discard']}", level="INFO", isOn=LOGGING_SWITCH)
    
    def _setup_piles(self, game: GameState):
        """Set up draw and discard piles - moved from GameActions"""
        try:
            # Move remaining cards to draw pile
            game.draw_pile = game.deck.cards.copy()
            game.deck.cards = []
            
            # Check if there's a predefined initial discard card
            if hasattr(game, '_predefined_initial_discard') and game._predefined_initial_discard:
                discard_spec = game._predefined_initial_discard
                # Find the matching card in the draw pile
                matching_card = next(
                    (card for card in game.draw_pile 
                     if card.rank == discard_spec['rank'] and card.suit == discard_spec['suit']),
                    None
                )
                
                if matching_card:
                    game.draw_pile.remove(matching_card)
                    game.discard_pile.append(matching_card)
                    custom_log(f"Using predefined initial discard card: {matching_card.rank} of {matching_card.suit}", level="INFO", isOn=LOGGING_SWITCH)
                else:
                    custom_log(f"Warning: Could not find predefined discard card {discard_spec['rank']} of {discard_spec['suit']}, using random card", level="WARNING", isOn=LOGGING_SWITCH)
                    # Fall back to random card
                    if game.draw_pile:
                        first_card = game.draw_pile.pop(0)
                        game.discard_pile.append(first_card)
                
                # Clean up the temporary attribute
                delattr(game, '_predefined_initial_discard')
            else:
                # Start discard pile with first card from draw pile (normal behavior)
                if game.draw_pile:
                    first_card = game.draw_pile.pop(0)
                    game.discard_pile.append(first_card)
                else:
                    custom_log("Warning: No cards in draw pile after dealing", level="WARNING", isOn=LOGGING_SWITCH)
            
            custom_log(f"Setup piles: {len(game.draw_pile)} cards in draw pile, {len(game.discard_pile)} cards in discard pile", level="INFO", isOn=LOGGING_SWITCH)
            
            # Trigger change detection for both piles
            if hasattr(game, '_track_change'):
                game._track_change('draw_pile')
                game._track_change('discard_pile')
                game._send_changes_if_needed()
                
        except Exception as e:
            custom_log(f"Error in _setup_piles: {e}", level="ERROR", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"Traceback: {traceback.format_exc()}", level="ERROR", isOn=LOGGING_SWITCH)





    def _to_flutter_card(self, card, full_data: bool = False) -> Dict[str, Any]:
        """Convert card to Flutter format
        
        Args:
            card: Card object to convert
            full_data: If True, send full card data. If False, send ID-only data (face-down)
        """
        # Debug: Check if card is actually a Card object
        if not isinstance(card, Card):
            custom_log(f"WARNING: _to_flutter_card called with non-Card object: {type(card)} - {card}", isOn=LOGGING_SWITCH)
            return {
                'cardId': str(card) if card else 'unknown',
                'suit': '?',
                'rank': '?',
                'points': 0,
                'displayName': f'Invalid Card: {card}',
                'color': 'black',
            }
        if not full_data:
            # Send ID-only data (face-down card)
            return {
                'cardId': card.card_id,
                'suit': '?',
                'rank': '?',
                'points': 0,
                'displayName': f'Card {card.card_id}',
                'color': 'black',
            }
        
        # Send full card data (face-up card)
        rank_mapping = {
            '2': 'two', '3': 'three', '4': 'four', '5': 'five',
            '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten'
        }
        
        # Handle None values for incomplete cards
        suit = card.suit or '?'
        rank = card.rank or '?'
        points = card.points or 0
        
        return {
            'cardId': card.card_id,
            'suit': suit,
            'rank': rank_mapping.get(rank, rank) if rank != '?' else '?',
            'points': points,
            'displayName': str(card),
            'color': 'red' if suit in ['hearts', 'diamonds'] else 'black',
        }

    def _to_flutter_known_cards(self, known_cards: Dict[str, Any]) -> Dict[str, Any]:
        """Convert known_cards to Flutter format with ID-only data
        
        Args:
            known_cards: Dict with player_id as key and card data as value
            
        Returns:
            Dict with player_id as key and simplified card data as value
        """
        result = {}
        for player_id, card_data in known_cards.items():
            if isinstance(card_data, dict) and 'card1' in card_data and 'card2' in card_data:
                # Convert card data to ID-only format
                result[player_id] = {
                    'card1': card_data['card1']['card_id'] if card_data['card1'] and 'card_id' in card_data['card1'] else None,
                    'card2': card_data['card2']['card_id'] if card_data['card2'] and 'card_id' in card_data['card2'] else None,
                }
            else:
                # Handle unexpected data structure
                result[player_id] = {
                    'card1': None,
                    'card2': None,
                }
        return result

    def _to_flutter_player_data(self, player, is_current: bool = False) -> Dict[str, Any]:
        """
        Convert player to Flutter format - SINGLE SOURCE OF TRUTH for player data structure
        
        This method structures ALL player data that will be sent to the frontend.
        The structure MUST match the Flutter frontend schema exactly.
        """
        # Debug: Check player data types
        custom_log(f"DEBUG: Processing player {player.player_id} - hand length: {len(player.hand)}", isOn=LOGGING_SWITCH)
        for i, card in enumerate(player.hand):
            if card is not None:
                custom_log(f"DEBUG: Hand[{i}] type: {type(card)}, is Card: {isinstance(card, Card)}", isOn=LOGGING_SWITCH)
                if not isinstance(card, Card):
                    custom_log(f"DEBUG: WARNING - Hand[{i}] is not a Card object: {card}", isOn=LOGGING_SWITCH)
        
        return {
            'id': player.player_id,
            'name': player.name,
            'type': 'human' if player.player_type.value == 'human' else 'computer',
            'hand': [self._to_flutter_card(c, full_data=False) if c is not None and isinstance(c, Card) else None for c in player.hand],  # Send face-down cards with safety check
            'visibleCards': [self._to_flutter_card(c, full_data=True) for c in player.visible_cards if c is not None and isinstance(c, Card)],  # Send face-up cards with safety check
            'cardsToPeek': [self._to_flutter_card(c, full_data=True) for c in player.cards_to_peek if c is not None and isinstance(c, Card)],  # Send face-up cards with safety check
            'score': int(player.calculate_points()),
            'status': player.status.value,  # Use the player's actual status
            'isCurrentPlayer': is_current,
            'hasCalledRecall': bool(player.has_called_recall),
            'drawnCard': self._to_flutter_card(player.drawn_card, full_data=True) if player.drawn_card and isinstance(player.drawn_card, Card) else None,  # Send face-up drawn card with safety check
            'known_cards': self._to_flutter_known_cards(player.known_cards),  # Send known cards with ID-only data
            'collection_rank': player.collection_rank,  # Send player's collection rank string
            'collection_rank_cards': [self._to_flutter_card(card, full_data=True) for card in player.collection_rank_cards if card is not None and isinstance(card, Card)],  # Send collection rank cards with full data
        }

    def _to_flutter_game_data(self, game: GameState) -> Dict[str, Any]:
        """
        Convert game state to Flutter format - SINGLE SOURCE OF TRUTH for game data structure
        
        This method structures ALL game data that will be sent to the frontend.
        The structure MUST match the Flutter frontend schema exactly.
        """
        # DEBUG: Log the phase being sent directly
        import traceback
        original_phase = game.phase.value
        custom_log(f"🔍 _to_flutter_game_data DEBUG:", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"🔍   Called from: {traceback.format_stack()[-2].strip()}", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"🔍   Game ID: {game.game_id}", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"🔍   Phase being sent directly: {original_phase}", level="INFO", isOn=LOGGING_SWITCH)
        
        # Get current player data
        current_player = None
        if game.current_player_id and game.current_player_id in game.players:
            current_player = self._to_flutter_player_data(game.players[game.current_player_id], True)
        else:
            pass

        # Build complete game data structure matching Flutter schema
        game_data = {
            # Core game identification
            'gameId': game.game_id,
            'gameName': f"Recall Game {game.game_id}",
            
            # Player information
            # TODO: Implement player-specific data filtering to prevent sending sensitive data (hand, cardsToPeek, drawnCard) to other players
            # Currently sending ALL player data to ALL players - this is a security/privacy issue
            'players': [self._to_flutter_player_data(player, pid == game.current_player_id) for pid, player in game.players.items()],
            'currentPlayer': current_player,
            'playerCount': len(game.players),
            'maxPlayers': game.max_players,
            'minPlayers': game.min_players,
            'activePlayerCount': len([p for p in game.players.values() if p.is_active]),
            
            # Game state and phase - send phase value directly without mapping
            'phase': game.phase.value,
            'status': 'active' if game.phase.value in ['player_turn', 'same_rank_window', 'ending_round', 'ending_turn', 'recall_called'] else 'inactive',
            
            # Card piles
            'drawPile': [self._to_flutter_card(card, full_data=False) for card in game.draw_pile if card is not None and isinstance(card, Card)],  # Send face-down cards with safety check
            'discardPile': [self._to_flutter_card(card, full_data=True) for card in game.discard_pile if card is not None and isinstance(card, Card)],  # Send face-up cards with safety check
            
            # Game timing
            'gameStartTime': datetime.fromtimestamp(game.game_start_time).isoformat() if game.game_start_time and isinstance(game.game_start_time, (int, float)) else (game.game_start_time.isoformat() if hasattr(game.game_start_time, 'isoformat') else None),
            'lastActivityTime': datetime.fromtimestamp(game.last_action_time).isoformat() if game.last_action_time and isinstance(game.last_action_time, (int, float)) else (game.last_action_time.isoformat() if hasattr(game.last_action_time, 'isoformat') else None),
            
            # Game completion
            'winner': game.winner,
            'gameEnded': game.game_ended,
            
            # Room settings
            'permission': game.permission,  # Include room permission
            
            # Additional game metadata
            'recallCalledBy': game.recall_called_by,
            'lastPlayedCard': self._to_flutter_card(game.last_played_card, full_data=True) if game.last_played_card and isinstance(game.last_played_card, Card) else None,  # Send face-up last played card with safety check
            'outOfTurnDeadline': game.out_of_turn_deadline,
            'outOfTurnTimeoutSeconds': game.out_of_turn_timeout_seconds,
        }
        
        # DEBUG: Log the final game data being sent
        custom_log(f"🔍 Final game data being sent to Flutter:", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"🔍   gameId: {game_data['gameId']}", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"🔍   phase: {game_data['phase']}", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"🔍   status: {game_data['status']}", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"🔍   playerCount: {game_data['playerCount']}", level="INFO", isOn=LOGGING_SWITCH)
        custom_log(f"🔍   currentPlayer: {game_data['currentPlayer']['id'] if game_data['currentPlayer'] else 'None'}", level="INFO", isOn=LOGGING_SWITCH)
        
        return game_data

    # ========= DEPRECATED METHODS - REMOVE AFTER MIGRATION =========
    

    def _to_flutter_player(self, player, is_current: bool = False) -> Dict[str, Any]:
        """
        DEPRECATED: Convert player to Flutter format
        This method will be removed after migration to _to_flutter_player_data
        """
        return self._to_flutter_player_data(player, is_current)

    def _to_flutter_game_state(self, game: GameState) -> Dict[str, Any]:
        """
        DEPRECATED: Convert game state to Flutter format
        This method will be removed after migration to _to_flutter_game_data
        """
        return self._to_flutter_game_data(game)

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
            
            # Register callback for room_joined hook
            self.app_manager.register_hook_callback('room_joined', self._on_room_joined)
            
            # Register callback for room_closed hook
            self.app_manager.register_hook_callback('room_closed', self._on_room_closed)
            
            # Register callback for leave_room hook
            self.app_manager.register_hook_callback('leave_room', self._on_leave_room)
            
        except Exception as e:
            pass
    
    def _on_room_created(self, room_data: Dict[str, Any]):
        """Callback for room_created hook - automatically create game"""
        try:
            room_id = room_data.get('room_id')
            max_players = room_data.get('max_players', 4)
            min_players = room_data.get('min_players', 2)
            permission = room_data.get('permission', 'public')  # Extract room permission
            
            # Create game with room_id as game_id and room permission
            game_id = self.create_game_with_id(room_id, max_players=max_players, min_players=min_players, permission=permission)
            
            # Initialize game state (waiting for players)
            game = self.get_game(game_id)
            if game:
                game.phase = GamePhase.WAITING_FOR_PLAYERS
            else:
                pass
        except Exception as e:
            pass
    
    def _on_room_joined(self, room_data: Dict[str, Any]):
        """Callback for room_joined hook - handle player joining existing game"""
        try:
            room_id = room_data.get('room_id')
            user_id = room_data.get('user_id')
            session_id = room_data.get('session_id')  # Get session_id from room_data
            current_size = room_data.get('current_size', 1)
            
            # Check if game exists for this room
            game = self.get_game(room_id)
            if not game:
                return
            
            # Add player to the game if they don't exist
            player_added = False
            if user_id not in game.players:
                # Create a human player for the user
                from ..models.player import HumanPlayer
                player = HumanPlayer(user_id, f"Player_{user_id[:8]}")
                game.add_player(player)
                player_added = True
            else:
                pass
            
            # Set up session mapping for the player
            if session_id and user_id:
                game.update_player_session(user_id, session_id)
            
            # Update room size in WebSocket manager (if player was newly added)
            if player_added:
                try:
                    from core.managers.websockets.websocket_manager import WebSocketManager
                    ws_manager = WebSocketManager.instance
                    if ws_manager:
                        ws_manager.update_room_size(room_id, 1)  # Increase room size by 1
                except Exception as e:
                    pass
            
            # Update game state based on player count
            if current_size >= game.min_players and game.phase == GamePhase.WAITING_FOR_PLAYERS:
                pass
            
            # Use the coordinator to send recall player joined events
            if hasattr(self, 'app_manager') and self.app_manager:
                coordinator = getattr(self.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    coordinator._send_recall_player_joined_events(room_id, user_id, session_id, game)
                else:
                    pass
            else:
                pass
            
        except Exception as e:
            import traceback
    
    def _on_room_closed(self, room_data: Dict[str, Any]):
        """Callback for room_closed hook - cleanup game when room is closed"""
        try:
            room_id = room_data.get('room_id')
            reason = room_data.get('reason', 'unknown')
            
            # Remove game if it exists
            if room_id in self.active_games:
                del self.active_games[room_id]
            else:
                pass
        except Exception as e:
            pass
    
    def _on_leave_room(self, room_data: Dict[str, Any]):
        """Callback for leave_room hook - handle player leaving game"""
        try:
            room_id = room_data.get('room_id')
            session_id = room_data.get('session_id')
            user_id = room_data.get('user_id')  # Get user_id from room_data
            
            # Check if game exists for this room
            game = self.get_game(room_id)
            if not game:
                return
            
            # Try to find player by session_id first
            player_id = None
            if session_id:
                player_id = game.get_session_player(session_id)
                if player_id:
                    pass
            
            # Fallback: try to find player by user_id if session lookup failed
            if not player_id and user_id:
                if user_id in game.players:
                    player_id = user_id
            
            # Remove player if found
            if player_id:
                game.remove_player(player_id)
                
                # Clean up session mapping
                if session_id:
                    game.remove_session(session_id)
                
                # Update room size in WebSocket manager
                try:
                    from core.managers.websockets.websocket_manager import WebSocketManager
                    ws_manager = WebSocketManager.instance
                    if ws_manager:
                        ws_manager.update_room_size(room_id, -1)  # Decrease room size by 1
                except Exception as e:
                    pass
            else:
                pass
            
        except Exception as e:
            pass