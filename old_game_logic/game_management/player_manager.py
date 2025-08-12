import sys
import os
from enum import Enum, auto
import types
import inspect
from app_logging.server.custom_logging import custom_log, log_function_call, game_play_log, add_logging_to_module, FUNCTION_LOGGING_ENABLED

DEBUG_ACTIVE = True

class PlayerState(Enum):
    IDLE = auto()
    REVEAL_CARDS = auto()
    SAME_RANK_WINDOW = auto()
    CHOOSING_DECK = auto()
    CHOOSING_CARD = auto()
    JACK_SPECIAL = auto()
    QUEEN_SPECIAL = auto()
    CALL_WINDOW = auto()
    QUEEN_PLAY_INFO = auto()
    JACK_PLAY_INFO = auto()
    SHOW_FIRST_CARDS = auto()

class Player:
    def __init__(self, name, player_id, player_type, event_manager, game_room):
        self.player_type = player_type
        self.name = name
        self.id = str(player_id)
        self.hand = []
        self.known_cards = []
        self.unknown_cards = []
        self.known_from_others = []
        self.active_card = None
        self.score = 0
        self.event_manager = event_manager
        self.state = PlayerState.IDLE
        self.game_room = game_room
        self.game_room_serialized = game_room.serialize(full=False) if game_room else {}

    def handle_state_change(self, new_state, data=None):
        if new_state == PlayerState.CALL_WINDOW:
            if self.player_type == 'user':
                self.event_manager.emit_event('callWindow', data, rooms=self.id)
        else:
            # Set the new state for the player
            self.state = new_state
            # Check if data is provided, if not, serialize the current player state
            data = self.serialize()

            if self.player_type == 'user':
                self.event_manager.emit_event('player_data', data, rooms=self.id)

    def set_active_card(self, card):
        """Sets a card as the active card."""
        self.active_card = card

    def set_score(self, score):
        """Sets the player's score."""
        self.score = score

    def check_remaining_cards(self):
        return len(self.hand)

    def __repr__(self):
        return (f"<Player name={self.name}, "
                f"id={self.id}, "
                f"player_type={self.player_type}, "
                f"hand={self.hand}, "
                f"known_cards={self.known_cards}, "
                f"unknown_cards={self.unknown_cards}, "
                f"known_from_others={self.known_from_others}, "
                f"active_card={self.active_card}, "
                f"score={self.score}>")

    def serialize(self):
        """Serialize the player object to a dictionary suitable for JSON serialization."""
        card_details = []
        for id in self.hand:
            game_room_card = self.game_room.get_card_details_by_id(id)
            card_details.append(game_room_card)
        
        return {
            'name': self.name,
            'id': self.id,
            'player_type': self.player_type,
            'hand': self.hand,
            'score': self.score,
            'active_card': self.active_card if self.active_card else None,
            'state': self.state.name,
            'game_room': self.game_room_serialized,
        }

class PlayerManager:
    def __init__(self, game_manager, event_manager):
        self.game_manager = game_manager
        self.event_manager = event_manager

        if FUNCTION_LOGGING_ENABLED:
            add_logging_to_module(__import__(__name__))
        
    def create_player(self, name, player_id, player_type, event_manager, game_room):
        return Player(name, player_id, player_type, event_manager, game_room)
