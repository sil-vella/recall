"""
Game State Models for Recall Game

This module defines the game state management system for the Recall card game,
including game phases, state transitions, and game logic.
"""

from typing import List, Dict, Any, Optional
from enum import Enum
from .card import Card, CardDeck
from ..utils.deck_factory import DeckFactory
from .player import Player, HumanPlayer, ComputerPlayer, PlayerType
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
    
    def add_player(self, player: Player) -> bool:
        """Add a player to the game"""
        if len(self.players) >= self.max_players:
            return False
        
        self.players[player.player_id] = player
        return True
    
    def remove_player(self, player_id: str) -> bool:
        """Remove a player from the game"""
        if player_id in self.players:
            del self.players[player_id]
            return True
        return False
    
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
            "winner": self.winner
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
        
        # Restore cards
        for card_data in data.get("discard_pile", []):
            card = Card.from_dict(card_data)
            game_state.discard_pile.append(card)
        
        if data.get("last_played_card"):
            game_state.last_played_card = Card.from_dict(data["last_played_card"])
        
        return game_state


class GameStateManager:
    """Manages multiple game states"""
    
    def __init__(self):
        self.active_games = {}  # game_id -> GameState
    
    def create_game(self, max_players: int = 4) -> str:
        """Create a new game"""
        game_id = str(uuid.uuid4())
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
    
    def cleanup_ended_games(self):
        """Remove games that have ended"""
        ended_games = []
        for game_id, game_state in self.active_games.items():
            if game_state.game_ended:
                ended_games.append(game_id)
        
        for game_id in ended_games:
            del self.active_games[game_id] 