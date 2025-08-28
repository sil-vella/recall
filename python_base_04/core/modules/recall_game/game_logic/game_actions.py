"""
Game Actions for Recall Game

This module handles all game actions and logic during gameplay,
including card playing, drawing, special powers, and turn management.
"""

from typing import List, Dict, Any, Optional
from datetime import datetime
import time
from ..models.card import Card
from ..models.player import Player, PlayerStatus
from .game_state import GameState, GamePhase
from tools.logger.custom_logging import custom_log


class GameActions:
    """Handles all game actions and logic during gameplay"""
    
    def __init__(self, game_state: GameState):
        self.game_state = game_state
    
    def play_card(self, player_id: str, card_id: str) -> Dict[str, Any]:
        """Play a card from a player's hand"""
        if self.game_state.phase != GamePhase.PLAYER_TURN:
            return {"error": "Not player's turn"}
        
        if player_id != self.game_state.current_player_id:
            return {"error": "Not your turn"}
        
        player = self.game_state.players.get(player_id)
        if not player:
            return {"error": "Player not found"}
        
        # New turn begins; previous out-of-turn window closes
        self.game_state.out_of_turn_deadline = None

        # Remove card from hand
        card = player.remove_card_from_hand(card_id)
        if not card:
            return {"error": "Card not found in hand"}
        
        # Add to discard pile
        self.game_state.discard_pile.append(card)
        self.game_state.last_played_card = card
        self.game_state.last_action_time = time.time()
        
        # Open out-of-turn window
        self.game_state.out_of_turn_deadline = self.game_state.last_action_time + self.game_state.out_of_turn_timeout_seconds
        
        # Check for special powers
        special_effect = self._handle_special_power(card, player)
        
        # Check if player emptied hand
        if len(player.hand) == 0:
            # Immediate end condition
            return self._end_game_with_scoring(reason="player_empty_hand", last_player_id=player_id)

        # Check for Recall opportunity
        recall_opportunity = self._check_recall_opportunity(player)
        
        # Move to next player
        self._next_player()
        
        return {
            "success": True,
            "card_played": card.to_dict(),
            "special_effect": special_effect,
            "recall_opportunity": recall_opportunity,
            "next_player": self.game_state.current_player_id
        }
    
    def play_out_of_turn(self, player_id: str, card_id: str) -> Dict[str, Any]:
        """Play a card out of turn (same rank)"""
        if not self.game_state.last_played_card:
            return {"error": "No card to match"}
        
        # Check time window
        if self.game_state.out_of_turn_deadline is None or time.time() > self.game_state.out_of_turn_deadline:
            return {"error": "Out-of-turn window closed"}
        
        player = self.game_state.players.get(player_id)
        if not player:
            return {"error": "Player not found"}
        
        # Check if player has matching card
        matching_cards = player.can_play_out_of_turn(self.game_state.last_played_card)
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
        self.game_state.discard_pile.append(card_to_play)
        self.game_state.last_played_card = card_to_play
        self.game_state.last_action_time = time.time()
        
        # Extend out-of-turn window for possible chains
        self.game_state.out_of_turn_deadline = self.game_state.last_action_time + self.game_state.out_of_turn_timeout_seconds
        
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
        if player_id != self.game_state.current_player_id:
            return {"error": "Not your turn"}
        if not self.game_state.draw_pile:
            return {"error": "Draw pile empty"}
        
        card = self.game_state.draw_pile.pop(0)
        self.game_state.pending_draws[player_id] = card
        self.game_state.last_action_time = time.time()
        
        return {"success": True, "drawn_card": card.to_dict(), "pending": True}

    def take_from_discard(self, player_id: str) -> Dict[str, Any]:
        """Take the top discard into pending for the current player."""
        if player_id != self.game_state.current_player_id:
            return {"error": "Not your turn"}
        if not self.game_state.discard_pile:
            return {"error": "Discard pile empty"}
        
        card = self.game_state.discard_pile.pop()  # top of discard is the end
        self.game_state.pending_draws[player_id] = card
        self.game_state.last_action_time = time.time()
        
        return {"success": True, "taken_card": card.to_dict(), "pending": True}

    def place_drawn_card_replace(self, player_id: str, replace_card_id: str) -> Dict[str, Any]:
        """Place pending drawn card by replacing a hand card; replaced card goes to discard."""
        if player_id != self.game_state.current_player_id:
            return {"error": "Not your turn"}
        if player_id not in self.game_state.pending_draws:
            return {"error": "No pending drawn card"}
        
        player = self.game_state.players.get(player_id)
        if not player:
            return {"error": "Player not found"}
        
        replaced = player.remove_card_from_hand(replace_card_id)
        if not replaced:
            return {"error": "Replace target not in hand"}
        
        # Add pending as face down (not visible)
        pending = self.game_state.pending_draws.pop(player_id)
        player.add_card_to_hand(pending)
        
        # Replaced goes to discard
        self.game_state.discard_pile.append(replaced)
        self.game_state.last_played_card = replaced
        self.game_state.last_action_time = time.time()
        
        # Do not advance turn here; turn advances when player explicitly plays
        return {"success": True, "placed": pending.to_dict(), "discarded": replaced.to_dict()}

    def place_drawn_card_play(self, player_id: str) -> Dict[str, Any]:
        """Play the pending drawn card directly to discard."""
        if player_id != self.game_state.current_player_id:
            return {"error": "Not your turn"}
        if player_id not in self.game_state.pending_draws:
            return {"error": "No pending drawn card"}
        
        card = self.game_state.pending_draws.pop(player_id)
        self.game_state.discard_pile.append(card)
        self.game_state.last_played_card = card
        self.game_state.last_action_time = time.time()
        
        # Open out-of-turn window
        self.game_state.out_of_turn_deadline = self.game_state.last_action_time + self.game_state.out_of_turn_timeout_seconds
        
        special_effect = self._handle_special_power(card, self.game_state.players[player_id])
        
        # If player now has zero cards, end immediately
        player = self.game_state.players.get(player_id)
        if player and len(player.hand) == 0:
            return self._end_game_with_scoring(reason="player_empty_hand", last_player_id=player_id)
        
        self._next_player()
        return {"success": True, "card_played": card.to_dict(), "special_effect": special_effect}

    def initial_peek(self, player_id: str, indices: List[int]) -> Dict[str, Any]:
        """Allow player to peek at up to remaining initial cards at game start."""
        player = self.game_state.players.get(player_id)
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
        if self.game_state.phase == GamePhase.RECALL_CALLED:
            return {"error": "Recall already called"}
        
        player = self.game_state.players.get(player_id)
        if not player:
            return {"error": "Player not found"}
        
        player.call_recall()
        self.game_state.recall_called_by = player_id
        self.game_state.phase = GamePhase.RECALL_CALLED
        self.game_state.last_action_time = time.time()
        
        return {
            "success": True,
            "recall_called_by": player_id,
            "phase": self.game_state.phase.value
        }
    
    def end_game(self) -> Dict[str, Any]:
        """End the game and determine winner"""
        # Allow scoring at recall or immediate end
        if self.game_state.phase not in (GamePhase.RECALL_CALLED, GamePhase.GAME_ENDED, GamePhase.PLAYER_TURN, GamePhase.OUT_OF_TURN_PLAY):
            return {"error": "Invalid phase for ending game"}
        return self._end_game_with_scoring()

    def start_game(self) -> Dict[str, Any]:
        """Start the game and deal cards"""
        if len(self.game_state.players) < 2:
            return {"error": "Need at least 2 players to start"}
        
        self.game_state.phase = GamePhase.DEALING_CARDS
        self.game_state.game_start_time = time.time()
        
        # Build deterministic deck from factory, then deal
        from ..utils.deck_factory import DeckFactory
        factory = DeckFactory(self.game_state.game_id)
        self.game_state.deck.cards = factory.build_deck(
            include_jokers=True,
            include_special_powers=True,
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
                player.set_playing()  # Current player is playing
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
    
    def _next_player(self):
        """Move to the next player and update statuses"""
        if not self.game_state.current_player_id:
            return
        
        # Set current player to ready
        current_player = self.game_state.players.get(self.game_state.current_player_id)
        if current_player:
            current_player.set_ready()
        
        # Move to next player
        player_ids = list(self.game_state.players.keys())
        current_index = player_ids.index(self.game_state.current_player_id)
        next_index = (current_index + 1) % len(player_ids)
        self.game_state.current_player_id = player_ids[next_index]
        
        # Set next player to playing
        next_player = self.game_state.players.get(self.game_state.current_player_id)
        if next_player:
            next_player.set_playing()
    
    def _end_game_with_scoring(self, reason: str = "", last_player_id: Optional[str] = None) -> Dict[str, Any]:
        """Compute scores and end game with tie-break rules."""
        # Set all players to finished status
        for player in self.game_state.players.values():
            player.set_finished()
        
        final_scores: Dict[str, Any] = {}
        for p in self.game_state.players.values():
            final_scores[p.player_id] = {
                "player_id": p.player_id,
                "name": p.name,
                "points": p.calculate_points(),
                "cards_remaining": len(p.hand),
                "called_recall": p.has_called_recall
            }
        
        winner = self._determine_winner(final_scores)
        self.game_state.winner = winner
        self.game_state.phase = GamePhase.GAME_ENDED
        self.game_state.game_ended = True
        
        return {
            "success": True,
            "winner": winner,
            "final_scores": final_scores,
            "phase": self.game_state.phase.value,
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
        return not player.has_called_recall and self.game_state.phase != GamePhase.RECALL_CALLED
