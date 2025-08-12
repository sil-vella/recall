from .game_state import GameStateEnum
from ..game_cards.Cards import cards_list
import random

from app_logging.server.custom_logging import custom_log, log_function_call, game_play_log

class GameRoomState:
    def __init__(self, event_manager, game_id):
        """
        Initialize a new instance of GameRoomState.

        Parameters:
        event_manager (EventManager): The event manager for the game.
        game_id (str): The unique identifier for the game room.
        """
        self.game_id = game_id
        self.game_mode = None
        self.players = {}
        self.current_player = None
        self.special_cards_queue = []
        self.cards_list = []
        self.face_down_cards = self.generate_unique_ids(cards_list)
        self.face_up_cards = []
        self.game_over = False
        self.state = GameStateEnum.PREGAME
        self.event_manager = event_manager
        self.same_rank_buffer_active = False
        self.special_rank_buffer_active = False
        self.first_reveal_buffer_active = False
        self.turn_number = 0
        self.final_round_queue = []
        self.called_user_id = ''
        self.winners_queue = []

    def generate_unique_ids(self, cards_list):
        """
        Generate unique 5-digit IDs for each card in the list, updating self.cards_list with 
        complete details and self.face_down_cards with just the ID.

        Parameters:
        cards_list (list): The list of card details.

        Returns:
        list: The list of unique IDs for the cards.
        """
        updated_cards = []
        used_ids = set()
        for card in cards_list:
            card_details = card.copy()  # Copy existing card details
            while True:
                new_id = random.randint(10000, 99999)  # Ensure unique IDs
                if new_id not in used_ids:
                    used_ids.add(new_id)
                    card_details['id'] = new_id  # Add unique ID
                    self.cards_list.append(card_details)  # Add complete details to cards_list
                    updated_cards.append(new_id)  # Store only the ID in face_down_cards
                    break
        return updated_cards

    def __repr__(self):
        """
        Return a string representation of the GameRoomState instance.

        Returns:
        str: The string representation of the GameRoomState instance.
        """
        players_repr = {player_id: str(player) for player_id, player in self.players.items()}
        return (f"<GameRoomState game_id={self.game_id}, players={players_repr}, "
                f"current_player={self.current_player}, "
                f"special_cards_queue={self.special_cards_queue}, "
                f"face_down_cards={self.face_down_cards}, "
                f"face_up_cards={self.face_up_cards}, "
                f"game_over={self.game_over}, "
                f"called_user_id={self.called_user_id}, "
                f"winners_queue={self.winners_queue}, "
                f"state={self.state.name}>")

    def remove_player(self, user_id):
        """
        Remove a player from the game room.

        Parameters:
        user_id (str): The unique identifier of the player to be removed.
        """
        self.players.pop(user_id, None)
 
    def log_current_players(self):
        """
        Log the current players in the game room.
        """
        player_info = ', '.join([f'{username} (ID: {player_id})' for username, player_id in self.players.items()])

    def get_room_data(self):
        """
        Get the room data for serialization.

        Returns:
        dict: The room data dictionary.
        """
        room_data = {
            'players': {player_id: player.serialize() for player_id, player in self.players.items()},
            'current_player': self.current_player,
        }
        return room_data
    
    def get_last_face_up_card(self):
        """
        Get the last face-up card if there are any, None otherwise.

        Returns:
        dict or None: The last face-up card details or None if there are no cards.
        """
        if self.face_up_cards:  # Check if the list is not empty
            return self.face_up_cards[-1]  # Return the last card
        return None  # Return None if the list is empty

    def add_mod_face_up_cards(self, card_id=None):
        """
        Add a card to the face-up pile, ensuring the last card has full details, or refresh the last card if card_id is None.

        Parameters:
        card_id (int, optional): The unique identifier for a card. If None, the last card's ID is used. Defaults to None.

        Returns:
        None
        """
        # If no card_id is provided, determine the card_id of the current last card
        if card_id is None:
            # Check if the face_up_cards pile is not empty to avoid index error
            if self.face_up_cards:
                # Fetch the card_id from the last card in face_up_cards
                # If the last card is a dict (full details), extract its 'id'
                card_id = self.face_up_cards[-1]['id'] if isinstance(self.face_up_cards[-1], dict) else self.face_up_cards[-1]
            else:
                # No cards to update, so card_id remains None
                card_id = None

        # If card_id is determined (not None)
        if card_id is not None:
            # Fetch the full card details using card_id
            card_details = self.get_card_details_by_id(card_id)

            # Remove any existing card with the same card_id from face_up_cards
            self.face_up_cards = [
                card for card in self.face_up_cards
                if not (isinstance(card, dict) and card['id'] == card_id) and card != card_id
            ]

            # Add the full card details to face_up_cards
            self.face_up_cards.append(card_details)

            # Strip full details from all cards except the last one
            for i in range(len(self.face_up_cards) - 1):
                if isinstance(self.face_up_cards[i], dict):
                    self.face_up_cards[i] = self.face_up_cards[i]['id']

    def get_card_details_by_id(self, card_id):
        """
        Retrieve card details by card ID, handling both full card dictionaries and ID-only lists.
        
        Args:
        card_id (int or dict): The unique identifier for a card or the card details dictionary.
        
        Returns:
        dict: The dictionary of card details such as rank, suit, and color, or raises an error.
        """
        # If card_id is already a dictionary, return it as is
        if isinstance(card_id, dict):
            custom_log(f"Card ID is already a dictionary: {card_id}")
            return card_id
        
        # Otherwise, treat it as an ID and look up the card details
        if all(isinstance(card, dict) for card in self.cards_list):  # Assuming all elements are dicts
            card_details_dict = {card['id']: card for card in self.cards_list}
            try:
                card_details = card_details_dict[card_id]
                custom_log(f"Retrieved card details for card ID {card_id}: {card_details}")
                return card_details
            except KeyError:
                custom_log(f"No card found with ID {card_id}")
                raise ValueError(f"No card found with ID {card_id}")
        else:
            custom_log("cards_list must contain dictionaries")
            raise TypeError("cards_list must contain dictionaries")

    def serialize(self, full=True):
        """
        Serialize the game room state to a dictionary suitable for JSON serialization, including the game_id.

        Parameters:
        full (bool, optional): If True, include all attributes in the serialization. If False, only include game_id and game_play_state. Defaults to True.

        Returns:
        dict: The serialized game room state.
        """
        def convert_int_to_str(value):
            """Convert integers in the data structure to strings."""
            if isinstance(value, int):
                return str(value)
            elif isinstance(value, list):
                return [convert_int_to_str(item) for item in value]
            elif isinstance(value, dict):
                return {key: convert_int_to_str(val) for key, val in value.items()}
            return value

        if not full:
            return {
                'game_id': str(self.game_id),
                'game_play_state': self.state.name
            }

        return {
            'game_id': str(self.game_id),  # Convert game_id to string
            'game_mode': self.game_mode,
            'players': {str(player_id): player.serialize() for player_id, player in self.players.items()},
            'current_player': str(self.current_player),
            'special_cards_queue': convert_int_to_str(self.special_cards_queue),
            'face_down_cards': convert_int_to_str(self.face_down_cards),
            'face_up_cards': convert_int_to_str(self.face_up_cards),
            'winners_queue': convert_int_to_str(self.winners_queue),
            'called_user_id': str(self.called_user_id),
            'game_play_state': self.state.name
        }
