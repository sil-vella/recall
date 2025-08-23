"""
Game State Models for Recall Game

This module defines the game state management system for the Recall card game,
including game phases, state transitions, game logic, and WebSocket communication.
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
    
    def __init__(self, game_id: str, max_players: int = 4):
        self.game_id = game_id
        self.max_players = max_players
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
    
    def start_game(self):
        """Start the game and deal cards"""
        if len(self.players) < 2:
            raise ValueError("Need at least 2 players to start")
        
        self.phase = GamePhase.DEALING_CARDS
        self.game_start_time = time.time()
        
        # Build deterministic deck from factory, then deal
        factory = DeckFactory(self.game_id)
        self.deck.cards = factory.build_deck(
            include_jokers=True,
            include_special_powers=True,
        )
        self._deal_cards()
        
        # Set up draw and discard piles
        self._setup_piles()
        # Allow initial 2 peeks per player (tracked on Player)
        
        # Set first player
        player_ids = list(self.players.keys())
        self.current_player_id = player_ids[0]
        
        self.phase = GamePhase.PLAYER_TURN
        self.last_action_time = time.time()
    
    def _deal_cards(self):
        """Deal 4 cards to each player"""
        for player in self.players.values():
            for _ in range(4):
                card = self.deck.draw_card()
                if card:
                    player.add_card_to_hand(card)
    
    def _setup_piles(self):
        """Set up draw and discard piles"""
        # Move remaining cards to draw pile
        self.draw_pile = self.deck.cards.copy()
        self.deck.cards = []
        
        # Start discard pile with first card from draw pile
        if self.draw_pile:
            first_card = self.draw_pile.pop(0)
            self.discard_pile.append(first_card)
    
    def get_current_player(self) -> Optional[Player]:
        """Get the current player"""
        return self.players.get(self.current_player_id)
    
    def next_player(self):
        """Move to the next player"""
        if not self.current_player_id:
            return
        
        player_ids = list(self.players.keys())
        current_index = player_ids.index(self.current_player_id)
        next_index = (current_index + 1) % len(player_ids)
        self.current_player_id = player_ids[next_index]
    
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
    
    def play_card(self, player_id: str, card_id: str) -> Dict[str, Any]:
        """Play a card from a player's hand"""
        if self.phase != GamePhase.PLAYER_TURN:
            return {"error": "Not player's turn"}
        
        if player_id != self.current_player_id:
            return {"error": "Not your turn"}
        
        player = self.players.get(player_id)
        if not player:
            return {"error": "Player not found"}
        
        # New turn begins; previous out-of-turn window closes
        self.out_of_turn_deadline = None

        # Remove card from hand
        card = player.remove_card_from_hand(card_id)
        if not card:
            return {"error": "Card not found in hand"}
        
        # Add to discard pile
        self.discard_pile.append(card)
        self.last_played_card = card
        self.last_action_time = time.time()
        # Open out-of-turn window
        self.out_of_turn_deadline = self.last_action_time + self.out_of_turn_timeout_seconds
        
        # Check for special powers
        special_effect = self._handle_special_power(card, player)
        
        # Check if player emptied hand
        if len(player.hand) == 0:
            # Immediate end condition
            return self._end_game_with_scoring(reason="player_empty_hand", last_player_id=player_id)

        # Check for Recall opportunity
        recall_opportunity = self._check_recall_opportunity(player)
        
        # Move to next player
        self.next_player()
        
        return {
            "success": True,
            "card_played": card.to_dict(),
            "special_effect": special_effect,
            "recall_opportunity": recall_opportunity,
            "next_player": self.current_player_id
        }
    
    def play_out_of_turn(self, player_id: str, card_id: str) -> Dict[str, Any]:
        """Play a card out of turn (same rank)"""
        if not self.last_played_card:
            return {"error": "No card to match"}
        # Check time window
        if self.out_of_turn_deadline is None or time.time() > self.out_of_turn_deadline:
            return {"error": "Out-of-turn window closed"}
        
        player = self.players.get(player_id)
        if not player:
            return {"error": "Player not found"}
        
        # Check if player has matching card
        matching_cards = player.can_play_out_of_turn(self.last_played_card)
        card_to_play = None
        
        for card in matching_cards:
            if card.card_id == card_id:
                card_to_play = card
                break
        
        if not card_to_play:
            return {"error": "Card cannot be played out of turn"}
        
        # Remove card from hand
        player.remove_card_from_hand(card_id)
        
        # Add to discard pile
        self.discard_pile.append(card_to_play)
        self.last_played_card = card_to_play
        self.last_action_time = time.time()
        # Extend out-of-turn window for possible chains
        self.out_of_turn_deadline = self.last_action_time + self.out_of_turn_timeout_seconds
        
        # Check for special powers
        special_effect = self._handle_special_power(card_to_play, player)
        
        return {
            "success": True,
            "card_played": card_to_play.to_dict(),
            "special_effect": special_effect,
            "played_out_of_turn": True
        }

    def draw_from_deck(self, player_id: str) -> Dict[str, Any]:
        """Draw the top card and hold in pending until placement decision."""
        if player_id != self.current_player_id:
            return {"error": "Not your turn"}
        if not self.draw_pile:
            return {"error": "Draw pile empty"}
        card = self.draw_pile.pop(0)
        self.pending_draws[player_id] = card
        self.last_action_time = time.time()
        return {"success": True, "drawn_card": card.to_dict(), "pending": True}

    def take_from_discard(self, player_id: str) -> Dict[str, Any]:
        """Take the top discard into pending for the current player."""
        if player_id != self.current_player_id:
            return {"error": "Not your turn"}
        if not self.discard_pile:
            return {"error": "Discard pile empty"}
        card = self.discard_pile.pop()  # top of discard is the end
        self.pending_draws[player_id] = card
        self.last_action_time = time.time()
        return {"success": True, "taken_card": card.to_dict(), "pending": True}

    def place_drawn_card_replace(self, player_id: str, replace_card_id: str) -> Dict[str, Any]:
        """Place pending drawn card by replacing a hand card; replaced card goes to discard."""
        if player_id != self.current_player_id:
            return {"error": "Not your turn"}
        if player_id not in self.pending_draws:
            return {"error": "No pending drawn card"}
        player = self.players.get(player_id)
        if not player:
            return {"error": "Player not found"}
        replaced = player.remove_card_from_hand(replace_card_id)
        if not replaced:
            return {"error": "Replace target not in hand"}
        # Add pending as face down (not visible)
        pending = self.pending_draws.pop(player_id)
        player.add_card_to_hand(pending)
        # Replaced goes to discard
        self.discard_pile.append(replaced)
        self.last_played_card = replaced
        self.last_action_time = time.time()
        # Do not advance turn here; turn advances when player explicitly plays
        return {"success": True, "placed": pending.to_dict(), "discarded": replaced.to_dict()}

    def place_drawn_card_play(self, player_id: str) -> Dict[str, Any]:
        """Play the pending drawn card directly to discard."""
        if player_id != self.current_player_id:
            return {"error": "Not your turn"}
        if player_id not in self.pending_draws:
            return {"error": "No pending drawn card"}
        card = self.pending_draws.pop(player_id)
        self.discard_pile.append(card)
        self.last_played_card = card
        self.last_action_time = time.time()
        # Open out-of-turn window
        self.out_of_turn_deadline = self.last_action_time + self.out_of_turn_timeout_seconds
        special_effect = self._handle_special_power(card, self.players[player_id])
        # If player now has zero cards, end immediately
        player = self.players.get(player_id)
        if player and len(player.hand) == 0:
            return self._end_game_with_scoring(reason="player_empty_hand", last_player_id=player_id)
        self.next_player()
        return {"success": True, "card_played": card.to_dict(), "special_effect": special_effect}

    def initial_peek(self, player_id: str, indices: List[int]) -> Dict[str, Any]:
        """Allow player to peek at up to remaining initial cards at game start."""
        player = self.players.get(player_id)
        if not player:
            return {"error": "Player not found"}
        if player.initial_peeks_remaining <= 0:
            return {"error": "No initial peeks remaining"}
        # Cap by remaining
        to_peek = min(len(indices), player.initial_peeks_remaining)
        revealed = []
        for i in range(to_peek):
            idx = int(indices[i])
            card = player.look_at_card_by_index(idx)
            if card:
                revealed.append({"index": idx, "card": card.to_dict()})
        player.initial_peeks_remaining -= to_peek
        return {"success": True, "revealed": revealed, "remaining": player.initial_peeks_remaining}
    
    def call_recall(self, player_id: str) -> Dict[str, Any]:
        """Player calls Recall to end the game"""
        if self.phase == GamePhase.RECALL_CALLED:
            return {"error": "Recall already called"}
        
        player = self.players.get(player_id)
        if not player:
            return {"error": "Player not found"}
        
        player.call_recall()
        self.recall_called_by = player_id
        self.phase = GamePhase.RECALL_CALLED
        self.last_action_time = time.time()
        
        return {
            "success": True,
            "recall_called_by": player_id,
            "phase": self.phase.value
        }
    
    def end_game(self) -> Dict[str, Any]:
        """End the game and determine winner"""
        # Allow scoring at recall or immediate end
        if self.phase not in (GamePhase.RECALL_CALLED, GamePhase.GAME_ENDED, GamePhase.PLAYER_TURN, GamePhase.OUT_OF_TURN_PLAY):
            return {"error": "Invalid phase for ending game"}
        return self._end_game_with_scoring()

    def _end_game_with_scoring(self, reason: str = "", last_player_id: Optional[str] = None) -> Dict[str, Any]:
        """Compute scores and end game with tie-break rules."""
        final_scores: Dict[str, Any] = {}
        for p in self.players.values():
            final_scores[p.player_id] = {
                "player_id": p.player_id,
                "name": p.name,
                "points": p.calculate_points(),
                "cards_remaining": len(p.hand),
                "called_recall": p.has_called_recall
            }
        winner = self._determine_winner(final_scores)
        self.winner = winner
        self.phase = GamePhase.GAME_ENDED
        self.game_ended = True
        return {
            "success": True,
            "winner": winner,
            "final_scores": final_scores,
            "phase": self.phase.value,
            "reason": reason
        }
    
    def _determine_winner(self, final_scores: Dict[str, Any]) -> str:
        """Determine the winner based on game rules"""
        # Find player with lowest points
        lowest_points = float('inf')
        lowest_point_players = []
        
        for player_id, score in final_scores.items():
            points = score["points"]
            if points < lowest_points:
                lowest_points = points
                lowest_point_players = [player_id]
            elif points == lowest_points:
                lowest_point_players.append(player_id)
        
        # If multiple players have same points, check cards remaining
        if len(lowest_point_players) > 1:
            lowest_cards = float('inf')
            lowest_card_players = []
            
            for player_id in lowest_point_players:
                cards = final_scores[player_id]["cards_remaining"]
                if cards < lowest_cards:
                    lowest_cards = cards
                    lowest_card_players = [player_id]
                elif cards == lowest_cards:
                    lowest_card_players.append(player_id)
            
            # If still tied, check who called Recall
            for player_id in lowest_card_players:
                if final_scores[player_id]["called_recall"]:
                    return player_id
            
            # If no one called Recall, it's a tie
            return lowest_card_players[0] if lowest_card_players else None
        
        return lowest_point_players[0] if lowest_point_players else None
    
    def _handle_special_power(self, card: Card, player: Player) -> Optional[Dict[str, Any]]:
        """Handle special power card effects"""
        if not card.has_special_power():
            return None
        
        power = card.special_power
        
        if power == "peek_at_card":
            return {
                "type": "peek_at_card",
                "description": "Look at any one card (own or other player's)",
                "requires_target": True
            }
        elif power == "switch_cards":
            return {
                "type": "switch_cards",
                "description": "Switch any two playing cards of any player",
                "requires_target": True
            }
        elif power == "steal_card":
            return {
                "type": "steal_card",
                "description": "Steal a card from another player's hand",
                "requires_target": True
            }
        
        return None
    
    def _check_recall_opportunity(self, player: Player) -> bool:
        """Check if player can call Recall"""
        return not player.has_called_recall and self.phase != GamePhase.RECALL_CALLED
    
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
                custom_log("❌ WebSocket manager not available for GameStateManager", level="ERROR")
                return False
            self._initialized = True
            custom_log("✅ GameStateManager initialized with WebSocket support")
            return True
        except Exception as e:
            custom_log(f"❌ Failed to initialize GameStateManager: {e}", level="ERROR")
            return False
    
    def create_game(self, max_players: int = 4) -> str:
        """Create a new game"""
        game_id = str(uuid.uuid4())
        game_state = GameState(game_id, max_players)
        self.active_games[game_id] = game_state
        return game_id
    
    def create_game_with_id(self, game_id: str, max_players: int = 4) -> str:
        """Create a new game using a provided identifier (e.g., room_id).

        This aligns backend game identity with the room identifier used by the
        frontend so join/start flows can address the same id across the stack.
        If a game with this id already exists, it is returned unchanged.
        """
        # If already exists, no-op
        existing = self.active_games.get(game_id)
        if existing is not None:
            return game_id
        game_state = GameState(game_id, max_players)
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
    
    # ========= WebSocket Event Handlers =========
    
    def on_join_game(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle player joining a game"""
        try:
            game_id = data.get('game_id')
            player_name = data.get('player_name') or 'Player'
            player_type = data.get('player_type') or 'human'
            max_players = data.get('max_players', 4)

            # Create game if it doesn't exist
            if not game_id:
                game_id = self.create_game(max_players=max_players)
            else:
                game = self.get_game(game_id)
                if not game:
                    self.create_game_with_id(game_id, max_players=max_players)

            game = self.get_game(game_id)
            if not game:
                self._send_error(session_id, f'Game not found: {game_id}')
                return False

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
        """Handle player actions"""
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

            # Build action data for game engine
            action_data = {
                'action_type': action,
                'player_id': user_id,
                'game_id': game_id,
                'card_id': (data.get('card') or {}).get('card_id') or (data.get('card') or {}).get('id'),
                'replace_card_id': (data.get('replace_card') or {}).get('card_id') or data.get('replace_card_id'),
                'replace_index': data.get('replaceIndex'),
                'power_data': data.get('power_data'),
            }

            # Process action through game engine
            engine_result = self.game_logic_engine.process_player_action(game, action_data)

            # Fallback for actions not in engine
            if not engine_result or engine_result.get('error'):
                engine_result = self._fallback_handle(game, action, user_id, data)

            if engine_result.get('error'):
                self._send_action_result(game_id, user_id, engine_result)
                return False
            
            # Send results and updates
            self._send_action_result(game_id, user_id, engine_result)
            self._broadcast_game_action(game_id, action, {'action_type': action, 'player_id': user_id, 'result': engine_result}, user_id)
            self._send_game_state_update(game_id)
            
            return True
        except Exception as e:
            custom_log(f"Error in on_player_action: {e}", level="ERROR")
            self._send_error(session_id, f'Player action failed: {str(e)}')
            return False

    def on_start_match(self, session_id: str, data: Dict[str, Any]) -> bool:
        """Handle game start"""
        try:
            game_id = data.get('game_id') or data.get('room_id')
            if not game_id:
                self._send_error(session_id, 'Missing game_id')
                return False
                
            game = self.get_game(game_id)
            if not game:
                self._send_error(session_id, f'Game not found: {game_id}')
                return False

            session_data = self.websocket_manager.get_session_data(session_id) or {}
            user_id = str(session_data.get('user_id') or session_id)
            
            # Process start_match through game engine
            action_data = {
                'action_type': 'start_match',
                'player_id': user_id,
                'game_id': game_id,
            }
            
            engine_result = self.game_logic_engine.process_player_action(game, action_data)
            
            if engine_result.get('error'):
                self._send_error(session_id, f"Start match failed: {engine_result['error']}")
                return False
            
            # Process notifications from engine
            for notification in engine_result.get('notifications', []):
                event = notification.get('event')
                event_data = notification.get('data', {})
                
                if event == 'game_started':
                    payload = {
                        'event_type': event,
                        'game_id': game_id,
                        'game_state': self._to_flutter_game_state(game),
                        **event_data
                    }
                    self._send_to_all_players(game_id, event, payload)
                elif event == 'turn_started':
                    target_player_id = event_data.get('player_id')
                    if target_player_id:
                        payload = {
                            'event_type': event,
                            'game_id': game_id,
                            'game_state': self._to_flutter_game_state(game),
                            **event_data
                        }
                        self._send_to_player(game_id, target_player_id, event, payload)
            
            return True
        except Exception as e:
            custom_log(f"Error in on_start_match: {e}", level="ERROR")
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

    def _fallback_handle(self, game, action: str, user_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Fallback handler for actions not in game engine"""
        if action == 'draw_from_deck':
            return game.draw_from_deck(user_id)
        if action == 'take_from_discard':
            return game.take_from_discard(user_id)
        if action in ('place_drawn_replace', 'place_drawn_card_replace'):
            replace_id = (data.get('replace_card') or {}).get('card_id') or data.get('replace_card_id')
            if not replace_id:
                return {'error': 'Missing replace target'}
            return game.place_drawn_card_replace(user_id, replace_id)
        if action in ('place_drawn_play', 'place_drawn_card_play'):
            return game.place_drawn_card_play(user_id)
        if action == 'play_card':
            card_id = (data.get('card') or {}).get('card_id') or (data.get('card') or {}).get('id')
            if not card_id:
                return {'error': 'Missing card_id'}
            return game.play_card(user_id, card_id)
        if action == 'call_recall':
            return game.call_recall(user_id)
        return {'error': 'Unsupported action'}

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
            'status': 'playing' if is_current else 'ready',
            'isCurrentPlayer': is_current,
            'hasCalledRecall': bool(player.has_called_recall),
        }

    def _to_flutter_game_state(self, game: GameState) -> Dict[str, Any]:
        """Convert game state to Flutter format"""
        phase_mapping = {
            'waiting_for_players': 'waiting',
            'dealing_cards': 'setup',
            'player_turn': 'playing',
            'out_of_turn_play': 'playing',
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
            'activePlayerCount': len([p for p in game.players.values() if p.is_active]),
        }

    def cleanup_ended_games(self):
        """Remove games that have ended"""
        ended_games = []
        for game_id, game_state in self.active_games.items():
            if game_state.game_ended:
                ended_games.append(game_id)
        
        for game_id in ended_games:
            del self.active_games[game_id]
    
 