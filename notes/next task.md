# next task

create new game on multi .. no change


# msg board data structure

            emit_data = {
                'msg_id': 1,
                'action': 'draw_from_deck',
                'username1': current_player.name,
                'card1': '',
                'card2': '',
                'deck': selected_deck,
                'cards_left': '',
                'index': '',
                'index1': '',
                'index2':'',
            }

preGameState: {
gameData: {
gameMode: null,
gameState: 'pre_game',
shareLink: null,
gameId: null,
activeGameData: null,
numOfOpponents: null,
},
playerData: {
gameCreatorUsername: null,
}
},
activeGamePlayState: {
game_id: null,
game_mode: null,
players: {},
current_player: null,
special_cards_queue: null,
face_down_cards: null,
face_up_cards: null,
winners_queue: null,
called_user_id: null,
game_play_state: 'LOADING'
},
userSection: {
name: null,
id: null,
player_type: null,
hand: null,
score: null,
known_cards: null,
unknown_cards: null,
known_from_others: null,
active_card: null,
state: 'IDLE',
},

    "gameData": {
        "gameMode": "solo",
        "gameState": "solo_game_ready",
        "gameId": "You-ocy8LT4ozjIxtbDdAAAB",
        "numOfOpponents": "2"
    },
    "playerData": {
        "gameCreatorUsername": "You",
        "username": "You",
        "player_id": "ocy8LT4ozjIxtbDdAAAB",
        "player_type": "user"
    }
