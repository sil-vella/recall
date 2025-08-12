import random
import time
import sys
from .game_state import GameStateEnum
from .player_manager import PlayerState
from app_logging.server.custom_logging import custom_log, log_function_call, game_play_log, add_logging_to_module, FUNCTION_LOGGING_ENABLED

class RoundManager:
    def __init__(self, event_manager, game_manager):
        self.event_manager = event_manager
        self.game_manager = game_manager

    def card_deck_selected_handler(self, data, user_id):
        """
        Handles the event when a user selects a card deck.

        Parameters:
        data (dict): The data received from the client, containing the gameId and selectedDeck.
        user_id (str): The ID of the user who sent the request.

        Returns:
        None
        """
        game_id = data['gameId']
        selected_deck = data['selectedDeck']

        # Retrieve the game room state using the GameManager
        game_room = self.game_manager.create_or_get_game(game_id)
        current_player = game_room.players.get(user_id)

        # Check if the current player is the one who sent the request
        if game_room.current_player == user_id:
            drawn_card = self.draw_card_from_deck(game_room, selected_deck, current_player)

            if drawn_card is not None and current_player:
                drawn_card_details = game_room.get_card_details_by_id(drawn_card)

                current_player.set_active_card(drawn_card_details)

                self.game_manager.msg_board_and_anim_update(data={
                    'action': 'you_drawn',
                    'username1': current_player.name,
                    'card1': drawn_card_details,
                }, game_room_id=current_player.id)

                current_player.handle_state_change(PlayerState.CHOOSING_CARD)

                # Log game play    
                game_play_log(f'Turn: {game_room.turn_number}. {current_player.name} active card before play. {current_player.active_card}: {drawn_card_details}')

            else:
                return

        else:
            self.event_manager.emit_event('notYourTurn', {'message': 'It is not your turn.'}, user_id)

    def card_to_play_handler(self, data, user_id):
        """
        Handles the card selection and play logic for a user.

        Parameters:
        data (dict): The data received from the client, containing gameId and newSelectedCards.
        user_id (str): The ID of the user who sent the request.

        Returns:
        None
        """

        game_id = data['gameId']
        card_id = data['newSelectedCards'][0]['cardId']
        # Retrieve the game room state using the GameManager
        game_room = self.game_manager.create_or_get_game(game_id)
        card_details = game_room.get_card_details_by_id(card_id)
        player = game_room.players.get(user_id)
        player.handle_state_change(PlayerState.IDLE)

        # Check if the current player is the one who sent the request
        if game_room.current_player == user_id:
           self.play_card(game_room=game_room, card_details=card_details)
        else:
            pass

    def play_same_rank_handler(self, data, user_id):
        """
        Handles the event when a player plays a card of the same rank.

        Parameters:
        data (dict): The data received from the client, containing the game ID and the card ID played.
        user_id (str): The ID of the player who played the card.

        Returns:
        None
        """
        game_id = data['gameId']
        card_id = data['newSelectedCards'][0]['cardId']
        game_room = self.game_manager.create_or_get_game(game_id)

        card_details = game_room.get_card_details_by_id(card_id)
        card_rank = card_details['rank']

        player = game_room.players.get(user_id)
        if player is not None:
            custom_log(f'Player found, hand: {player.hand}')
        else:
            custom_log('Player not found, returning early')
            return

        # Then, find the index of the card you're playing with
        try:
            card_index = player.hand.index(card_id)
        except ValueError:
            custom_log('Card to play not found in hand')
            return

        # Check the last played card's rank
        last_played_card = game_room.get_last_face_up_card()
        if last_played_card and 'rank' in last_played_card and last_played_card['rank'] == card_rank:

            # Remove the card by ID from the player's hand
            player.hand.remove(card_id)
            game_room.add_mod_face_up_cards(card_id)

            self.update_known_from_others(game_room, card_id)
            cards_left = player.check_remaining_cards()

            game_play_log(f'Turn: {game_room.turn_number}. {player.name} played same rank card: {card_details}. Hand: {player.hand} ({len(player.hand)}), Known Cards: {player.known_cards}, Unknown Cards: {player.unknown_cards}')

            if cards_left == 0: 
                game_room.winners_queue.append(user_id)
            else:
                if last_played_card['rank'].lower() in ['jack', 'queen']:
                    game_room.special_cards_queue.append(user_id)
                    game_play_log(f'Turn: {game_room.turn_number}. Special Card: {card_details}. {player.name} is added to special cards queue.')
                    game_play_log(f'Turn: {game_room.turn_number}. Special Play Queue: {game_room.special_cards_queue} \n')
    
            self.game_manager.msg_board_and_anim_update(data={
                'msg_id': 4,
                'action': 'play_same_rank',
                'username1': player.name,
                'card1': card_details,
                'cards_left': cards_left
            },
            game_room_id=game_room.game_id)

        else:
            player.handle_state_change(PlayerState.IDLE)
            if not game_room.face_down_cards:
                # Move all but the last card from face-up-cards to face-down-cards
                if len(game_room.face_up_cards) > 1:
                    game_room.face_down_cards = game_room.face_up_cards[:-1]
                    game_room.face_up_cards = game_room.face_up_cards[-1:]
                        
            drawn_card = random.choice(game_room.face_down_cards)  # Assuming face_down_cards contains card IDs
            game_room.face_down_cards.remove(drawn_card)
            player.hand.append(drawn_card)

            # Log game play    
            game_play_log(f'{player.name} played a wrong rank card: {card_details}. Hand: {player.hand}, Known Cards: {player.known_cards}, Unknown Cards: {player.unknown_cards}')
            self.game_manager.msg_board_and_anim_update(data={
                'msg_id': 5,
                'action': 'play_wrong_rank',
                'username1': player.name,
                'card1': card_details,
            },
            game_room_id=game_room.game_id)

    # SINGLE TURN PLAY
    def draw_card_from_deck(self, game_room, selectedDeck, current_player):
        """
        Draws a card from the specified deck in the game room.

        Parameters:
        game_room (GameRoom): The game room object containing the decks.
        selectedDeck (str): The deck from which to draw a card. It can be either 'face-up-deck' or 'face-down-deck'.

        Returns:
        drawn_card_id (str): The ID of the drawn card. Returns None if no card was drawn.
        """
        drawn_card_id = None
        card_details = {}

        if selectedDeck == 'face_up_deck' and game_room.face_up_cards:
            # Pop the last card object from the face-up deck
            card_object = game_room.face_up_cards.pop()
            drawn_card_id = card_object['id']
            card_details = game_room.get_card_details_by_id(drawn_card_id)
            
            self.game_manager.msg_board_and_anim_update(data={
                'msg_id': 2,
                'action': 'draw_from_fu_deck',
                'username1': current_player.name,
                'card1': card_details,
                'card1id': drawn_card_id,
            }, game_room_id=game_room.game_id, expect_reply=True, timeout=5.0)

        elif selectedDeck == 'face_down_deck':
            if not game_room.face_down_cards:
                # Move all but the last card from face-up-cards to face-down-cards
                if len(game_room.face_up_cards) > 1:
                    game_room.face_down_cards = game_room.face_up_cards[:-1]
                    game_room.face_up_cards = game_room.face_up_cards[-1:]

            if game_room.face_down_cards:
                drawn_card = random.choice(game_room.face_down_cards)
                drawn_card_id = drawn_card
                card_details = game_room.get_card_details_by_id(drawn_card_id)
                game_room.face_down_cards.remove(drawn_card)

                self.game_manager.msg_board_and_anim_update(data={
                    'msg_id': 1,
                    'action': 'draw_from_fd_deck',
                    'username1': current_player.name,
                    'card1id': drawn_card_id,
                }, game_room_id=game_room.game_id, expect_reply=True, timeout=10.0)
        
        game_play_log(f"Turn: {game_room.turn_number}. {current_player.name} selected card deck: {selectedDeck}.")
        
        if drawn_card_id is not None:
            return drawn_card_id

        return None

    def play_card(self, game_room, card_details):
        """
        Plays a card for the current player in the game room.

        Parameters:
        game_room (GameRoom): The game room where the card is being played.
        card_details (dict): The details of the card being played.

        Returns:
        None
        """
        current_player_id = game_room.current_player
        # Retrieve the current player's object directly.
        current_player = game_room.players.get(current_player_id)
        card_id = card_details['id']

        if not current_player:
            custom_log('Player not found')
            return

        played_card_index = None

        if current_player.active_card['id'] == card_id:
            game_play_log(f'{current_player.name} played their active card {card_details}.')
        else:
            # Check if the card ID is in the player's hand
            for index, card in enumerate(current_player.hand):
                if card == card_id:
                    played_card_index = index
                    # Replace the card at this index with the ID from current_player.active_card
                    current_player.hand[index] = current_player.active_card['id']
                    break
            game_play_log(f'Turn: {game_room.turn_number}. {current_player.name} played card {card_details}. Hand: {current_player.hand}, Known Cards: {current_player.known_cards}, Unknown Cards: {current_player.unknown_cards}')

        # Clear the active card setting
        current_player.set_active_card(None)
        current_player.handle_state_change(PlayerState.CALL_WINDOW)
        self.post_play(game_room, current_player, card_details, current_player_id, played_card_index)


    def post_play(self, game_room, current_player, card_details, current_player_id, played_card_index=False):
        """
        Performs actions after a card has been played.

        Parameters:
        game_room (GameRoom): The game room where the card was played.
        current_player (Player): The player who played the card.
        card_details (dict): The details of the card played.
        current_player_id (str): The ID of the current player.
        played_card_index (int, optional): The index of the played card in the current player's hand. Defaults to False.

        Returns:
        None
        """
        card_id = card_details['id']
        game_id = game_room.game_id

        self.game_manager.msg_board_and_anim_update(data={
            'msg_id': 3,
            'action': 'play_card',
            'username1': current_player.name,
            'card1': card_details,
        },
        game_room_id=game_id)
        game_room.add_mod_face_up_cards(card_id)
        self.game_manager.handle_state_change(GameStateEnum.SAME_RANK_WINDOW, game_room)
        time.sleep(4)

        play_card_rank = card_details['rank']

        self.update_known_from_others(game_room, card_id)

        if play_card_rank.lower() in ['jack', 'queen']:
            # Log game play    
            game_play_log(f'Turn: {game_room.turn_number}. Special Card: {card_details}. {current_player.name} is added to special cards queue.')
            game_room.special_cards_queue.append(current_player_id)
            game_play_log(f'Turn: {game_room.turn_number}. Special Play Queue: {game_room.special_cards_queue} \n')

        # SAME RANK BUFFER SECTION
        game_room.same_rank_buffer_active = True  # Set buffer active flag on game_room instance
        
        self.game_manager.set_all_players_state(game_room=game_room, new_state=PlayerState.SAME_RANK_WINDOW)

        time.sleep(10)

        if game_room.game_mode == 'solo':
            self.game_manager.computer_manager.same_rank_check(game_room, play_card_rank)

        for player in game_room.players.values():  # Adjust based on your data structure
            # Filter out the played card from known_from_others
            player.known_from_others = [entry for entry in player.known_from_others if entry[0] != card_id]

        self.game_manager.handle_state_change(GameStateEnum.LOADING, game_room)
        self.game_manager.set_all_players_state(game_room=game_room, new_state=PlayerState.IDLE)

        game_room.same_rank_buffer_active = False
        # END SAME RANK BUFFER

        self.end_of_turn(game_room=game_room, current_player_id=current_player_id, play_card_rank=play_card_rank)

    def end_of_turn(self, game_room, current_player_id, play_card_rank):
        """
        Handles the end of a player's turn in a game room.

        Args:
            game_room (GameRoom): The game room object containing all players.
            current_player_id (str): The ID of the player whose turn is ending.
            play_card_rank (str): The rank of the card that was played during the current player's turn.

        Returns:
            None
        """

        self.game_manager.set_all_players_state(game_room=game_room, new_state=PlayerState.IDLE)

        # SPECIAL RANK BUFFER SECTION
        if game_room.special_cards_queue:
            game_room.special_rank_buffer_active = True

            def process_next_user(game_room, play_card_rank, game_id):
                """
                Processes the next player in the special cards queue.

                Args:
                    game_room (GameRoom): The game room object containing all players.
                    play_card_rank (str): The rank of the card that was played during the current player's turn.
                    game_id (str): The ID of the game room.

                Returns:
                    None
                """
                game_room = game_room
                if game_room.special_cards_queue:

                    self.game_manager.handle_state_change(GameStateEnum.SPECIAL_RANK_WINDOW, game_room)
                    next_user_id = game_room.special_cards_queue.pop(0)

                    player = game_room.players.get(next_user_id)
                    if player is None:
                        # Handle the error appropriately, such as skipping to the next player or raising an exception
                        return

                    if play_card_rank.lower() == 'jack':
                        if player.player_type == 'user':
                            player.handle_state_change(PlayerState.JACK_SPECIAL)
                            time.sleep(10)
                        else:
                            self.game_manager.computer_manager.jack_special_play(game_room, player)
                        game_room = self.game_manager.create_or_get_game(game_id)
                    else:
                        if player.player_type == 'user':
                            player.handle_state_change(PlayerState.QUEEN_SPECIAL)
                            time.sleep(10)
                        else:
                            self.game_manager.computer_manager.queen_special_play(game_room, player)

                    player.handle_state_change(PlayerState.IDLE)
                    self.game_manager.handle_state_change(GameStateEnum.LOADING, game_room)

            while game_room.special_cards_queue:
                process_next_user(game_room, play_card_rank, game_room.game_id)
                game_play_log(f'Turn: {game_room.turn_number}. {game_room.special_cards_queue} left in Special Queue.')

            game_room.special_rank_buffer_active = False
            # END SPECIAL RANK BUFFER

        if game_room.winners_queue:
            self.game_manager.end_game_handler(game_room=game_room)
            return
        
        if game_room.final_round_queue:
            final_round_queue = game_room.final_round_queue
            
            if current_player_id in final_round_queue:
                final_round_queue = [player_id for player_id in final_round_queue if player_id != current_player_id]
            else:
                custom_log(f"Current player {current_player_id} not found in queue, no removal performed")
            
            if not final_round_queue:
                self.game_manager.end_game_handler(game_room)
                return
            else:
                game_room.final_round_queue = final_round_queue
                self.next_turn_handler(game_room, current_player_id)

            # Log game play    
            game_play_log(f'{current_player_id} is done playing in the final round.')
            self.game_manager.msg_board_and_anim_update(data={
                'msg_id': 8,
                'action': 'end_of_turn',
            },
            game_room_id=game_room.game_id)


        else:
            self.next_turn_handler(game_room, current_player_id)

    # HELPER FUNCTIONS
    def get_card_index(self, player, card_id):
        # Iterate over the list of cards in the player's hand
        for index, card in enumerate(player.hand):
            # Check if the current card's ID matches the card_id we're looking for
            if card['id'] == card_id:
                return index  # Return the index of the card

        # If no card matches the given card_id, return None
        return None

    def update_known_from_others(self, game_room, card_id, new_owner_id=None):
        """
        Updates the 'known_from_others' list for all players in a game room.
        If a card's new owner is the player themselves, the card is removed from their 'known_from_others' list.
        Additionally, if new_owner_id is None, the card is removed from all players' lists.
        If new_owner_id is the player_id, the player is skipped and no update is made to their list.

        Args:
            game_room: The game room object containing all players.
            card_id: The ID of the card that has changed hands.
            new_owner_id: The ID of the player who now owns the card, or None to remove the card from tracking.
        """
        # Iterate over each player in the game room
        for player_id, player in game_room.players.items():
            # Skip updating the list for the player who is the new owner of the card
            if player_id == new_owner_id:
                continue

            # Create a new list for known_from_others with updated information
            new_known_from_others = []
            card_found = False  # Flag to check if the card was in the player's known_from_others list
            
            for card_tuple in player.known_from_others:
                if card_tuple[0] != card_id:  # Keep cards that are not the target card
                    new_known_from_others.append(card_tuple)
                else:
                    card_found = True
            
            # If the card was found in the list and there's a new owner, update the list
            if card_found and new_owner_id is not None:
                new_known_from_others.append((card_id, new_owner_id))
            
            # Update the player's known_from_others list
            player.known_from_others = new_known_from_others

    def jack_special_play(self, selected_cards_data, game_room, user_id):
        """
        Handles the Jack special play action.

        Parameters:
        selected_cards_data (dict): Data containing the selected cards for the Jack swap.
        game_room (GameRoom): The game room where the action is taking place.
        user_id (str): The ID of the user performing the action.

        Returns:
        None
        """
        selected_cards = selected_cards_data.get("newSelectedCards", [])
        if len(selected_cards) != 2:
            custom_log("Error: There should be exactly two cards to swap.")
            return

        game_play_log(f'Turn: {game_room.turn_number}. Jack swap')
        game_play_log(f'Turn: {game_room.turn_number}. Cards to be swapped: {selected_cards}')

        # Validate presence of cards and identify players
        card1_id = selected_cards[0]["cardId"]
        card2_id = selected_cards[1]["cardId"]
        
        player1 = None
        player2 = None
        card1_index = None
        card2_index = None

        for player in game_room.players.values():
            if card1_id in player.hand:
                player1 = player
                card1_index = player.hand.index(card1_id)
            if card2_id in player.hand:
                player2 = player
                card2_index = player.hand.index(card2_id)
            if player1 and player2:
                break

        if not all([player1, player2]):
            custom_log("Error: One or both cards are not found in any player's hand.")
            return
        
        game_play_log(f'Turn: {game_room.turn_number}. {player1.name} hand before jack swap. Hand: {player1.hand}, Known Cards: {player1.known_cards}, Unknown Cards: {player1.unknown_cards}, Known from others: {player1.known_from_others}')
        game_play_log(f'Turn: {game_room.turn_number}. {player2.name} hand before jack swap. Hand: {player2.hand}, Known Cards: {player2.known_cards}, Unknown Cards: {player2.unknown_cards}, Known from others: {player2.known_from_others}')

        self.game_manager.msg_board_and_anim_update(data={
            'msg_id': 6,
            'action': 'jack_swap',
            'username1': player1.name,
            'username2': player2.name,
            'card1id': card1_id,
            'card2id': card2_id,
        },
        game_room_id=game_room.game_id)

        try:
            emit_data = {
                'card1index': card1_index,
                'username': player1.name,
                'card2index': card2_index,
                'username2': player2.name
            }

            # Swap the cards based on index
            player1.hand[card1_index], player2.hand[card2_index] = player2.hand[card2_index], player1.hand[card1_index]

            # If both cards belong to the same player, update their hand only once
            if player1 == player2:
                player1.hand[card1_index], player1.hand[card2_index] = player1.hand[card2_index], player1.hand[card1_index]

            # Update known and unknown cards
            def update_known_unknown(player, new_card_id, old_card_id):
                # Remove old card
                if old_card_id in player.known_cards:
                    player.known_cards.remove(old_card_id)
                if old_card_id in player.unknown_cards:
                    player.unknown_cards.remove(old_card_id)

                # Add new card
                if new_card_id in [card[0] for card in player.known_from_others]:
                    player.known_cards.append(new_card_id)
                    player.known_from_others = [card for card in player.known_from_others if card[0] != new_card_id]
                else:
                    if new_card_id not in player.known_cards and new_card_id not in player.unknown_cards:
                        player.unknown_cards.append(new_card_id)

            # Update for player1
            update_known_unknown(player1, player1.hand[card1_index], card1_id)
            # Update for player2 only if they are different players
            if player1 != player2:
                update_known_unknown(player2, player2.hand[card2_index], card2_id)
            else:
                # If it's the same player, ensure indices are correctly managed
                update_known_unknown(player1, player1.hand[card2_index], card2_id)

            # Update known_from_others for all players
            self.update_known_from_others(game_room, card1_id, player1.id)
            self.update_known_from_others(game_room, card2_id, player2.id)

            game_play_log(f'Turn: {game_room.turn_number}. {player1.name} hand after jack swap. Hand: {player1.hand}, Known Cards: {player1.known_cards}, Unknown Cards: {player1.unknown_cards}, Known from others: {player1.known_from_others}')
            game_play_log(f'Turn: {game_room.turn_number}. {player2.name} hand after jack swap. Hand: {player2.hand}, Known Cards: {player2.known_cards}, Unknown Cards: {player2.unknown_cards}, Known from others: {player2.known_from_others}')
            game_play_log(f'Turn: {game_room.turn_number}. End of Jack swap \n')

        except IndexError:
            custom_log("Error: Card index out of range.", True)
            return

    def queen_special_play(self, data, game_room, user_id):
        """
        Handles the queen special play action.

        Parameters:
        data (dict): The data received from the client.
        game_room (GameRoom): The game room where the action is taking place.
        user_id (str): The ID of the player performing the action.

        Returns:
        None
        """
        selected_cards = data.get("newSelectedCards")
        if not selected_cards:
            custom_log("Error: No selected cards provided.")
            return
        
        owner_id = selected_cards[0]["playerId"]
        card_id = selected_cards[0]['cardId']
        owner = game_room.players.get(owner_id)
        player = game_room.players.get(user_id)
        card_details = game_room.get_card_details_by_id(card_id)

        game_play_log(f'Turn: {game_room.turn_number}. Queen question')
        game_play_log(f'Turn: {game_room.turn_number}. {player.name} (Player) hand before Queen Question. {player.hand}, Known Cards: {player.known_cards}, Unknown Cards: {player.unknown_cards}, Known from others: {player.known_from_others}')
        game_play_log(f'Turn: {game_room.turn_number}. {owner.name} (Owner) hand before Queen Question. {owner.hand}, Known Cards: {owner.known_cards}, Unknown Cards: {owner.unknown_cards}, Known from others: {owner.known_from_others}')
    
        if owner:
            try:
                card_index = owner.hand.index(card_id)
            except ValueError:
                custom_log(f"Card ID {card_id} not found in player's hand.")
                return
        else:
            custom_log(f"Player with ID {owner_id} not found.")
            return

        if owner_id not in game_room.players:
            custom_log(f"Error: Player with ID {owner_id} does not exist.")
            return

        if player.player_type == 'computer':
            if owner_id == user_id:
                if card_id not in player.known_cards:
                    player.known_cards.append(card_id)
                try:
                    player.unknown_cards.remove(card_id)
                except ValueError:
                    custom_log(f"Card {card_id} not found in unknown_cards of player {user_id}")
            else:
                if not any(c[0] == card_id for c in player.known_from_others):
                    player.known_from_others.append((card_id, owner_id))

            self.game_manager.msg_board_and_anim_update(data={
                'msg_id': 7,
                'action': 'queen_question',
                'username1': player.name,
                'username2': owner.name,
                'index1': card_index,
            },
            game_room_id=game_room.game_id)

        else:
            self.game_manager.msg_board_and_anim_update(data={
                'msg_id': 7,
                'action': 'queen_question',
                'username1': player.name,
                'username1type': player.player_type,
                'username2': owner.name,
                'index1': card_index,
                'card1': card_details,
            },
            game_room_id=game_room.game_id)

        game_play_log(f'Turn: {game_room.turn_number}. {player.name} (Player) hand after Queen Question. {player.hand}, Known Cards: {player.known_cards}, Unknown Cards: {player.unknown_cards}, Known from others: {player.known_from_others}')
        game_play_log(f'Turn: {game_room.turn_number}. {owner.name} (Owner) hand after Queen Question. {owner.hand}, Known Cards: {owner.known_cards}, Unknown Cards: {owner.unknown_cards}, Known from others: {owner.known_from_others}')
        game_play_log(f'Turn: {game_room.turn_number}. End of Queen question \n')

    def special_rank_play_handler(self, data, user_id):
        """
        Handles the special rank play action.

        Parameters:
        data (dict): The data received from the client.
        user_id (str): The ID of the player performing the action.

        Returns:
        None
        """
        game_id = data['gameId']
        game_room = self.game_manager.create_or_get_game(game_id)
        player = game_room.players.get(user_id)
        player.handle_state_change(PlayerState.IDLE)
        specialRank = data['playerState']

        if specialRank == 'JACK_SPECIAL':
            self.jack_special_play(data, game_room, user_id)
            pass
        else:
            self.queen_special_play(data, game_room, user_id)
            pass

    def next_turn_handler(self, game_room, current_player_id=None):
        """
        Handles the next turn in the game.

        Parameters:
        game_room (GameRoom): The game room where the next turn is taking place.
        current_player_id (str): The ID of the current player. If not provided, a random player will be chosen.

        Returns:
        None
        """
        if not current_player_id:
            game_room.current_player = random.choice(list(game_room.players.keys()))
        else:
            current_player = game_room.players.get(game_room.current_player)
            game_room.turn_number += 1
            player_ids = list(game_room.players.keys())
            next_index = (player_ids.index(current_player_id) + 1) % len(player_ids)
            game_room.current_player = player_ids[next_index]

        player = game_room.players.get(game_room.current_player)
        self.game_manager.handle_state_change(GameStateEnum.PLAYER_TURN, game_room)
        if player.player_type == 'computer':
            self.game_manager.computer_turn(game_room, player.id)
        else:
            player.handle_state_change(PlayerState.CHOOSING_DECK)