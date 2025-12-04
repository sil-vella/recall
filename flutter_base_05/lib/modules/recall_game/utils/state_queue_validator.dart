/// State Queue Validator for Recall Game
///
/// This file provides shared state update validation and queuing functionality
/// that is identical across Flutter and Dart backend implementations.
///
/// It handles:
/// - State update validation using a comprehensive schema
/// - Queue system for sequential state update processing
/// - Consistent validation rules across platforms

import 'dart:async';
import 'field_specifications.dart';
import '../../../tools/logging/logger.dart';

/// Callback type for applying validated state updates (platform-specific)
typedef StateUpdateHandler = void Function(Map<String, dynamic> validatedUpdate);

/// State Queue Validator
///
/// Singleton class that validates and queues state updates for sequential processing.
/// All validation logic is platform-agnostic and shared between Flutter and Dart backend.
class StateQueueValidator {
  static StateQueueValidator? _instance;
  static StateQueueValidator get instance {
    _instance ??= StateQueueValidator._internal();
    return _instance!;
  }

  StateQueueValidator._internal();

  /// Queue of pending state updates
  final List<Map<String, dynamic>> _updateQueue = [];

  /// Flag to track if queue is currently processing
  bool _isProcessing = false;

  /// Handler for applying validated updates (platform-specific)
  StateUpdateHandler? _updateHandler;

  /// Logger instance (must be declared before constructor)
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = true;

  /// Define the complete state schema with validation rules
  /// Must remain identical across Flutter and Dart backend implementations
  static const Map<String, RecallStateFieldSpec> _stateSchema = {
    // User Context
    'userId': RecallStateFieldSpec(
      type: String,
      required: true,
      description: 'Current user ID from authentication',
    ),
    'username': RecallStateFieldSpec(
      type: String,
      required: true,
      description: 'Current username from authentication',
    ),
    'playerId': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Player ID in current game session',
    ),
    'isRoomOwner': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether current user is the room owner',
    ),
    'isMyTurn': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether it is currently the user\'s turn',
    ),
    'turnTimeout': RecallStateFieldSpec(
      type: int,
      defaultValue: 30,
      description: 'Turn timeout duration in seconds',
    ),
    'turnStartTime': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'ISO timestamp when the current turn started',
    ),
    'playerStatus': RecallStateFieldSpec(
      type: String,
      required: false,
      allowedValues: [
        'waiting', 'ready', 'playing', 'same_rank_window', 'playing_card', 
        'drawing_card', 'queen_peek', 'jack_swap', 'peeking', 'initial_peek', 
        'finished', 'disconnected', 'winner'
      ],
      description: 'Current player status (waiting, ready, playing, drawing_card, etc.)',
    ),
    'canCallRecall': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether user can call recall in current game state',
    ),
    'canPlayCard': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether user can play a card in current game state',
    ),
    
    // Room Context
    'currentRoomId': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'ID of currently joined room',
    ),
    'permission': RecallStateFieldSpec(
      type: String,
      allowedValues: ['public', 'private'],
      defaultValue: 'public',
      description: 'Room visibility setting',
    ),
    'currentSize': RecallStateFieldSpec(
      type: int,
      min: 0,
      max: 12,
      defaultValue: 0,
      description: 'Current number of players in room',
    ),
    'maxSize': RecallStateFieldSpec(
      type: int,
      min: 2,
      max: 12,
      defaultValue: 4,
      description: 'Maximum allowed players in room',
    ),
    'minSize': RecallStateFieldSpec(
      type: int,
      min: 2,
      max: 8,
      defaultValue: 2,
      description: 'Minimum required players to start game',
    ),
    'isInRoom': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether user is currently in a room',
    ),
    
    // Game Context
    'currentGameId': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'ID of currently active game',
    ),
    'games': RecallStateFieldSpec(
      type: Map,
      defaultValue: {},
      description: 'Map of games by ID with their complete state data',
    ),
    
    // Room Lists
    'myCreatedRooms': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of rooms created by the current user',
    ),
    'currentRoom': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Current room information',
    ),
    
    // Game Tracking (Map<String, Map<String, dynamic>>)
    'activeGames': RecallStateFieldSpec(
      type: Map,
      defaultValue: {},
      description: 'Map of active games by ID with their status and metadata',
    ),
    'availableGames': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of available games that can be joined',
    ),
    
    // Joined Games Tracking (Raw Data)
    'joinedGames': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of games the user is currently in',
    ),
    'joinedGamesSlice': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'games': [],
        'totalGames': 0,
        'timestamp': '',
        'isLoadingGames': false,
      },
      description: 'Joined games widget state slice',
    ),
    'totalJoinedGames': RecallStateFieldSpec(
      type: int,
      defaultValue: 0,
      description: 'Total number of games the user is currently in',
    ),
    'joinedGamesTimestamp': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Timestamp of last joined games update',
    ),
    
    // Widget Slices
    'actionBar': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'showStartButton': false,
        'canPlayCard': false,
        'canCallRecall': false,
        'isGameStarted': false,
      },
      description: 'Action bar widget state slice',
    ),
    'statusBar': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'currentPhase': 'waiting',
        'turnInfo': '',
        'playerCount': 0,
        'gameStatus': 'inactive',
        'turnNumber': 0,
        'roundNumber': 1,
      },
      description: 'Status bar widget state slice',
    ),
    'myHand': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'cards': [],
        'selectedIndex': -1,
        'selectedCard': null,
      },
      description: 'My hand widget state slice',
    ),
    'centerBoard': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'drawPileCount': 0,
        'topDiscard': null,
        'topDraw': null,
        'canDrawFromDeck': false,
        'canTakeFromDiscard': false,
      },
      description: 'Center board widget state slice',
    ),
    'opponentsPanel': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'opponents': [],
        'currentTurnIndex': -1,
      },
      description: 'Opponents panel widget state slice',
    ),
    'gameInfo': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'currentGameId': '',
        'currentSize': 0,
        'maxSize': 4,
        'gamePhase': 'waiting',
        'gameStatus': 'inactive',
        'isRoomOwner': false,
        'isInGame': false,
      },
      description: 'Game info widget state slice',
    ),
    'gameState': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Full game state object',
    ),
    'drawPileCount': RecallStateFieldSpec(
      type: int,
      defaultValue: 0,
      description: 'Number of cards in draw pile',
    ),
    'drawPile': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'Cards in draw pile',
    ),
    'discardPile': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'Cards in discard pile',
    ),
    'opponentPlayers': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of opponent players',
    ),
    'currentPlayerIndex': RecallStateFieldSpec(
      type: int,
      defaultValue: -1,
      description: 'Index of current player',
    ),
    'currentGameData': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Current game data object',
    ),
    'myScore': RecallStateFieldSpec(
      type: int,
      defaultValue: 0,
      description: 'Current player\'s total score',
    ),
    'myDrawnCard': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Most recently drawn card for current player',
    ),
    'myCardsToPeek': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'Cards the current player has peeked at (with full data)',
    ),
    'cards_to_peek': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of cards available for peeking (Queen peek, initial peek, etc.)',
    ),
    
    // Message State
    'messages': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'session': [],
        'rooms': {},
      },
      description: 'Message boards for session and rooms',
    ),
    'actionError': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Current action error to display to user',
    ),
    
    // UI State
    'selectedCard': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Currently selected card in hand',
    ),
    'selectedCardIndex': RecallStateFieldSpec(
      type: int,
      required: false,
      description: 'Index of currently selected card in hand',
    ),
    
    // Connection State
    'isConnected': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether WebSocket is connected',
    ),
    'isLoading': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether a loading operation is in progress',
    ),
    'isRandomJoinInProgress': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Flag indicating if a random game join is in progress (for navigation)',
    ),
    'lastError': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Last error message, if any',
    ),
    'lastUpdated': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Timestamp of last state update',
    ),
    
    // Game State Fields
    'isGameActive': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether a game is currently active',
    ),
    'playerCount': RecallStateFieldSpec(
      type: int,
      defaultValue: 0,
      description: 'Number of players in current game',
    ),
    'roundNumber': RecallStateFieldSpec(
      type: int,
      defaultValue: 1,
      description: 'Current round number in the game',
    ),
    'currentPlayer': RecallStateFieldSpec(
      type: Map,
      required: false,
      nullable: true,
      description: 'Current player object with id, name, etc.',
    ),
    'currentPlayerStatus': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Status of current player',
    ),
    'roundStatus': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Status of current round',
    ),
    'turn_events': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of turn events for animations (play, reposition, draw, collect, etc.)',
    ),
    
    // Game Phase Field
    'gamePhase': RecallStateFieldSpec(
      type: String,
      defaultValue: 'waiting',
      description: 'Current game phase (waiting, playing, finished, etc.)',
      allowedValues: [
        // Direct backend phase values (from GamePhase enum)
        'waiting_for_players',
        'dealing_cards',
        'initial_peek',
        'player_turn',
        'same_rank_window',
        'special_play_window',
        'queen_peek_window',
        'turn_pending_events',
        'ending_round',
        'ending_turn',
        'recall_called',
        'game_ended',
        // Legacy mapped values (for backward compatibility)
        'waiting',
        'setup', 
        'playing',
        'out_of_turn',
        'recall',
        'finished'
      ],
    ),
    
    // Practice Mode Fields
    'practiceUser': RecallStateFieldSpec(
      type: Map,
      required: false,
      nullable: true,
      description: 'Practice mode user data (userId, displayName, isPracticeUser)',
    ),
    'practiceSettings': RecallStateFieldSpec(
      type: Map,
      required: false,
      nullable: true,
      description: 'Practice mode settings (difficulty, showInstructions)',
    ),
    
    // Game Status Field
    'gameStatus': RecallStateFieldSpec(
      type: String,
      defaultValue: 'inactive',
      description: 'Current game status (inactive, active, finished, etc.)',
    ),
  };

  /// Set the handler for applying validated updates (platform-specific)
  void setUpdateHandler(StateUpdateHandler handler) {
    _logger.info('StateQueueValidator: setUpdateHandler called', isOn: LOGGING_SWITCH);
    _updateHandler = handler;
  }


  /// Enqueue a state update for validation and processing
  ///
  /// Updates are added to the queue and processed sequentially.
  /// If the queue is empty, processing starts immediately.
  void enqueueUpdate(Map<String, dynamic> update) {
    _updateQueue.add(update);
    _logger.debug('StateQueueValidator: Enqueued update with keys: ${update.keys.join(', ')}', isOn: LOGGING_SWITCH);
    
    // Start processing if not already processing
    if (!_isProcessing) {
      processQueue();
    }
  }

  /// Process all queued updates sequentially
  ///
  /// Each update is validated before being passed to the update handler.
  /// Invalid updates are logged and skipped, processing continues with remaining updates.
  Future<void> processQueue() async {
    if (_isProcessing) {
      return; // Already processing
    }

    _isProcessing = true;

    try {
      while (_updateQueue.isNotEmpty) {
        final update = _updateQueue.removeAt(0);

        try {
          // Validate the update
          final validatedUpdate = validateUpdate(update);

          // Apply the validated update via handler
          if (_updateHandler != null) {
            _logger.debug('StateQueueValidator: About to call handler with keys: ${validatedUpdate.keys.join(', ')}', isOn: LOGGING_SWITCH);
            _logger.info('StateQueueValidator: Handler is NOT NULL, calling it now', isOn: LOGGING_SWITCH);
            try {
              _logger.info('StateQueueValidator: Calling _updateHandler!() now', isOn: LOGGING_SWITCH);
              _updateHandler!(validatedUpdate);
              _logger.info('StateQueueValidator: _updateHandler!() call returned (no exception)', isOn: LOGGING_SWITCH);
              _logger.debug('StateQueueValidator: Handler completed successfully, applied validated update with keys: ${validatedUpdate.keys.join(', ')}', isOn: LOGGING_SWITCH);
            } catch (e, stackTrace) {
              _logger.error('StateQueueValidator: Handler threw exception: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
              rethrow;
            }
          } else {
            _logger.error('StateQueueValidator: No update handler set, skipping update', isOn: LOGGING_SWITCH);
          }
        } catch (e) {
          // Log error but continue processing queue
          _logger.error('StateQueueValidator: Validation failed for update: $e', isOn: LOGGING_SWITCH);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Clear all pending updates from the queue
  void clearQueue() {
    _updateQueue.clear();
    _logger.debug('StateQueueValidator: Cleared update queue', isOn: LOGGING_SWITCH);
  }

  /// Validate a state update against the schema
  ///
  /// Returns a map of validated updates.
  /// Throws RecallStateException if validation fails.
  Map<String, dynamic> validateUpdate(Map<String, dynamic> update) {
    final validatedUpdates = <String, dynamic>{};

    for (final entry in update.entries) {
      final key = entry.key;
      final value = entry.value;

      // Check if field exists in schema
      final fieldSpec = _stateSchema[key];
      if (fieldSpec == null) {
        final error = 'Unknown state field: "$key". Allowed fields: ${_stateSchema.keys.join(', ')}';
        _logger.error('StateQueueValidator: Schema validation failed - $error', isOn: LOGGING_SWITCH);
        throw RecallStateException(error, fieldName: key);
      }

      // Validate field value
      try {
        final validatedValue = _validateStateFieldValue(key, value, fieldSpec);
        validatedUpdates[key] = validatedValue;
      } catch (e) {
        _logger.error('StateQueueValidator: Field validation failed for "$key": $e', isOn: LOGGING_SWITCH);
        rethrow;
      }
    }

    return validatedUpdates;
  }

  /// Check if an update is valid without throwing exceptions
  ///
  /// Returns true if the update passes validation, false otherwise.
  bool isUpdateValid(Map<String, dynamic> update) {
    try {
      validateUpdate(update);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Validate individual state field value
  ///
  /// Handles null values, type validation, allowed values, and range validation.
  dynamic _validateStateFieldValue(String key, dynamic value, RecallStateFieldSpec spec) {
    // Handle null values
    if (value == null) {
      if (spec.required) {
        final error = 'Field "$key" is required and cannot be null';
        _logger.error('StateQueueValidator: $error', isOn: LOGGING_SWITCH);
        throw RecallStateException(error, fieldName: key);
      }
      // If field is nullable, allow null values
      if (spec.nullable == true) {
        return null;
      }
      return spec.defaultValue;
    }

    // Type validation
    if (!ValidationUtils.isValidType(value, spec.type)) {
      final error = 'Field "$key" must be of type ${spec.type}, got ${value.runtimeType}';
      _logger.error('StateQueueValidator: $error', isOn: LOGGING_SWITCH);
      throw RecallStateException(error, fieldName: key);
    }

    // Allowed values validation
    if (spec.allowedValues != null && !ValidationUtils.isAllowedValue(value, spec.allowedValues!)) {
      final error = 'Field "$key" value "$value" is not allowed. Allowed values: ${spec.allowedValues!.join(', ')}';
      _logger.error('StateQueueValidator: $error', isOn: LOGGING_SWITCH);
      throw RecallStateException(error, fieldName: key);
    }

    // Range validation for numbers
    if (value is int) {
      if (!ValidationUtils.isValidRange(value, min: spec.min, max: spec.max)) {
        final rangeDesc = [
          if (spec.min != null) 'min: ${spec.min}',
          if (spec.max != null) 'max: ${spec.max}',
        ].join(', ');
        final error = 'Field "$key" value $value is out of range ($rangeDesc)';
        _logger.error('StateQueueValidator: $error', isOn: LOGGING_SWITCH);
        throw RecallStateException(error, fieldName: key);
      }
    }

    return value;
  }

  /// Get the current queue size
  int get queueSize => _updateQueue.length;

  /// Check if the queue is currently processing
  bool get isProcessing => _isProcessing;
}

