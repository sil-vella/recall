import 'validated_event_emitter.dart';
import 'validated_state_manager.dart';

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
  jackSwap,
  
  // Query actions
  getPublicRooms,
}

/// Centralized player action class for all game interactions
class PlayerAction {
  static final RecallGameEventEmitter _eventEmitter = RecallGameEventEmitter.instance;
  static final RecallGameStateUpdater _stateUpdater = RecallGameStateUpdater.instance;
  
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
      // Special handling for Jack swap - don't set status to waiting yet
      if (actionType == PlayerActionType.jackSwap) {
        return; // Jack swap is handled by selectCardForJackSwap method
      }
      
      // Set status to waiting after action execution to prevent multiple selections
      _setPlayerStatusToWaiting();
      
      // Check if this is a practice game
      final isPracticeGame = _checkIfPracticeGame();
      if (isPracticeGame) {
        // For practice games, we just log the action without sending to backend
        // TODO: Implement practice game logic (local simulation, etc.)
        return;
      }
      
      await _eventEmitter.emit(
        eventType: eventName,
        data: payload,
      );

    } catch (e) {
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

  /// Centralized method to set player status to waiting after any action
  /// This prevents players from making multiple selections while waiting for backend response
  static void _setPlayerStatusToWaiting() {
    try {
      // Use the dedicated state updater to properly update the player status
      _stateUpdater.updateState({
        'playerStatus': 'waiting',
      });
      
    } catch (e) {
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
      // If this is the first card selection
      if (_firstSelectedCardId == null) {
        _firstSelectedCardId = cardId;
        _firstSelectedPlayerId = playerId;
        print('Jack swap: First card selected - Card: $cardId, Player: $playerId');
        return; // Wait for second card
      }
      
      // If this is the second card selection
      if (_secondSelectedCardId == null) {
        _secondSelectedCardId = cardId;
        _secondSelectedPlayerId = playerId;
        print('Jack swap: Second card selected - Card: $cardId, Player: $playerId');
        
        // Both cards selected, execute the swap
        await _executeJackSwap(gameId);
      }
      
    } catch (e) {
      print('Error in selectCardForJackSwap: $e');
      rethrow;
    }
  }

  /// Execute the Jack swap with both selected cards
  static Future<void> _executeJackSwap(String gameId) async {
    try {
      if (_firstSelectedCardId == null || _secondSelectedCardId == null ||
          _firstSelectedPlayerId == null || _secondSelectedPlayerId == null) {
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

      // Send the swap request to backend
      await _eventEmitter.emit(
        eventType: 'jack_swap',
        data: swapPayload,
      );

      // Clear selections after successful execution
      _clearJackSwapSelections();
      
      // Set player status to waiting
      _setPlayerStatusToWaiting();

    } catch (e) {
      print('Error executing Jack swap: $e');
      rethrow;
    }
  }

  /// Clear Jack swap selections
  static void _clearJackSwapSelections() {
    _firstSelectedCardId = null;
    _firstSelectedPlayerId = null;
    _secondSelectedCardId = null;
    _secondSelectedPlayerId = null;
  }

  /// Reset Jack swap selections (call this when Jack swap is cancelled)
  static void resetJackSwapSelections() {
    _clearJackSwapSelections();
  }

  /// Check if Jack swap is in progress
  static bool isJackSwapInProgress() {
    return _firstSelectedCardId != null;
  }

  /// Get the number of cards selected for Jack swap
  static int getJackSwapSelectionCount() {
    int count = 0;
    if (_firstSelectedCardId != null) count++;
    if (_secondSelectedCardId != null) count++;
    return count;
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
