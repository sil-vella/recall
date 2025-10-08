import 'package:recall/tools/logging/logger.dart';

import 'validated_event_emitter.dart';
import 'validated_state_manager.dart';
import '../game_logic/practice_match/practice_game.dart';

/// Player action types for the Recall game
enum PlayerActionType {
  // Card actions
  drawCard,
  playCard,
  replaceCard,
  
  // Special actions
  callRecall,
  playSameRank,
  useSpecialPower,
  initialPeek,
  completedInitialPeek,
  jackSwap,
  queenPeek,
  
  // Query actions
  getPublicRooms,
}

/// Centralized player action class for all game interactions
class PlayerAction {
  static final RecallGameEventEmitter _eventEmitter = RecallGameEventEmitter.instance;
  static final RecallGameStateUpdater _stateUpdater = RecallGameStateUpdater.instance;
  
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false;
  // Jack swap selection tracking
  static String? _firstSelectedCardId;
  static String? _firstSelectedPlayerId;
  static String? _secondSelectedCardId;
  static String? _secondSelectedPlayerId;

  final PlayerActionType actionType;
  final String eventName;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  PlayerAction._({
    required this.actionType,
    required this.eventName,
    required this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Execute the player action with validation and state management
  Future<void> execute() async {
    try {
      _logger.info('Executing action: ${actionType.name} with payload: $payload', isOn: LOGGING_SWITCH);
      
      // Special handling for Jack swap - don't set status to waiting yet
      if (actionType == PlayerActionType.jackSwap) {
        _logger.info('Jack swap action executed - waiting for card selections', isOn: LOGGING_SWITCH);
        return; // Jack swap is handled by selectCardForJackSwap method
      }
      
      // Special handling for Queen peek - execute immediately with single card selection
      if (actionType == PlayerActionType.queenPeek) {
        _logger.info('Queen peek action executed - peeking at card: ${payload['card_id']}', isOn: LOGGING_SWITCH);
        // Queen peek executes immediately, no special handling needed
      }
      
      // Set status to waiting after action execution to prevent multiple selections
      _setPlayerStatusToWaiting();
      _logger.info('Player status set to waiting after action execution', isOn: LOGGING_SWITCH);
      
      // Check if this is a practice game
      final isPracticeGame = _checkIfPracticeGame();
      _logger.info('🎯 Practice game check: isPracticeGame=$isPracticeGame, currentGameId=${payload['game_id']}', isOn: LOGGING_SWITCH);
      
      if (isPracticeGame) {
        _logger.info('Practice game detected - triggering practice event handler', isOn: LOGGING_SWITCH);
        
        // Trigger practice event through state manager so PracticeRoom can handle it
        _triggerPracticeEvent();
        
        return;
      }
      
      _logger.info('Sending event to backend: $eventName with data: $payload', isOn: LOGGING_SWITCH);
      await _eventEmitter.emit(
        eventType: eventName,
        data: payload,
      );
      _logger.info('Event successfully sent to backend', isOn: LOGGING_SWITCH);

    } catch (e) {
      _logger.error('Error executing action ${actionType.name}: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }

  /// Check if the current game is a practice game
  bool _checkIfPracticeGame() {
    try {
      // Use the centralized game state accessor
      final gameAccessor = RecallGameStateAccessor.instance;
      final isPractice = gameAccessor.isCurrentGamePractice();
      
      return isPractice;
      
    } catch (e) {
      return false;
    }
  }

  /// Trigger practice event by calling the PracticeGameCoordinator directly
  void _triggerPracticeEvent() {
    try {
      // Get the practice game coordinator (singleton)
      final practiceCoordinator = PracticeGameCoordinator();
      
      // Extract session ID (game_id) from payload
      final sessionId = payload['game_id'] as String? ?? '';
      
      if (sessionId.isEmpty) {
        _logger.warning('Cannot trigger practice event - no game_id in payload', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Call the practice coordinator to handle the event
      _logger.info('Calling practice coordinator for event: $eventName (session: $sessionId)', isOn: LOGGING_SWITCH);
      practiceCoordinator.handlePracticeEvent(sessionId, eventName, payload);
      
      _logger.info('Practice event handled by coordinator: $eventName', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('Error triggering practice event: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Centralized method to set player status to waiting after any action
  /// This prevents players from making multiple selections while waiting for backend response
  static void _setPlayerStatusToWaiting() {
    try {
      final logger = Logger();
      logger.info('Setting player status to waiting', isOn: LOGGING_SWITCH);
      
      // Use the dedicated state updater to properly update the player status
      _stateUpdater.updateState({
        'playerStatus': 'waiting',
      });
      
      logger.info('Player status successfully set to waiting', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      final logger = Logger();
      logger.error('Error setting player status to waiting: $e', isOn: LOGGING_SWITCH);
      // Don't rethrow - this is not critical for the main action execution
    }
  }

  // ========= VALIDATION LOGIC =========

  // ========= CARD ACTIONS =========

  /// Draw a card from the specified pile
  static PlayerAction playerDraw({
    required String pileType, // 'draw_pile' or 'discard_pile'
    required String gameId,
    // playerId is now auto-added by RecallGameEventEmitter
  }) {
    // Convert frontend pile type to backend source value
    String source;
    switch (pileType) {
      case 'draw_pile':
        source = 'deck';
        break;
      case 'discard_pile':
        source = 'discard';
        break;
      default:
        source = pileType; // Fallback for any other values
    }
    
    return PlayerAction._(
      actionType: PlayerActionType.drawCard,
      eventName: 'draw_card',
      payload: {
        'game_id': gameId,
        'source': source, // Backend expects 'deck' or 'discard'
        // player_id will be automatically included by the event emitter
      },
    );
  }

  /// Play a card from the player's hand
  static PlayerAction playerPlayCard({
    required String gameId,
    required String cardId,

  }) {
    return PlayerAction._(
      actionType: PlayerActionType.playCard,
      eventName: 'play_card',
      payload: {
        'game_id': gameId,
        'card_id': cardId
        // player_id will be automatically included by the event emitter
      },
    );
  }

    /// Play a card from the player's hand
  static PlayerAction sameRankPlay({
    required String gameId,
    required String cardId,

  }) {
    return PlayerAction._(
      actionType: PlayerActionType.playSameRank,
      eventName: 'same_rank_play',
      payload: {
        'game_id': gameId,
        'card_id': cardId
        // player_id will be automatically included by the event emitter
      },
    );
  }

  /// Jack swap action - waits for 2 cards to be selected
  static PlayerAction jackSwap({
    required String gameId,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.jackSwap,
      eventName: 'jack_swap',
      payload: {
        'game_id': gameId,
        // card selections will be added when both cards are selected
      },
    );
  }

  // ========= JACK SWAP LOGIC =========

  /// Select a card for Jack swap (can be from any player)
  static Future<void> selectCardForJackSwap({
    required String cardId,
    required String playerId,
    required String gameId,
  }) async {
    try {
      final logger = Logger();
      logger.info('Jack swap card selection attempt - Card: $cardId, Player: $playerId, Game: $gameId', isOn: LOGGING_SWITCH);
      
      // If this is the first card selection
      if (_firstSelectedCardId == null) {
        _firstSelectedCardId = cardId;
        _firstSelectedPlayerId = playerId;
        logger.info('Jack swap: First card selected - Card: $cardId, Player: $playerId', isOn: LOGGING_SWITCH);
        print('Jack swap: First card selected - Card: $cardId, Player: $playerId');
        return; // Wait for second card
      }
      
      // If this is the second card selection
      if (_secondSelectedCardId == null) {
        _secondSelectedCardId = cardId;
        _secondSelectedPlayerId = playerId;
        logger.info('Jack swap: Second card selected - Card: $cardId, Player: $playerId', isOn: LOGGING_SWITCH);
        print('Jack swap: Second card selected - Card: $cardId, Player: $playerId');
        
        // Both cards selected, execute the swap
        logger.info('Both cards selected, executing Jack swap', isOn: LOGGING_SWITCH);
        await _executeJackSwap(gameId);
      } else {
        logger.warning('Jack swap: Attempted to select third card - already have two cards selected', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      final logger = Logger();
      logger.error('Error in selectCardForJackSwap: $e', isOn: LOGGING_SWITCH);
      print('Error in selectCardForJackSwap: $e');
      rethrow;
    }
  }

  /// Execute the Jack swap with both selected cards
  static Future<void> _executeJackSwap(String gameId) async {
    try {
      final logger = Logger();
      logger.info('Executing Jack swap - Game: $gameId', isOn: LOGGING_SWITCH);
      
      if (_firstSelectedCardId == null || _secondSelectedCardId == null ||
          _firstSelectedPlayerId == null || _secondSelectedPlayerId == null) {
        logger.error('Jack swap validation failed - missing card or player IDs', isOn: LOGGING_SWITCH);
        throw Exception('Both cards must be selected for Jack swap');
      }

      // Create the swap payload
      final swapPayload = {
        'game_id': gameId,
        'first_card_id': _firstSelectedCardId,
        'first_player_id': _firstSelectedPlayerId,
        'second_card_id': _secondSelectedCardId,
        'second_player_id': _secondSelectedPlayerId,
      };

      logger.info('Jack swap payload created: $swapPayload', isOn: LOGGING_SWITCH);

      // Send the swap request to backend
      logger.info('Sending jack_swap event to backend', isOn: LOGGING_SWITCH);
      await _eventEmitter.emit(
        eventType: 'jack_swap',
        data: swapPayload,
      );
      logger.info('Jack swap event successfully sent to backend', isOn: LOGGING_SWITCH);

      // Clear selections after successful execution
      _clearJackSwapSelections();
      logger.info('Jack swap selections cleared', isOn: LOGGING_SWITCH);
      
      // Set player status to waiting
      _setPlayerStatusToWaiting();
      logger.info('Player status set to waiting after Jack swap execution', isOn: LOGGING_SWITCH);

    } catch (e) {
      final logger = Logger();
      logger.error('Error executing Jack swap: $e', isOn: LOGGING_SWITCH);
      print('Error executing Jack swap: $e');
      rethrow;
    }
  }

  /// Clear Jack swap selections
  static void _clearJackSwapSelections() {
    final logger = Logger();
    logger.info('Clearing Jack swap selections', isOn: LOGGING_SWITCH);
    
    _firstSelectedCardId = null;
    _firstSelectedPlayerId = null;
    _secondSelectedCardId = null;
    _secondSelectedPlayerId = null;
    
    logger.info('Jack swap selections cleared successfully', isOn: LOGGING_SWITCH);
  }

  /// Reset Jack swap selections (call this when Jack swap is cancelled)
  static void resetJackSwapSelections() {
    final logger = Logger();
    logger.info('Resetting Jack swap selections', isOn: LOGGING_SWITCH);
    _clearJackSwapSelections();
  }

  /// Check if Jack swap is in progress
  static bool isJackSwapInProgress() {
    final inProgress = _firstSelectedCardId != null;
    final logger = Logger();
    logger.info('Jack swap in progress check: $inProgress', isOn: LOGGING_SWITCH);
    return inProgress;
  }

  /// Get the number of cards selected for Jack swap
  static int getJackSwapSelectionCount() {
    int count = 0;
    if (_firstSelectedCardId != null) count++;
    if (_secondSelectedCardId != null) count++;
    
    final logger = Logger();
    logger.info('Jack swap selection count: $count', isOn: LOGGING_SWITCH);
    return count;
  }

  // ========= INITIAL PEEK LOGIC =========

  /// Completed initial peek action - signals that player has finished peeking at 2 cards
  static PlayerAction completedInitialPeek({
    required String gameId,
    required List<String> cardIds,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.completedInitialPeek,
      eventName: 'completed_initial_peek',
      payload: {
        'game_id': gameId,
        'card_ids': cardIds,
      },
    );
  }

  // ========= QUEEN PEEK LOGIC =========

  /// Queen peek action - peek at any one card from any player
  static PlayerAction queenPeek({
    required String gameId,
    required String cardId,
    required String ownerId,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.queenPeek,
      eventName: 'queen_peek',
      payload: {
        'game_id': gameId,
        'card_id': cardId,
        'ownerId': ownerId,
      },
    );
  }

  // ========= QUERY ACTIONS =========

  /// Get list of public rooms
  static PlayerAction getPublicRooms() {
    return PlayerAction._(
      actionType: PlayerActionType.getPublicRooms,
      eventName: 'recall_get_public_rooms',
      payload: {},
    );
  }

  // ========= UTILITY METHODS =========

  /// Convert action to JSON
  Map<String, dynamic> toJson() {
    return {
      'actionType': actionType.name,
      'eventName': eventName,
      'payload': payload,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create action from JSON
  factory PlayerAction.fromJson(Map<String, dynamic> json) {
    final actionType = PlayerActionType.values.firstWhere(
      (type) => type.name == json['actionType'],
    );

    return PlayerAction._(
      actionType: actionType,
      eventName: json['eventName'],
      payload: Map<String, dynamic>.from(json['payload']),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  @override
  String toString() {
    return 'PlayerAction(${actionType.name}: $eventName, payload: $payload)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlayerAction &&
        other.actionType == actionType &&
        other.eventName == eventName &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => actionType.hashCode ^ eventName.hashCode ^ timestamp.hashCode;
}
