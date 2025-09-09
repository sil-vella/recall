"""
Player Models for Recall Game

This module defines the player system for the Recall card game,
including human players and computer players with AI logic.
"""

from typing import List, Dict, Any, Optional
from enum import Enum
from .card import Card
from tools.logger.custom_logging import custom_log

# Logging switch for this module
LOGGING_SWITCH = True


class PlayerType(Enum):
    """Player types"""
    HUMAN = "human"
    COMPUTER = "computer"


class PlayerStatus(Enum):
    """Player status enumeration"""
    WAITING = "waiting"      # Waiting for game to start
    READY = "ready"          # Ready to play (waiting for turn)
    PLAYING = "playing"      # Currently playing (active turn)
    SAME_RANK_WINDOW = "same_rank_window"  # Window for out-of-turn same rank plays
    PLAYING_CARD = "playing_card"  # Player is in the process of playing a card
    DRAWING_CARD = "drawing_card"  # Player is in the process of drawing a card
    QUEEN_PEEK = "queen_peek"      # Player used queen power to peek at a card
    JACK_SWAP = "jack_swap"        # Player used jack power to swap cards
    FINISHED = "finished"    # Game finished
    DISCONNECTED = "disconnected"  # Disconnected from game


class Player:
    """Base player class for the Recall game"""
    
    def __init__(self, player_id: str, player_type: PlayerType, name: str):
        self.player_id = player_id
        self.player_type = player_type
        self.name = name
        self.hand = []  # 4 cards face down
        self.visible_cards = []  # Cards player has looked at
        self.known_from_other_players = []  # Cards player knows from other players
        self.points = 0
        self.cards_remaining = 4
        self.is_active = True
        self.has_called_recall = False
        self.last_action_time = None
        self.initial_peeks_remaining = 2
        self.status = PlayerStatus.WAITING  # Player status
        self.drawn_card = None  # Most recently drawn card (Card object)
        
        # Auto-change detection for player updates
        self._change_tracking_enabled = True
        self._pending_changes = set()  # Track which properties have changed
        self._initialized = True  # Flag to prevent tracking during initialization
        self._game_state_manager = None  # Reference to game state manager for sending updates
        self._game_id = None  # Reference to game ID for sending updates
    
    def add_card_to_hand(self, card: Card):
        """Add a card to the player's hand, filling a blank slot if available"""
        card.owner_id = self.player_id
        
        # Look for a blank slot (None) to fill first
        for i, slot in enumerate(self.hand):
            if slot is None:
                self.hand[i] = card
                # Don't update cards_remaining - we're filling an existing slot
                custom_log(f"Added card to hand: {card.card_id} at index {i} (filled blank slot)", isOn=LOGGING_SWITCH)
                
                # Manually trigger change detection for hand modification
                if hasattr(self, '_track_change'):
                    self._track_change('hand')
                    self._send_changes_if_needed()
                return
        
        # If no blank slot found, append to the end (shouldn't happen in normal gameplay)
        self.hand.append(card)
        self.cards_remaining = len(self.hand)
        
        # Manually trigger change detection for hand modification
        if hasattr(self, '_track_change'):
            self._track_change('hand')
            self._send_changes_if_needed()
    
    def set_drawn_card(self, card: Card):
        """Set the most recently drawn card"""
        self.drawn_card = card
    
    def get_drawn_card(self) -> Optional[Card]:
        """Get the most recently drawn card"""
        return self.drawn_card
    
    def clear_drawn_card(self):
        """Clear the drawn card (e.g., after playing it)"""
        self.drawn_card = None
    
    def remove_card_from_hand(self, card_id: str) -> Optional[Card]:
        """Remove a card from the player's hand and replace it with a blank slot (None) if needed"""
        custom_log(f"remove_card_from_hand called for card_id: {card_id}", level="DEBUG", isOn=LOGGING_SWITCH)
        for i, card in enumerate(self.hand):
            if card is not None and card.card_id == card_id:
                removed_card = self.hand[i]
                
                custom_log(f"Removing card from hand: {card.card_id} at index {i}", isOn=LOGGING_SWITCH)
                
                # Check if we should create a blank slot or remove the card entirely
                should_create_blank_slot = self._should_create_blank_slot_at_index(i)
                
                if should_create_blank_slot:
                    # Replace the card with None (blank slot) to maintain index positions
                    self.hand[i] = None
                    custom_log(f"Created blank slot at index {i}", level="DEBUG", isOn=LOGGING_SWITCH)
                else:
                    # Remove the card entirely and shift remaining cards
                    self.hand.pop(i)
                    custom_log(f"Removed card entirely from index {i}, shifted remaining cards", level="DEBUG", isOn=LOGGING_SWITCH)
                
                # Don't update cards_remaining - we want to maintain the slot count for blank slots
                
                # Clear drawn card if the removed card was the drawn card
                if self.drawn_card and self.drawn_card.card_id == card_id:
                    custom_log(f"Clearing drawn card", isOn=LOGGING_SWITCH)
                    self.clear_drawn_card()
                
                # Manually trigger change detection for hand modification
                if hasattr(self, '_track_change'):
                    self._track_change('hand')
                    self._send_changes_if_needed()
                
                return removed_card
        custom_log(f"Card {card_id} not found in hand", level="DEBUG", isOn=LOGGING_SWITCH)
        return None
    
    def _should_create_blank_slot_at_index(self, index: int) -> bool:
        """Determine if we should create a blank slot at the given index"""
        # If index is 3 or less, always create a blank slot (maintain initial 4-card structure)
        if index <= 3:
            return True
        
        # For index 4 and beyond, only create blank slot if there are actual cards further up
        # Check if there are any non-None cards at higher indices
        for i in range(index + 1, len(self.hand)):
            if self.hand[i] is not None:
                custom_log(f"Found actual card at index {i}, will create blank slot at {index}", level="DEBUG", isOn=LOGGING_SWITCH)
                return True
        
        # No actual cards beyond this index, so remove the card entirely
        custom_log(f"No actual cards beyond index {index}, will remove card entirely", level="DEBUG", isOn=LOGGING_SWITCH)
        return False
    
    def look_at_card(self, card_id: str) -> Optional[Card]:
        """Look at a specific card in hand"""
        for card in self.hand:
            if card.card_id == card_id:
                card.is_visible = True
                if card not in self.visible_cards:
                    self.visible_cards.append(card)
                    # Manually trigger change detection for visible_cards modification
                    if hasattr(self, '_track_change'):
                        self._track_change('visible_cards')
                        self._send_changes_if_needed()
                return card
        return None

    def look_at_card_by_index(self, index: int) -> Optional[Card]:
        """Look at a specific card in hand by index"""
        if index < 0 or index >= len(self.hand):
            return None
        card = self.hand[index]
        card.is_visible = True
        if card not in self.visible_cards:
            self.visible_cards.append(card)
        return card
    
    def get_visible_cards(self) -> List[Card]:
        """Get cards that the player has looked at"""
        return [card for card in self.hand if card is not None and card.is_visible]
    
    def get_hidden_cards(self) -> List[Card]:
        """Get cards that the player hasn't looked at"""
        return [card for card in self.hand if card is not None and not card.is_visible]
    
    def calculate_points(self) -> int:
        """Calculate total points from cards in hand"""
        return sum(card.points for card in self.hand if card is not None)
    
    def call_recall(self):
        """Player calls Recall to end the game"""
        self.has_called_recall = True

    
    def set_status(self, status: PlayerStatus):
        """Set player status"""
        self.status = status
    
    # Individual setter methods removed - now use set_status() with PlayerStatus enum
    # Examples:
    # player.set_status(PlayerStatus.PLAYING)
    # player.set_status(PlayerStatus.READY)
    # player.set_status(PlayerStatus.WAITING)
    # player.set_status(PlayerStatus.SAME_RANK_WINDOW)
    # player.set_status(PlayerStatus.PLAYING_CARD)
    # player.set_status(PlayerStatus.DRAWING_CARD)
    # player.set_status(PlayerStatus.QUEEN_PEEK)
    # player.set_status(PlayerStatus.JACK_SWAP)
    # player.set_status(PlayerStatus.FINISHED)
    # player.set_status(PlayerStatus.DISCONNECTED)
    
    def is_playing(self) -> bool:
        """Check if player is currently playing (active turn)"""
        return self.status == PlayerStatus.PLAYING
    
    def is_ready(self) -> bool:
        """Check if player is ready (waiting for turn)"""
        return self.status == PlayerStatus.READY
    
    def is_waiting(self) -> bool:
        """Check if player is waiting (game not started)"""
        return self.status == PlayerStatus.WAITING
    
    def is_same_rank_window(self) -> bool:
        """Check if player is in same rank window (can play out-of-turn)"""
        return self.status == PlayerStatus.SAME_RANK_WINDOW
    
    def is_playing_card(self) -> bool:
        """Check if player is in process of playing a card"""
        return self.status == PlayerStatus.PLAYING_CARD
    
    def is_drawing_card(self) -> bool:
        """Check if player is in process of drawing a card"""
        return self.status == PlayerStatus.DRAWING_CARD
    
    def is_queen_peek(self) -> bool:
        """Check if player is in queen peek status (used queen power)"""
        return self.status == PlayerStatus.QUEEN_PEEK
    
    def is_jack_swap(self) -> bool:
        """Check if player is in jack swap status (used jack power)"""
        return self.status == PlayerStatus.JACK_SWAP
    
    def is_finished(self) -> bool:
        """Check if player has finished the game"""
        return self.status == PlayerStatus.FINISHED
    
    def is_disconnected(self) -> bool:
        """Check if player is disconnected"""
        return self.status == PlayerStatus.DISCONNECTED
    
    # ========= Auto-Change Detection Methods =========
    
    def set_game_references(self, game_state_manager, game_id: str):
        """Set references to game state manager and game ID for auto-updates"""
        self._game_state_manager = game_state_manager
        self._game_id = game_id
    
    def __setattr__(self, name, value):
        """Override __setattr__ to detect property changes and send updates"""
        # Handle initialization and internal attributes
        if not hasattr(self, '_initialized') or not self._initialized:
            super().__setattr__(name, value)
            return
        
        # Check if this is an internal attribute
        if name.startswith('_'):
            super().__setattr__(name, value)
            return
        
        # Get current value for comparison
        current_value = getattr(self, name, None)
        super().__setattr__(name, value)
        
        # Check if change tracking is enabled and value actually changed
        if (self._change_tracking_enabled and 
            current_value != value and 
            name not in ['_change_tracking_enabled', '_pending_changes', '_initialized', '_game_state_manager', '_game_id']):
            
            # Log the change
            from tools.logger.custom_logging import custom_log
            custom_log(f"Player property change detected: {name} = {value}", isOn=LOGGING_SWITCH)
            
            # Track the change
            self._track_change(name)
            self._send_changes_if_needed()
    
    def _track_change(self, property_name: str):
        """Track a property change"""
        from tools.logger.custom_logging import custom_log
        custom_log(f"Tracking change for player property: {property_name}", isOn=LOGGING_SWITCH)
        self._pending_changes.add(property_name)
    
    def _send_changes_if_needed(self):
        """Send player state update if there are pending changes"""
        if not self._pending_changes or not self._game_state_manager or not self._game_id:
            return
        
        try:
            from tools.logger.custom_logging import custom_log
            custom_log(f"Player _send_changes_if_needed called with {len(self._pending_changes)} pending changes", isOn=LOGGING_SWITCH)
            custom_log(f"=== SENDING PLAYER UPDATE ===", isOn=LOGGING_SWITCH)
            custom_log(f"Player ID: {self.player_id}", isOn=LOGGING_SWITCH)
            custom_log(f"Changed properties: {list(self._pending_changes)}", isOn=LOGGING_SWITCH)
            custom_log(f"=============================", isOn=LOGGING_SWITCH)
            
            # Get the coordinator from the game state manager
            if hasattr(self._game_state_manager, 'app_manager') and self._game_state_manager.app_manager:
                coordinator = getattr(self._game_state_manager.app_manager, 'game_event_coordinator', None)
                if coordinator:
                    # Send player state update using existing coordinator method
                    coordinator._send_player_state_update(self._game_id, self.player_id)
                    custom_log(f"Player update sent successfully for properties: {list(self._pending_changes)}", isOn=LOGGING_SWITCH)
                    
                    # Also trigger GameState players property change detection
                    self._trigger_gamestate_players_update()
                else:
                    custom_log("No coordinator found for player update", isOn=LOGGING_SWITCH)
            else:
                custom_log("No app_manager found for player update", isOn=LOGGING_SWITCH)
            
            # Clear pending changes
            self._pending_changes.clear()
            
        except Exception as e:
            from tools.logger.custom_logging import custom_log
            custom_log(f"Error in player _send_changes_if_needed: {e}", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"❌ Traceback: {traceback.format_exc()}", isOn=LOGGING_SWITCH)
    
    def _trigger_gamestate_players_update(self):
        """Trigger GameState players property change detection to send room-wide update"""
        try:
            from tools.logger.custom_logging import custom_log
            custom_log(f"🔄 Triggering GameState players property update for player: {self.player_id}", isOn=LOGGING_SWITCH)
            
            # Get the game state from the game state manager
            if hasattr(self._game_state_manager, 'get_game'):
                game_state = self._game_state_manager.get_game(self._game_id)
                if game_state and hasattr(game_state, '_track_change'):
                    # Manually trigger the players property change detection
                    game_state._track_change('players')
                    game_state._send_changes_if_needed()
                    custom_log(f"✅ GameState players property update triggered successfully", isOn=LOGGING_SWITCH)
                else:
                    custom_log("❌ GameState not found or doesn't have change tracking", isOn=LOGGING_SWITCH)
            else:
                custom_log("❌ GameStateManager doesn't have get_game method", isOn=LOGGING_SWITCH)
                
        except Exception as e:
            from tools.logger.custom_logging import custom_log
            custom_log(f"❌ Error triggering GameState players update: {e}", isOn=LOGGING_SWITCH)
            import traceback
            custom_log(f"❌ Traceback: {traceback.format_exc()}", isOn=LOGGING_SWITCH)
    
    def enable_change_tracking(self):
        """Enable automatic change tracking"""
        self._change_tracking_enabled = True
    
    def disable_change_tracking(self):
        """Disable automatic change tracking"""
        self._change_tracking_enabled = False
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert player to dictionary representation"""
        # Debug logging for hand serialization
        hand_cards = [card.to_dict() for card in self.hand if card is not None]
        custom_log(f"Player {self.player_id} to_dict: hand has {len(self.hand)} slots, {len(hand_cards)} actual cards", level="DEBUG", isOn=LOGGING_SWITCH)
        custom_log(f"Hand slots: {[card.card_id if card else 'None' for card in self.hand]}", level="DEBUG", isOn=LOGGING_SWITCH)
        
        return {
            "player_id": self.player_id,
            "player_type": self.player_type.value,
            "name": self.name,
            "hand": hand_cards,
            "visible_cards": [card.to_dict() for card in self.visible_cards],
            "points": self.points,
            "cards_remaining": self.cards_remaining,
            "is_active": self.is_active,
            "has_called_recall": self.has_called_recall,
            "initial_peeks_remaining": self.initial_peeks_remaining,
            "status": self.status.value,  # Include player status
            "drawn_card": self.drawn_card.to_dict() if self.drawn_card else None,  # Include drawn card
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Player':
        """Create player from dictionary"""
        player_type = PlayerType(data["player_type"])
        player = cls(data["player_id"], player_type, data["name"])
        
        # Restore hand
        for card_data in data.get("hand", []):
            card = Card.from_dict(card_data)
            player.add_card_to_hand(card)
        
        # Restore visible cards
        for card_data in data.get("visible_cards", []):
            card = Card.from_dict(card_data)
            player.visible_cards.append(card)
        
        player.points = data.get("points", 0)
        player.cards_remaining = data.get("cards_remaining", 4)
        player.is_active = data.get("is_active", True)
        player.has_called_recall = data.get("has_called_recall", False)
        player.initial_peeks_remaining = data.get("initial_peeks_remaining", 2)
        
        # Restore drawn card
        drawn_card_data = data.get("drawn_card")
        if drawn_card_data:
            player.drawn_card = Card.from_dict(drawn_card_data)
        else:
            player.drawn_card = None
        
        # Restore player status
        status_str = data.get("status", "waiting")
        try:
            player.status = PlayerStatus(status_str)
        except ValueError:
            player.status = PlayerStatus.WAITING  # Default fallback
        
        return player


class HumanPlayer(Player):
    """Human player class"""
    
    def __init__(self, player_id: str, name: str):
        super().__init__(player_id, PlayerType.HUMAN, name)
    
    def make_decision(self, game_state: Dict[str, Any]) -> Dict[str, Any]:
        """Human players make decisions through WebSocket events"""
        # This will be handled by WebSocket events from the frontend
        return {
            "player_id": self.player_id,
            "decision_type": "waiting_for_human_input",
            "available_actions": self._get_available_actions(game_state)
        }
    
    def _get_available_actions(self, game_state: Dict[str, Any]) -> List[str]:
        """Get available actions for the human player"""
        actions = []
        
        if game_state.get("current_player_id") == self.player_id:
            actions.append("play_card")
            actions.append("draw_from_discard")
            actions.append("call_recall")
        
        # Check for out-of-turn plays
        if game_state.get("last_played_card"):
            out_of_turn_cards = self.can_play_out_of_turn(
                game_state["last_played_card"]
            )
            if out_of_turn_cards:
                actions.append("play_out_of_turn")
        
        return actions


class ComputerPlayer(Player):
    """Computer player class with AI decision making"""
    
    def __init__(self, player_id: str, name: str, difficulty: str = "medium"):
        super().__init__(player_id, PlayerType.COMPUTER, name)
        self.difficulty = difficulty
    
    def make_decision(self, game_state: Dict[str, Any]) -> Dict[str, Any]:
        """Make AI decision based on game state using built-in logic"""
        from tools.logger.custom_logging import custom_log
        
        # Use built-in AI logic methods
        best_card = self._select_best_card(game_state)
        should_call_recall = self._should_call_recall(game_state)
        
        if should_call_recall:
            return {
                "action": "call_recall",
                "reason": f"AI decided to call recall (difficulty: {self.difficulty})",
                "player_id": self.player_id
            }
        
        if best_card:
            # Find the card index in hand
            card_index = next((i for i, card in enumerate(self.hand) if card.card_id == best_card.card_id), 0)
            return {
                "action": "play_card",
                "card_index": card_index,
                "reason": f"AI selected best card (difficulty: {self.difficulty})",
                "player_id": self.player_id
            }
        
        # Fallback: play first card
        return {
            "action": "play_card",
            "card_index": 0,
            "reason": f"AI fallback decision (difficulty: {self.difficulty})",
            "player_id": self.player_id
        }
    
    def _evaluate_card_value(self, card: Card, game_state: Dict[str, Any]) -> float:
        """Evaluate the value of a card in the current game state"""
        base_value = card.points
        
        # Factor in special powers
        if card.has_special_power():
            base_value -= 2  # Prefer special power cards
        
        # Factor in game progression
        if game_state.get("recall_called"):
            # In final round, minimize points
            return -base_value
        else:
            # During normal play, balance points and utility
            return -base_value * 0.7 + (10 if card.has_special_power() else 0)
    
    def _select_best_card(self, game_state: Dict[str, Any]) -> Optional[Card]:
        """Select the best card to play"""
        if not self.hand:
            return None
        
        # Evaluate all cards
        card_values = []
        for card in self.hand:
            value = self._evaluate_card_value(card, game_state)
            card_values.append((card, value))
        
        # Sort by value (best first)
        card_values.sort(key=lambda x: x[1], reverse=True)
        
        return card_values[0][0] if card_values else None
    
    def _should_call_recall(self, game_state: Dict[str, Any]) -> bool:
        """Determine if the computer should call Recall"""
        if self.has_called_recall:
            return False
        
        # Calculate current position
        total_points = self.calculate_points()
        cards_remaining = len(self.hand)
        
        # Simple AI logic - call Recall if in good position
        if cards_remaining <= 1 and total_points <= 5:
            return True
        
        if cards_remaining <= 2 and total_points <= 3:
            return True
        
        return False 
    
    def _update_known_from_other_players(self, card: Card, game_state: Dict[str, Any]):
        """Update the player's known cards from other players list"""
