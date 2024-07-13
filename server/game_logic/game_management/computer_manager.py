import random
import time
from app_logging.server.custom_logging import custom_log, log_function_call, game_play_log, add_logging_to_module, FUNCTION_LOGGING_ENABLED


class ComputerManager:
    def __init__(self, event_manager, round_manager):
        self.event_manager = event_manager
        self.round_manager = round_manager
    
    def randomizer(self, low, high):
        return random.randint(low, high)

    def computer_turn(self, game_room, player_id):
        """
        This function simulates a computer player's turn in a card game.
        It draws a card from the deck, checks for a matching card in the hand,
        and plays the card. If no matching card is found, it selects a card
        based on certain criteria.

        Parameters:
        game_room (GameRoom): The game room where the turn is happening.
        player_id (str): The ID of the player who's turn it is.

        Returns:
        None
        """
        player = game_room.players.get(player_id)
        if not player:
            return

        # Decide which deck to use based on a random choice
        randomizer = self.randomizer(1, 15)
        selectedDeck = 'face_up_deck' if randomizer == 15 else 'face_down_deck'
        drawn_card_id = self.round_manager.draw_card_from_deck(game_room=game_room, selectedDeck=selectedDeck, current_player=player)
        time.sleep(5)

        drawn_card_details = game_room.get_card_details_by_id(drawn_card_id)
        
        # Validate drawn_card_details
        if not isinstance(drawn_card_details, dict) or 'id' not in drawn_card_details:
            return

        if selectedDeck == 'face_up_deck':
            self.round_manager.update_known_from_others(game_room, drawn_card_id, player_id)

        player.set_active_card(drawn_card_details)  # This method now takes a card ID and sets it as the active card

        # Log game play    
        game_play_log(f'Turn: {game_room.turn_number}. {player.name} active card before play. {player.active_card}: {drawn_card_details}')

        if player.unknown_cards:
            play_card_id = random.choice(player.unknown_cards)
        else:
            play_card_id = None
            matched_cards = []

            # Look for a card in hand that matches the rank of the drawn card
            for card_id in player.hand:
                try:
                    card_details = game_room.get_card_details_by_id(card_id)

                    # Validate card_details
                    if not isinstance(card_details, dict):
                        continue

                    # Check if the rank key exists in card details and matches the drawn card's rank
                    if 'rank' in card_details and card_details['rank'] == drawn_card_details['rank']:
                        matched_cards.append(card_id)
                except Exception as e:
                    continue

            if matched_cards:
                play_card_id = random.choice(matched_cards)
            else:
                # Retrieve details of all cards in hand
                hand_details = []
                for card_id in player.known_cards:
                    card_details = game_room.get_card_details_by_id(card_id)
                    # Validate card_details
                    if not isinstance(card_details, dict):
                        continue
                    hand_details.append(card_details)

                # Get details of the active card if available
                active_card_details = game_room.get_card_details_by_id(player.active_card['id']) if player.active_card else None

                if active_card_details and not isinstance(active_card_details, dict):
                    active_card_details = None

                # Filter out cards with rank 'jack' and values 0, 1, 5, 6
                valid_hand_cards = [
                    card for card in hand_details
                    if card['rank'].lower() != 'jack' and card['value'] not in {0, 1, 5, 6}
                ]

                if active_card_details and active_card_details['rank'].lower() != 'jack' and active_card_details['value'] not in {0, 1, 5, 6}:
                    valid_hand_cards.append(active_card_details)

                if valid_hand_cards:
                    # Select the card with the highest value, random choice if multiple have the same highest value
                    highest_value_card = max(valid_hand_cards, key=lambda card: card['value'])
                    highest_value_cards = [card for card in valid_hand_cards if card['value'] == highest_value_card['value']]
                    play_card_id = random.choice(highest_value_cards)['id']

        self.play_card(game_room=game_room, player=player, play_card_id=play_card_id)

    def play_card(self, game_room, player, play_card_id):
        """
        Play a card from the player's hand.

        Parameters:
        game_room (GameRoom): The game room where the card is being played.
        player (ComputerPlayer): The player who is playing the card.
        play_card_id (str): The unique identifier of the card being played.

        Returns:
        None
        """
        card_details = game_room.get_card_details_by_id(play_card_id)
        player_id = player.id

        # Validate card_details
        if not isinstance(card_details, dict):
            return

        if play_card_id == player.active_card['id']:
            # If the played card is the active card, skip the hand logic
            game_play_log(f'Turn: {game_room.turn_number}. {player.name} played their active card {player.active_card}: {card_details}')
            
            # Pass the played_card_id directly to the post_play function
            self.round_manager.post_play(game_room, player, card_details, player_id, None)

            # Set the active card to None
            player.set_active_card(None)
        elif play_card_id in player.hand:
            played_card_index = player.hand.index(play_card_id)
            # Remove the played card ID from the player's hand
            player.hand.pop(played_card_index)
            
            # Remove card ID from known and unknown lists if present
            player.known_cards = [card_id for card_id in player.known_cards if card_id != play_card_id]
            player.unknown_cards = [card_id for card_id in player.unknown_cards if card_id != play_card_id]

            active_card_id = player.active_card['id']
            # Assuming active_card is a dictionary containing at least the 'id'
            player.hand.insert(played_card_index, active_card_id)
            player.known_cards.append(active_card_id)
            
            # Log game play    
            game_play_log(f'Turn: {game_room.turn_number}. {player.name} played card {card_details}. Hand: {player.hand}, Known Cards: {player.known_cards}, Unknown Cards: {player.unknown_cards}')

            player.set_active_card(None)

            # Pass the played_card_index to the post_play function
            self.round_manager.post_play(game_room, player, card_details, player_id, played_card_index)

    def jack_special_play(self, game_room, player):
        """
        Handle the special play action when a Jack card is played.

        Parameters:
        game_room (GameRoom): The game room where the special play is happening.
        player (ComputerPlayer): The player who played the Jack card.

        Returns:
        None
        """
        highest_value_cards = []  # List to hold cards with the highest value
        highest_value = 0  # Initial highest value
        total_value = sum(game_room.get_card_details_by_id(card_id)['value'] for card_id in player.known_cards)
        card_count = len(player.known_cards)
        selected_cards = []  # Data structure to store selected card details

        def select_cards():
            """
            Select cards for the special play action.

            Returns:
            list: A list of selected card details.
            """
            players_card_counts = []

            # Collect data about other players' hands
            for player_id, room_player in game_room.players.items():
                if player_id != player.id:
                    players_card_counts.append((player_id, len(room_player.hand)))

            # Sort players by the number of cards in their hand
            players_card_counts.sort(key=lambda x: x[1])

            # Ensure there are enough players
            if len(players_card_counts) < 2:
                return []  # Not enough players to choose from

            # Identify players with the least cards
            least_cards = [p for p in players_card_counts if p[1] == players_card_counts[0][1]]
            if len(least_cards) > 2:
                selected_players = random.sample(least_cards, 2)  # Randomly select 2 if more than 2 players have the same least count
            elif len(players_card_counts) > 1:
                # Include the next least if less than two at the lowest count
                least_cards += [p for p in players_card_counts if p[1] == players_card_counts[1][1]]
                selected_players = random.sample(least_cards, 2)
            else:
                # If all edge cases fail, select the available ones
                selected_players = least_cards

            # Randomly select a card from the chosen player's hand
            for player_id, _ in selected_players:
                room_player = game_room.players[player_id]
                if room_player.hand:
                    card_index = random.randint(0, len(room_player.hand) - 1)
                    selected_card_id = room_player.hand[card_index]
                    # Append card data including player id and index
                    selected_cards.append({"playerId": player_id, "cardId": selected_card_id, "cardIndex": card_index})
            
            return selected_cards

        if game_room.final_round_queue:
            if player.unknown_cards:
                # If there are unknown cards, select a random card from the unknown cards
                selected_card_id = random.choice(player.unknown_cards)
                card_index = self.get_card_index(player, selected_card_id)
                selected_cards.append({"playerId": player.id, "cardId": selected_card_id, "cardIndex": card_index})

            elif (card_count == 2 and total_value == 0) or (card_count == 1 and total_value <= 1):
                # Fetch selected cards based on the conditions
                selected_cards = select_cards()
                if not selected_cards:  # Check if any cards were selected
                    return None  # Return None if no cards were selected

            else:
                for card_id in player.known_cards:
                    card_details = game_room.get_card_details_by_id(card_id)
                    card_value = card_details.get('value', 0)

                    # Check if the current card's value is greater than the current highest value
                    if card_value > highest_value:
                        highest_value = card_value  # Update the highest value
                        highest_value_cards = [card_details]  # Start a new list with this card
                    elif card_value == highest_value:
                        highest_value_cards.append(card_details)  # Add this card to the list of highest value cards

                # Randomly select one card from the list of highest value cards
                if highest_value_cards:
                    selected_card_details = random.choice(highest_value_cards)
                    card_index = self.get_card_index(player, selected_card_details['id'])
                    selected_cards.append({"playerId": player.id, "cardId": selected_card_details['id'], "cardIndex": card_index})

        else:
            # Handle selected cards outside FINAL_ROUND state
            selected_cards = select_cards()
            if not selected_cards:
                return None  # Return None if no cards were selected

        # Prepare the data structure to send to round_manager.jack_special_play
        selected_cards_data = {"newSelectedCards": selected_cards}
        
        # Emit data to another function for processing
        self.round_manager.jack_special_play(selected_cards_data, game_room, player.id)

    def queen_special_play(self, game_room, player):
        """
        This function handles the special play action when a Queen card is played.
        If the game is in the final round, it selects a card from the called user's hand.
        Otherwise, it selects a card from a player with the least number of cards.

        Parameters:
        game_room (GameRoom): The game room where the special play is happening.
        player (ComputerPlayer): The player who played the Queen card.

        Returns:
        None
        """
        selected_cards_data = []

        if game_room.final_round_queue:
            called_user = game_room.players.get(game_room.called_user_id)
            if called_user.hand:
                selected_card_id = random.choice(called_user.hand)
                card_index = self.get_card_index(called_user, selected_card_id)
                selected_cards_data.append({"playerId": called_user.id, "cardId": selected_card_id, "cardIndex": card_index})
        else:
            players_card_counts = []

            # Collect data about other players' hands
            for player_id, room_player in game_room.players.items():
                if player_id != player.id:
                    players_card_counts.append((player_id, len(room_player.hand)))

            # Sort players by the number of cards in their hand
            players_card_counts.sort(key=lambda x: x[1])

            # Ensure there are enough players
            if len(players_card_counts) < 1:
                return

            # Identify players with the least cards
            least_cards = [p for p in players_card_counts if p[1] == players_card_counts[0][1]]
            if len(least_cards) >= 1:
                selected_players = random.sample(least_cards, 1)  # Choosing one randomly

            # Randomly select a card from the chosen player's hand
            for player_id, _ in selected_players:
                room_player = game_room.players[player_id]
                if room_player.hand:
                    card_index = random.randint(0, len(room_player.hand) - 1)
                    selected_card_id = room_player.hand[card_index]
                    # Append card data including player id and index
                    selected_cards_data.append({"playerId": player_id, "cardId": selected_card_id, "cardIndex": card_index})

        # Pass data to another function for processing
        if selected_cards_data:
            data_to_pass = {"newSelectedCards": selected_cards_data}
            self.round_manager.queen_special_play(data_to_pass, game_room, player.id)

    def same_rank_check(self, game_room, last_played_rank):
        """
        This function checks if any computer player has a card with the same rank as the last played card.
        If a match is found, the card is played and the relevant actions are performed.

        Parameters:
        game_room (GameRoom): The game room where the check is happening.
        last_played_rank (str): The rank of the last played card.

        Returns:
        None
        """
        if last_played_rank:

            for player_id, player in game_room.players.items():
                if player.player_type == 'computer':
                    matched_cards = []
                    
                    # Start logging and processing each card
                    for card_id in player.known_cards:
                        try:
                            card_details = game_room.get_card_details_by_id(card_id)
                            
                            # Check if the rank key exists in card details and matches the last played rank
                            if 'rank' in card_details and card_details['rank'] == last_played_rank:
                                matched_cards.append(card_id)
                        except Exception as e:
                            continue

                    if matched_cards:
                        for card_id in matched_cards:
                            try:
                                card_details = game_room.get_card_details_by_id(card_id)
                                game_play_log(f'Turn: {game_room.turn_number}. {player.name} played same rank card {card_details}. Hand: {player.hand} ({len(player.hand)}), Known Cards: {player.known_cards}, Unknown Cards: {player.unknown_cards}')

                                player.hand.remove(card_id)
                                player.known_cards.remove(card_id)
                                game_room.add_mod_face_up_cards(card_id)
                                self.round_manager.update_known_from_others(game_room, card_id)
                                # Check if a special action needs to be triggered
                                if last_played_rank.lower() in ['jack', 'queen']:
                                    game_play_log(f'Turn: {game_room.turn_number}. Special Card: {card_details}. {player.name} is added to special cards queue.')
                                    game_room.special_cards_queue.append(player_id)
                                    game_play_log(f'Turn: {game_room.turn_number}. Special Play Queue: {game_room.special_cards_queue} \n')

                                    special_rank = last_played_rank.lower()
                                    getattr(self, f'{special_rank}_special_play')(game_room, player)

                                cards_left = player.check_remaining_cards()
    
                                self.round_manager.msg_board_and_anim_update(data={
                                    'msg_id': 4,
                                    'action': 'play_same_rank',
                                    'username1': player.name,
                                    'card1': card_details,
                                    'cards_left': cards_left,
                                },
                                game_room_id=game_room.game_id)

                                if cards_left == 0: 
                                    game_room.winners_queue.append(player_id)

                                    # Log game play    
                                    game_play_log(f'{player_id} has no cards left. Hand: {player.hand}, Known Cards: {player.known_cards}, Unknown Cards: {player.unknown_cards}')
                            except Exception as e:
                                custom_log(f"Error during processing of card {card_id}: {e}")