from enum import Enum, auto

class GameStateEnum(Enum):
    PREGAME = auto()
    SOLO_GAME_READY = auto()
    MULTIPLAYER_GAME_READY = auto()
    REVEAL_CARDS = auto()
    PLAYER_TURN = auto()
    LOADING = auto()
    SAME_RANK_WINDOW = auto()
    SPECIAL_RANK_WINDOW = auto()
    GAME_OVER = auto()

class GameState:
    def __init__(self, event_manager):
        self.event_manager = event_manager
        self.games = {}  # Maps room IDs to game room states
        self._observers = []
        self._state = None
        self._state_data = None

    def attach(self, observer):
        if observer not in self._observers:
            self._observers.append(observer)

    def notify(self):
        for observer in self._observers:
            observer(self._state, self._state_data)

    def set_state(self, state, data=None):
        if state != self._state:
            self._state = state
            self._state_data = data
            self.notify()
