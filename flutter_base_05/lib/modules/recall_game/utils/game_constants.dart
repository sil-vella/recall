/// Game constants for the Recall card game
class GameConstants {
  // Game settings
  static const int MIN_PLAYERS = 2;
  static const int MAX_PLAYERS = 6;
  static const int CARDS_PER_PLAYER = 7;
  static const int POINTS_TO_WIN = 50;
  
  // Game phases
  static const String PHASE_WAITING = 'waiting';
  static const String PHASE_SETUP = 'setup';
  static const String PHASE_PLAYING = 'playing';
  static const String PHASE_OUT_OF_TURN = 'out_of_turn';
  static const String PHASE_SAME_RANK_WINDOW = 'same_rank_window';
  static const String PHASE_SPECIAL_PLAY_WINDOW = 'special_play_window';
  static const String PHASE_RECALL = 'recall';
  static const String PHASE_FINISHED = 'finished';
  
  // Game status
  static const String STATUS_ACTIVE = 'active';
  static const String STATUS_PAUSED = 'paused';
  static const String STATUS_ENDED = 'ended';
  static const String STATUS_ERROR = 'error';
  
  // Player status
  static const String PLAYER_STATUS_WAITING = 'waiting';
  static const String PLAYER_STATUS_READY = 'ready';
  static const String PLAYER_STATUS_PLAYING = 'playing';
  static const String PLAYER_STATUS_FINISHED = 'finished';
  static const String PLAYER_STATUS_DISCONNECTED = 'disconnected';
  
  // Player types
  static const String PLAYER_TYPE_HUMAN = 'human';
  static const String PLAYER_TYPE_COMPUTER = 'computer';
  
  // AI difficulty levels
  static const String AI_DIFFICULTY_EASY = 'easy';
  static const String AI_DIFFICULTY_MEDIUM = 'medium';
  static const String AI_DIFFICULTY_HARD = 'hard';
  
  // Special power types
  static const String SPECIAL_POWER_QUEEN = 'queen';
  static const String SPECIAL_POWER_JACK = 'jack';
  static const String SPECIAL_POWER_ADDED = 'added_power';
  static const String SPECIAL_POWER_NONE = 'none';
  
  // Card suits
  static const String SUIT_HEARTS = 'hearts';
  static const String SUIT_DIAMONDS = 'diamonds';
  static const String SUIT_CLUBS = 'clubs';
  static const String SUIT_SPADES = 'spades';
  
  // Card ranks
  static const String RANK_ACE = 'ace';
  static const String RANK_TWO = 'two';
  static const String RANK_THREE = 'three';
  static const String RANK_FOUR = 'four';
  static const String RANK_FIVE = 'five';
  static const String RANK_SIX = 'six';
  static const String RANK_SEVEN = 'seven';
  static const String RANK_EIGHT = 'eight';
  static const String RANK_NINE = 'nine';
  static const String RANK_TEN = 'ten';
  static const String RANK_JACK = 'jack';
  static const String RANK_QUEEN = 'queen';
  static const String RANK_KING = 'king';
  
  // WebSocket events
  static const String WS_EVENT_GAME_JOINED = 'recall_game_joined';
  static const String WS_EVENT_GAME_LEFT = 'recall_game_left';
  static const String WS_EVENT_PLAYER_JOINED = 'recall_player_joined';
  static const String WS_EVENT_PLAYER_LEFT = 'recall_player_left';
  static const String WS_EVENT_GAME_STARTED = 'recall_game_started';
  static const String WS_EVENT_GAME_ENDED = 'recall_game_ended';
  static const String WS_EVENT_TURN_CHANGED = 'recall_turn_changed';
  static const String WS_EVENT_CARD_PLAYED = 'recall_card_played';
  static const String WS_EVENT_RECALL_CALLED = 'recall_recall_called';
  static const String WS_EVENT_GAME_STATE_UPDATED = 'recall_game_state_updated';
  static const String WS_EVENT_ERROR = 'recall_error';
  
  // Player actions
  static const String ACTION_JOIN_GAME = 'recall_join_game';
  static const String ACTION_LEAVE_GAME = 'recall_leave_game';
  static const String ACTION_PLAY_CARD = 'recall_player_action';
  static const String ACTION_CALL_RECALL = 'recall_player_action';
  static const String ACTION_USE_SPECIAL_POWER = 'recall_player_action';
  
  // UI constants
  static const double CARD_WIDTH = 80.0;
  static const double CARD_HEIGHT = 120.0;
  static const double CARD_SPACING = 10.0;
  static const double HAND_HEIGHT = 140.0;
  static const double PLAYER_AVATAR_SIZE = 60.0;
  static const double GAME_BOARD_PADDING = 20.0;
  
  // Animation durations
  static const Duration CARD_ANIMATION_DURATION = Duration(milliseconds: 300);
  static const Duration TURN_ANIMATION_DURATION = Duration(milliseconds: 500);
  static const Duration GAME_STATE_ANIMATION_DURATION = Duration(milliseconds: 200);
  
  // Colors
  static const int COLOR_RED = 0xFFE74C3C;
  static const int COLOR_BLACK = 0xFF2C3E50;
  static const int COLOR_GOLD = 0xFFF39C12;
  static const int COLOR_SILVER = 0xFFBDC3C7;
  static const int COLOR_BRONZE = 0xFFE67E22;
  
  // Game messages
  static const String MSG_GAME_JOINED = 'Joined game successfully';
  static const String MSG_GAME_LEFT = 'Left game';
  static const String MSG_PLAYER_JOINED = 'Player joined the game';
  static const String MSG_PLAYER_LEFT = 'Player left the game';
  static const String MSG_GAME_STARTED = 'Game started!';
  static const String MSG_GAME_ENDED = 'Game ended';
  static const String MSG_TURN_CHANGED = 'Turn changed';
  static const String MSG_CARD_PLAYED = 'Card played';
  static const String MSG_RECALL_CALLED = 'Recall called!';
  static const String MSG_SPECIAL_POWER_USED = 'Special power used';
  static const String MSG_NOT_YOUR_TURN = 'Not your turn';
  static const String MSG_CANNOT_CALL_RECALL = 'Cannot call recall at this time';
  static const String MSG_INVALID_CARD = 'Invalid card';
  static const String MSG_GAME_FULL = 'Game is full';
  static const String MSG_GAME_NOT_FOUND = 'Game not found';
  static const String MSG_CONNECTION_ERROR = 'Connection error';
  static const String MSG_UNKNOWN_ERROR = 'Unknown error occurred';
  
  // Error codes
  static const String ERROR_NOT_IN_GAME = 'NOT_IN_GAME';
  static const String ERROR_NOT_YOUR_TURN = 'NOT_YOUR_TURN';
  static const String ERROR_CANNOT_CALL_RECALL = 'CANNOT_CALL_RECALL';
  static const String ERROR_INVALID_CARD = 'INVALID_CARD';
  static const String ERROR_GAME_FULL = 'GAME_FULL';
  static const String ERROR_GAME_NOT_FOUND = 'GAME_NOT_FOUND';
  static const String ERROR_CONNECTION_FAILED = 'CONNECTION_FAILED';
  static const String ERROR_UNKNOWN = 'UNKNOWN_ERROR';
  
  // Game settings
  static const Map<String, dynamic> DEFAULT_GAME_SETTINGS = {
    'maxPlayers': MAX_PLAYERS,
    'cardsPerPlayer': CARDS_PER_PLAYER,
    'pointsToWin': POINTS_TO_WIN,
    'allowComputerPlayers': true,
    'aiDifficulty': AI_DIFFICULTY_MEDIUM,
    'autoStart': false,
    'timeLimit': null,
    'specialPowersEnabled': true,
    'addedPowerCardsEnabled': true,
  };
  
  // AI behavior settings
  static const Map<String, dynamic> AI_BEHAVIOR_SETTINGS = {
    'easy': {
      'aggression': 0.3,
      'riskTolerance': 0.2,
      'recallThreshold': 0.8,
      'specialPowerUsage': 0.4,
    },
    'medium': {
      'aggression': 0.5,
      'riskTolerance': 0.5,
      'recallThreshold': 0.6,
      'specialPowerUsage': 0.7,
    },
    'hard': {
      'aggression': 0.8,
      'riskTolerance': 0.8,
      'recallThreshold': 0.4,
      'specialPowerUsage': 0.9,
    },
  };
} 