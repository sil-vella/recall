import random
import time
import os
import sys
import logging
from flask import request
from flask_socketio import join_room
from .plugin_manager import PluginManager
from .game_state import GameState, GameStateEnum
from .game_room_state import GameRoomState
from .player_manager import PlayerManager, PlayerState
from .computer_manager import ComputerManager
from .round_manager import RoundManager
from app_logging.server.custom_logging import custom_log, log_function_call, game_play_log, add_logging_to_module, FUNCTION_LOGGING_ENABLED

if FUNCTION_LOGGING_ENABLED:
    current_module = sys.modules[__name__]
    add_logging_to_module(current_module, exclude_packages=['flask', 'flask_cors', 'flask_socketio'])


class GameManager:
    def __init__(self, event_manager):
        self.event_manager = event_manager
        self.round_manager = RoundManager(self.event_manager, self)
        self.computer_manager = ComputerManager(self.event_manager, self.round_manager)
        self.player_manager = PlayerManager(self, event_manager=self.event_manager)
        self.plugin_manager = PluginManager(self)
        
        base_dir = os.path.dirname(os.path.abspath(__file__))  # Get the directory of the current file
        plugin_dir = os.path.join(base_dir, '../plugins')  # Construct the plugin directory path
        self.plugin_manager.load_plugins(plugin_dir)
        
        self.user_game_mapping = {}
        self.game_state = GameState(event_manager)
        self.game_state.attach(self.handle_state_change)

    def handle_state_change(self, new_state, game_room, data=None):
        """
        Handle the state change for the game room by updating the game state and emitting the corresponding event.

        Args:
            new_state (GameStateEnum): The new state to be set for the game room.
            game_room (GameRoomState): The game room state object.
            data (dict, optional): Additional data to be included in the emitted event. Defaults to None.

        Returns:
            None
        """
        game_room.state = new_state
        emit_data = data if data else game_room.serialize()
        event_map = {
            GameStateEnum.SOLO_GAME_READY: 'solo_game_ready',
            GameStateEnum.MULTIPLAYER_GAME_READY: 'multiplayer_game_ready',
            GameStateEnum.REVEAL_CARDS: 'revealTwoCards',
            GameStateEnum.PLAYER_TURN: 'player_turn',
            GameStateEnum.GAME_OVER: 'game_ended',
            GameStateEnum.LOADING: 'loading',
            GameStateEnum.SAME_RANK_WINDOW: 'same_rank_phase',
            GameStateEnum.SPECIAL_RANK_WINDOW: 'special_rank_phase',
        }
        event_name = event_map.get(new_state, 'state_changed')
        self.event_manager.emit_event(event_name, emit_data, rooms=game_room.game_id)

    def create_or_get_game(self, room_id):
        """
        Retrieve an existing game room state or create a new one if it doesn't exist.

        :param room_id: The unique identifier for the game room.
        :return: The GameRoomState object for the specified room_id.
        """
        # Check if the game room state already exists
        if room_id not in self.game_state.games:
            # Create a new game room state if it doesn't exist
            new_room_state = GameRoomState(self.event_manager, room_id)
            self.game_state.games[room_id] = new_room_state

        # Return the existing or newly created game room state
        return self.game_state.games[room_id]


    def add_player(self, gameData, playerData):
        """
        Adds a new player to the game room.

        Parameters:
        gameData (dict): Contains game-related data such as gameId.
        playerData (dict): Contains player-related data such as player_id, player_type, and username.

        Returns:
        None
        """
        player_id = playerData['player_id']
        player_type = playerData['player_type']
        username = playerData['username']

        gameId = gameData['gameId']

        game_room = self.create_or_get_game(gameId)
        if player_id not in game_room.players:
            new_player = self.player_manager.create_player(username, player_id, player_type, self.event_manager, game_room)
            game_room.players[player_id] = new_player
            game_room.log_current_players()

            # Ensure join_room is used correctly
            join_room(gameId)
            join_room(player_id)

    def add_user_to_game(self, user_id: str, game_id: str) -> None:
        """
        Add or update the mapping of user_id to game_id.

        Parameters:
        user_id (str): The unique identifier of the user.
        game_id (str): The unique identifier of the game.

        Returns:
        None
        """
        self.user_game_mapping[user_id] = game_id

    def remove_user_from_game(self, user_id: str) -> None:
        """
        Remove the user from the mapping if they exist.

        Parameters:
        user_id (str): The unique identifier of the user.

        Returns:
        None
        """
        if user_id in self.user_game_mapping:
            del self.user_game_mapping[user_id]

    def user_disconnect_handler(self, user_id):
        """
        Handles the disconnection of a user from the game.

        Parameters:
        user_id (str): The unique identifier of the user who disconnected.

        Returns:
        None
        """
        # Use user_game_mapping to find the game the user is part of
        game_id = self.user_game_mapping.get(user_id)
        if game_id:
            # Proceed to handle the user's disconnection from the game
            game = self.game_state.games.get(game_id)
            if game:
                game.remove_player(user_id)
                serialized_game_state = game.serialize()
                # Emit the current game state along with the disconnected user_id
                self.event_manager.emit_event('playerLeft', {'user_id': user_id, 'gameData': serialized_game_state}, rooms=game_id)
                
            # Clean up the mapping
            self.remove_user_from_game(user_id)

    def setup_first_reveal_buffer(self, game_room):
        """
        Sets up a buffer for the first reveal of cards in the game.

        Parameters:
        game_room (GameRoomState): The game room instance where the buffer will be set up.

        Returns:
        None
        """
        game_room.first_reveal_buffer_active = True

        self.handle_state_change(GameStateEnum.REVEAL_CARDS, game_room)
        self.set_all_players_state(game_room=game_room, new_state=PlayerState.REVEAL_CARDS)

        time.sleep(10)

        # Iterate through each player and update their hand
        for player in game_room.players.values():
            new_hand = []
            for card in player.hand:
                if isinstance(card, dict):
                    new_hand.append(card['id'])
                else:
                    new_hand.append(card)
            player.hand = new_hand

        self.set_all_players_state(game_room=game_room, new_state=PlayerState.IDLE)
        self.handle_state_change(GameStateEnum.LOADING, game_room)
        game_room.first_reveal_buffer_active = False  # Reset buffer active flag on game_room instance

    def player_join_game_handler(self, data, user_id):
        """
        Handles the player joining the game. Creates computer players if the game mode is 'solo' and
        updates the game state accordingly.

        Parameters:
        data (dict): The data containing game and player information.
        user_id (str): The unique identifier of the player joining the game.

        Returns:
        None
        """

        def joinPlayer(data, game_room, user_id, player_type):
            """
            Joins a player to the game room.

            Parameters:
            data (dict): The data containing game and player information.
            game_room (GameRoomState): The game room state object.
            user_id (str): The unique identifier of the player joining the game.
            player_type (str): The type of the player (user or computer).

            Returns:
            None
            """
            gameData = data['gameData']
            playerData = data['playerData']
            playerData['player_id'] = user_id
            playerData['player_type'] = player_type

            game_id = gameData['gameId']
            self.add_user_to_game(user_id, game_id)
            self.add_player(gameData, playerData)

            join_room(game_id)
            join_room(user_id)

        def roomNotAvailable(data, user_id):
            """
            Emits an event indicating that the room is not available.

            Parameters:
            data (dict): The data containing game and player information.
            user_id (str): The unique identifier of the player.

            Returns:
            None
            """
            self.event_manager.emit_event('roomNotAvailable', {}, user_id)

        def create_computer_data(base_data, index):
            """
            Creates computer player data.

            Parameters:
            base_data (dict): The base data containing game and player information.
            index (int): The index of the computer player.

            Returns:
            dict: The modified base data with computer player information.
            """
            # Directly modify the playerData dictionary within base_data
            base_data['playerData']['username'] = f'Computer{index}'
            return base_data

        game_mode = data.get('gameData', {}).get('gameMode')
        game_id = data['gameData']['gameId']
        game_room = self.create_or_get_game(game_id)

        if game_room.state in (GameStateEnum.PREGAME, GameStateEnum.MULTIPLAYER_GAME_READY):
            if game_mode == 'solo':
                numOfOpponents = int(data['gameData']['numOfOpponents'])
                for i in range(numOfOpponents):
                    computer_id = f"{user_id}computer{i+1}"
                    computer_data = create_computer_data(data, i+1)
                    joinPlayer(computer_data, game_room, computer_id, player_type='computer')

                data['playerData']['username'] = 'You'
                joinPlayer(data, game_room, user_id, player_type='user')

            else:
                joinPlayer(data, game_room, user_id, player_type='user')

        else:
            roomNotAvailable(data, user_id)

    def end_game_handler(self, game_room):
        """
        Handles the end of the game, determines the winner(s), and manages state changes.

        Args:
            game_room (GameRoomState): The GameRoomState object containing all game-related data.

        Returns:
            None
        """

        def winners_handler():
            """
            Determines the winners, emits the corresponding events, and updates the game state.

            Returns:
                None
            """
            winners_ids = game_room.winners_queue
            if winners_ids:
                # Handle already determined winners
                for winner_id in winners_ids:
                    self.event_manager.emit_event('gameWinner', {}, winner_id)
            else:
                # Calculate scores and determine new winners
                scores = self.calculate_and_update_scores(game_room=game_room)
                min_score = min(scores, key=lambda x: x[1])[1]
                players_with_min_score = [player for player in scores if player[1] == min_score]
                found = any(player[0] == game_room.called_user_id for player in players_with_min_score)

                if found:
                    # The caller is among the winners
                    caller_winner_data = game_room.players[game_room.called_user_id].serialize()
                    self.event_manager.emit_event('callerGameWinner', {'player_data': caller_winner_data}, game_room.called_user_id)
                    game_room.winners_queue.append(game_room.called_user_id)
                else:
                    # Handle multiple winners with the lowest score
                    for player in players_with_min_score:
                        player_data = game_room.players[player[0]].serialize()
                        self.event_manager.emit_event('gameWinnerLowestScore', {'player_data': player_data}, player[0])
                        game_room.winners_queue.append(player[0])

                    # Log and handle state change
                    winners_usernames = [game_room.players[player_id].name for player_id in game_room.winners_queue]
                    self.handle_state_change(GameStateEnum.GAME_OVER, game_room)

        # Wait for all buffers to end before handling winners
        self.wait_for_buffers_to_end(game_room, winners_handler)

    def start_game_handler(self, data):
        """
        Handles the start of the game.

        Parameters:
        data (dict): The data containing game and player information.

        Returns:
        None
        """
        game_id = data['gameData']['gameId']
        # Retrieve the game room state using the GameManager
        game_room = self.create_or_get_game(game_id)
        first_turned_card = random.choice(game_room.face_down_cards)

        game_room.add_mod_face_up_cards(first_turned_card)
        game_room.face_down_cards.remove(first_turned_card)

        self.handle_state_change(GameStateEnum.LOADING, game_room)

        self.first_draw(game_room=game_room)
        time.sleep(2)
        self.setup_first_reveal_buffer(game_room=game_room)

        self.round_manager.next_turn_handler(game_room)

    def reveal_first_cards_handler(self, data, user_id):
        """
        Handles the revealing of the first two cards by a player.

        Parameters:
        data (dict): The data containing game and player information.
            gameId (str): The ID of the game room.
            newSelectedCards (list): The list of cards selected by the player.

        user_id (str): The unique identifier of the player revealing the cards.

        Returns:
        None
        """
        game_id = data['gameId']
        cards = data['newSelectedCards']
        
        game_room = self.create_or_get_game(game_id)
        player = game_room.players.get(user_id)
        player.handle_state_change(PlayerState.IDLE)

        player_hand = player.hand
        card1_id = cards[0]['cardId'] 
        card2_id = cards[1]['cardId']  
        
        # Find the index of the card_id in the player's hand and replace it with card details
        if card1_id in player_hand:
            index1 = player_hand.index(card1_id)
            card1_details = game_room.get_card_details_by_id(cards[0]['cardId'])
        
        if card2_id in player_hand:
            index2 = player_hand.index(card2_id)
            card2_details = game_room.get_card_details_by_id(cards[1]['cardId'])
        
        self.msg_board_and_anim_update(data={
            'msg_id': 9,
            'action': 'reveal_first_cards',
            'username1': player.name,
            'username1type': player.player_type,
            'card1': card1_details,
            'card2': card2_details,
            'index1': index1,
            'index2': index2,

        },
        game_room_id=game_room.game_id)

        # Log game play
        game_play_log(f"{player.name} revealed 2 cards: {card1_details} and {card2_details}.")

    def setup_game(self, gameData, playerData):
        """
        Setups the game based on the provided gameData and playerData.

        Parameters:
        gameData (dict): Contains game-related information such as gameMode, lobby_rooms, and numOfOpponents.
        playerData (dict): Contains player-related information such as username.

        Returns:
        None
        """
        game_mode = gameData['gameMode']

        game_rooms = gameData['lobby_rooms']
        game_room_id = game_rooms['game_room']
        private_room_id = game_rooms['private_room']

        # Fetch the game instance using the private_room_id
        game_room = self.create_or_get_game(game_room_id)
        game_room.game_mode = game_mode

        if game_mode == 'multiplayer':

            base_url = request.url_root.rstrip('/') 
            share_link = f"{base_url}/?room={game_room_id}"
            
            emit_data = {
                'gameData': {
                    'gameMode': game_mode,
                    'shareLink': share_link,
                    'gameState': 'multiplayer_game_ready',
                    'gameId': game_room_id,
                },
                'playerData': playerData
            }
            game_room = self.create_or_get_game(game_room_id)
            self.player_join_game_handler(data=emit_data, user_id=private_room_id)
            self.handle_state_change(GameStateEnum.MULTIPLAYER_GAME_READY, game_room, emit_data)

        else:
            emit_data = {
                'gameData': {
                    'gameMode': game_mode,
                    'gameState': 'solo_game_ready',
                    'gameId': game_room_id,
                    'numOfOpponents': gameData['numOfOpponents']
                },
                'playerData': playerData
            }
            game_room = self.create_or_get_game(game_room_id)
            self.player_join_game_handler(data=emit_data, user_id=private_room_id)
            self.handle_state_change(GameStateEnum.SOLO_GAME_READY, game_room, emit_data)

    def game_mode_selection_handler(self, data, user_id):
        """
        Handles the game mode selection by a user. Creates a game room, sets up the game, and
        updates the game state based on the selected game mode.

        Parameters:
        data (dict): A dictionary containing game and player information.
            gameData (dict): A dictionary containing game-related information such as gameMode, lobby_rooms, and numOfOpponents.
            playerData (dict): A dictionary containing player-related information such as username.

        user_id (str): The unique identifier of the user making the game mode selection.

        Returns:
        None
        """
        gameData = data['gameData']
        playerData = data['playerData']
        gameCreatorUsername = playerData.get('gameCreatorUsername', '')
        game_id = f'{gameCreatorUsername}-{user_id}'

        lobby_rooms = {'private_room': user_id, 'game_room': game_id}
        gameData['lobby_rooms'] = lobby_rooms 

        self.setup_game(gameData, playerData)  # Call on the instance

    def user_called_game_handler(self, data, user_id):
        """
        Handles the game call by a user. Sets up the final round queue, logs the game play,
        and updates the game room's called user ID.

        Parameters:
        data (str): The game ID.
        user_id (str): The unique identifier of the user calling the game.

        Returns:
        None
        """
        game_id = data
        game_room = self.create_or_get_game(game_id)
        
        # Set up the final round queue with all player IDs except the caller
        game_room.final_round_queue = list(game_room.players.keys())
        game_room.called_user_id = user_id
        game_room.final_round_queue = [player_id for player_id in game_room.players.keys() if player_id != user_id]

        # Log game play
        game_play_log(f'{user_id} called the game')

    def set_all_players_state(self, game_room, new_state, data=None, exclude=None):
        """
        Set the state for all players in the game room, excluding the specified player ID or IDs.

        Parameters:
        game_room (GameRoom): The game room object containing all player data.
        new_state (str): The new state to be set for the players.
        data (dict, optional): Additional data to be passed to the state change function. Defaults to None.
        exclude (list or str, optional): The player IDs or ID to be excluded from the state change. Defaults to None.

        Returns:
        None
        """
        if not game_room:
            return

        # Ensure exclude is either a list of IDs or a single ID
        if exclude is None:
            exclude = []
        elif not isinstance(exclude, list):
            exclude = [exclude]

        for player_id, player in game_room.players.items():
            if player_id in exclude:
                continue  # Skip the state change for excluded player IDs

            player_data = game_room.players.get(player_id)
            if player_data:
                player_data.handle_state_change(new_state)

    def calculate_and_update_scores(self, game_room):
        """
        Calculates and updates the scores for all players in the game room.

        Parameters:
        game_room (GameRoom): The game room object containing all player data.

        Returns:
        list: A list of tuples, where each tuple contains the player ID and their corresponding score.
        """
        results = []  # List to store tuples of (player_id, score)

        # Iterate over all players in the game room
        for player_id, player in game_room.players.items():
            total_points = 0

            # Calculate the total points for each card in the player's hand
            for cardId in player.hand:
                card_details = game_room.get_card_details_by_id(cardId)
                # Directly add the value from the card
                card_value = card_details.get('value', 0)  # Default to 0 if no value key is found
                total_points += card_value

            # Update player's score in their object
            player.set_score(total_points)

            # Append the tuple to the results list
            results.append((player_id, total_points))

        # Return the list of tuples
        return results  # Return the list of tuples

    def wait_for_buffers_to_end(self, game_room, on_completion):
        """
        Waits for all buffers in the game room to end before executing the on_completion function.

        Args:
            game_room (GameRoom): The game room object containing all player data.
            on_completion (function): The function to be executed when all buffers have ended.

        Returns:
            None
        """
        while True:
            if not game_room.same_rank_buffer_active and not game_room.special_rank_buffer_active:
                on_completion()
                break
            time.sleep(3)  # Wait for 3 seconds before checking again

    def first_draw(self, game_room):
        """
        Performs the first draw for each player in the game room.

        Args:
            game_room (GameRoom): The game room object containing all player data.

        Returns:
            None
        """
        for player in game_room.players.values():
            for _ in range(4):
                if game_room.face_down_cards:
                    drawn_card = random.choice(game_room.face_down_cards)
                    game_room.face_down_cards.remove(drawn_card)
                    player.hand.append(drawn_card)
                    player.unknown_cards.append(drawn_card)
            if player.player_type == 'computer' and len(player.hand) >= 2:
                selected_card_ids = random.sample(player.hand, 2)
                player.known_cards.extend(selected_card_ids)
                for card_id in selected_card_ids:
                    player.unknown_cards.remove(card_id)

    def msg_board_and_anim_update(self, data, game_room_id, expect_reply=False, timeout=None):
        """
        Updates the message board and animation for the game room.

        Args:
            data (dict): The data to be sent to the message board and animation.
            game_room_id (str): The ID of the game room.
            expect_reply (bool, optional): Whether to expect a reply from the event. Defaults to False.
            timeout (int, optional): The timeout for the event. Defaults to None.

        Returns:
            None
        """
        data['game_id'] = game_room_id
        self.event_manager.emit_event('msgBoardAndAnim', {'data': data}, game_room_id, expect_reply=expect_reply, timeout=timeout)

    def computer_turn(self, game_room, player_id):
        """
        Performs the computer's turn in the game room.

        Args:
            game_room (GameRoom): The game room object containing all player data.
            player_id (str): The ID of the computer player.

        Returns:
            None
        """
        self.computer_manager.computer_turn(game_room, player_id)