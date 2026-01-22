import 'package:dutch/tools/logging/logger.dart';

import 'validated_event_emitter.dart';
import '../../dutch_game/managers/dutch_game_state_updater.dart';
import '../../../core/managers/module_manager.dart';
import '../../../modules/analytics_module/analytics_module.dart';

/// Player action types for the Dutch game
enum PlayerActionType {
  // Card actions
  drawCard,
  playCard,
  replaceCard,
  
  // Special actions
  callDutch, // Deprecated, use callFinalRound
  callFinalRound,
  playSameRank,
  useSpecialPower,
  initialPeek,
  completedInitialPeek,
  jackSwap,
  queenPeek,
  collectFromDiscard,
  
  // Query actions
  getPublicRooms,
}

/// Centralized player action class for all game interactions
class PlayerAction {
  static final DutchGameEventEmitter _eventEmitter = DutchGameEventEmitter.instance;
  static final DutchGameStateUpdater _stateUpdater = DutchGameStateUpdater.instance;
  
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = true; // Enabled for practice match debugging and leave_room event verification
  
  // Analytics module cache
  static AnalyticsModule? _analyticsModule;
  
  /// Get analytics module instance
  static AnalyticsModule? _getAnalyticsModule() {
    if (_analyticsModule == null) {
      try {
        final moduleManager = ModuleManager();
        _analyticsModule = moduleManager.getModuleByType<AnalyticsModule>();
      } catch (e) {
        // Silently fail
      }
    }
    return _analyticsModule;
  }
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
      _logger.info('PlayerAction.execute: Executing action: ${actionType.name}, eventName: $eventName, payload: $payload', isOn: LOGGING_SWITCH);
      
      // Special logging for leave_room events
      if (eventName == 'leave_room') {
        _logger.info('PlayerAction.execute: LEAVE_ROOM event - gameId: ${payload['game_id']}', isOn: LOGGING_SWITCH);
      }
      
      // Special handling for Jack swap - build complete payload from selections
      if (actionType == PlayerActionType.jackSwap) {
        // Validate both cards are selected
        if (_firstSelectedCardId == null || _secondSelectedCardId == null ||
            _firstSelectedPlayerId == null || _secondSelectedPlayerId == null) {
          _logger.error('Jack swap validation failed - missing card or player IDs', isOn: LOGGING_SWITCH);
          throw Exception('Both cards must be selected for Jack swap');
        }
        
        // Build complete payload with both card selections
        payload['first_card_id'] = _firstSelectedCardId;
        payload['first_player_id'] = _firstSelectedPlayerId;
        payload['second_card_id'] = _secondSelectedCardId;
        payload['second_player_id'] = _secondSelectedPlayerId;
        
        _logger.info('Jack swap payload built with both card selections', isOn: LOGGING_SWITCH);
      }
      
      // Special handling for Queen peek - execute immediately with single card selection
      if (actionType == PlayerActionType.queenPeek) {
        _logger.info('Queen peek action executed - peeking at card: ${payload['card_id']}', isOn: LOGGING_SWITCH);
        // Queen peek executes immediately, no special handling needed
      }
      
      // Note: Removed _setPlayerStatusToWaiting() call
      // Rapid-click prevention is now handled by local widget state (_isProcessingAction flag)
      // This prevents the frontend from overriding backend status updates
      _logger.info('Skipping optimistic status update - backend will control player status', isOn: LOGGING_SWITCH);
      
      // Use event emitter for both practice and multiplayer games
      // The event emitter will route to practice bridge if transport mode is practice
      _logger.info('Sending event to backend: $eventName with data: $payload', isOn: LOGGING_SWITCH);
      await _eventEmitter.emit(
        eventType: eventName,
        data: payload,
      );
      _logger.info('Event successfully sent to backend', isOn: LOGGING_SWITCH);
      
      // Clear Jack swap selections after successful WebSocket emission
      if (actionType == PlayerActionType.jackSwap) {
        _clearJackSwapSelections();
      }

    } catch (e) {
      _logger.error('Error executing action ${actionType.name}: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }
  
  /// Track analytics event for player actions
  static Future<void> _trackAnalyticsEvent(
    PlayerActionType actionType,
    String eventName,
    Map<String, dynamic> payload,
  ) async {
    try {
      final analyticsModule = _getAnalyticsModule();
      if (analyticsModule == null) return;
      
      // Map action types to analytics events
      switch (actionType) {
        case PlayerActionType.playCard:
        case PlayerActionType.replaceCard:
          await analyticsModule.trackEvent(
            eventType: 'card_played',
            eventData: {
              'action_type': actionType.name,
              'event_name': eventName,
            },
          );
          break;
        case PlayerActionType.queenPeek:
          await analyticsModule.trackEvent(
            eventType: 'special_card_used',
            eventData: {
              'card_type': 'queen_peek',
              'event_name': eventName,
            },
          );
          break;
        case PlayerActionType.jackSwap:
          await analyticsModule.trackEvent(
            eventType: 'special_card_used',
            eventData: {
              'card_type': 'jack_swap',
              'event_name': eventName,
            },
          );
          break;
        case PlayerActionType.callFinalRound:
          await analyticsModule.trackEvent(
            eventType: 'dutch_called',
            eventData: {
              'event_name': eventName,
            },
          );
          break;
        default:
          // Track other actions as generic game actions
          break;
      }
    } catch (e) {
      // Silently fail - don't block game actions if analytics fails
    }
  }

  /// Check if the current game is a dutch game
  bool _checkIfPracticeGame() {
    try {
      // Use the centralized game state accessor
      final gameAccessor = DutchGameStateAccessor.instance;
      final isPractice = gameAccessor.isCurrentGamePractice();
      
      return isPractice;
      
    } catch (e) {
      return false;
    }
  }

  /// Trigger dutch event by calling the PracticeGameCoordinator directly
  void _triggerPracticeEvent() {
    try {
      // Get the dutch game coordinator (singleton)
      // todo ... link to practice mode logic (dart bkend replica)
      
    } catch (e) {
      _logger.error('Error triggering dutch event: $e', isOn: LOGGING_SWITCH);
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
    // playerId is now auto-added by DutchGameEventEmitter
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
        return; // Wait for second card
      }
      
      // If this is the second card selection
      if (_secondSelectedCardId == null) {
        _secondSelectedCardId = cardId;
        _secondSelectedPlayerId = playerId;
        logger.info('Jack swap: Second card selected - Card: $cardId, Player: $playerId', isOn: LOGGING_SWITCH);
        
        // Both cards selected, execute the swap through normal execute() flow
        logger.info('Both cards selected, executing Jack swap', isOn: LOGGING_SWITCH);
        final jackSwapAction = PlayerAction.jackSwap(gameId: gameId);
        await jackSwapAction.execute();
      } else {
        logger.warning('Jack swap: Attempted to select third card - already have two cards selected', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      final logger = Logger();
      logger.error('Error in selectCardForJackSwap: $e', isOn: LOGGING_SWITCH);
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

  /// Collect card from discard pile if it matches collection rank
  static PlayerAction collectFromDiscard({
    required String gameId,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.collectFromDiscard,
      eventName: 'collect_from_discard',
      payload: {
        'game_id': gameId,
        // player_id will be automatically included by the event emitter
      },
    );
  }

  /// Call final round - signals the final round of the game
  /// After calling, all players get one last turn, then game ends and winners are calculated
  static PlayerAction callFinalRound({
    required String gameId,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.callFinalRound,
      eventName: 'call_final_round',
      payload: {
        'game_id': gameId,
        // player_id will be automatically included by the event emitter
      },
    );
  }

  // ========= QUERY ACTIONS =========

  /// Get list of public rooms
  static PlayerAction getPublicRooms() {
    return PlayerAction._(
      actionType: PlayerActionType.getPublicRooms,
      eventName: 'dutch_get_public_rooms',
      payload: {},
    );
  }

  // ========= GAME ACTIONS =========

  /// Start a match
  static PlayerAction startMatch({
    required String gameId,
    bool? showInstructions,
    bool? isClearAndCollect,
  }) {
    final payload = <String, dynamic>{
      'game_id': gameId,
    };
    
    // Include showInstructions if provided (practice mode)
    if (showInstructions != null) {
      payload['showInstructions'] = showInstructions;
    }
    
    // Include isClearAndCollect if provided
    if (isClearAndCollect != null) {
      payload['isClearAndCollect'] = isClearAndCollect;
    }
    
    return PlayerAction._(
      actionType: PlayerActionType.useSpecialPower, // Using a generic type since start_match isn't in the enum
      eventName: 'start_match',
      payload: payload,
    );
  }

  /// Join a game
  static PlayerAction joinGame({
    required String gameId,
    required String playerName,
    String playerType = 'human',
    int maxPlayers = 4,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.useSpecialPower, // Using a generic type
      eventName: 'join_game',
      payload: {
        'game_id': gameId,
        'player_name': playerName,
        'player_type': playerType,
        'max_players': maxPlayers,
      },
    );
  }

  /// Leave a game
  static PlayerAction leaveGame({
    required String gameId,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.useSpecialPower, // Using a generic type
      eventName: 'leave_room', // Changed from 'leave_game' to match backend handler
      payload: {
        'game_id': gameId,
      },
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
