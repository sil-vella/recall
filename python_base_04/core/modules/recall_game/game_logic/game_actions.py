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
        
        # Set next player to drawing card (they need to draw first)
        next_player = self.game_state.players.get(self.game_state.current_player_id)
        if next_player:
            next_player.set_drawing_card()
