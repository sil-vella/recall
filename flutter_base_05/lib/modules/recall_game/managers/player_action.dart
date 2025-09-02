import '../../../tools/logging/logger.dart';
import '../../../core/managers/state_manager.dart';
import 'validated_event_emitter.dart';
import 'validated_state_updater.dart';

/// Player action types for the Recall game
enum PlayerActionType {
  // Card actions
  drawCard,
  playCard,
  replaceCard,
  
  // Special actions
  callRecall,
  playOutOfTurn,
  useSpecialPower,
  initialPeek,
  
  // Query actions
  getPublicRooms,
}

/// Centralized player action class for all game interactions
class PlayerAction {
  static final Logger _log = Logger();
  static final RecallGameEventEmitter _eventEmitter = RecallGameEventEmitter.instance;
  static final RecallGameStateUpdater _stateUpdater = RecallGameStateUpdater.instance;

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
      _log.info('🎮 Executing ${actionType.name}: $eventName with payload: $payload');
      
      // Check if this is a practice game
      final isPracticeGame = _checkIfPracticeGame();
      if (isPracticeGame) {
        _log.info('🎯 [PRACTICE GAME] Action ${actionType.name} would be executed in practice mode - logging only');
        // For practice games, we just log the action without sending to backend
        // TODO: Implement practice game logic (local simulation, etc.)
        return;
      }
      
      // Set status to waiting after action execution to prevent multiple selections
      _setPlayerStatusToWaiting();
      
      await _eventEmitter.emit(
        eventType: eventName,
        data: payload,
      );
      
      _log.info('✅ Action ${actionType.name} sent successfully');

    } catch (e) {
      _log.error('❌ Failed to execute action ${actionType.name}: $e');
      rethrow;
    }
  }

  /// Check if the current game is a practice game
  bool _checkIfPracticeGame() {
    try {
      final stateManager = StateManager();
      final recallGameState = stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      
      // Get current game ID
      final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
      if (currentGameId.isEmpty) {
        _log.warning('⚠️ No current game ID found, assuming not practice game');
        return false;
      }
      
      // Get games map
      final games = recallGameState['games'] as Map<String, dynamic>? ?? {};
      if (!games.containsKey(currentGameId)) {
        _log.warning('⚠️ Current game not found in games map, assuming not practice game');
        return false;
      }
      
      // Get current game data
      final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
      final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
      
      // Check if game type is 'practice'
      final gameType = gameState['gameType']?.toString() ?? 'normal';
      final isPractice = gameType == 'practice';
      
      _log.info('🔍 Game type check: gameId=$currentGameId, gameType=$gameType, isPractice=$isPractice');
      
      return isPractice;
      
    } catch (e) {
      _log.warning('⚠️ Error checking game type, assuming not practice game: $e');
      return false;
    }
  }

  /// Centralized method to set player status to waiting after any action
  /// This prevents players from making multiple selections while waiting for backend response
  void _setPlayerStatusToWaiting() {
    try {
      _log.info('⏳ Setting player status to waiting after action ${actionType.name}');
      
      // Use the dedicated state updater to properly update the player status
      _stateUpdater.updateState({
        'playerStatus': 'waiting',
      });
      
      _log.info('✅ Player status successfully set to waiting');
      
    } catch (e) {
      _log.warning('⚠️ Failed to set player status to waiting: $e');
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
    int? replaceIndex, // Optional: if replacing a drawn card
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.playCard,
      eventName: 'play_card',
      payload: {
        'game_id': gameId,
        'card_id': cardId,
        if (replaceIndex != null) 'replace_index': replaceIndex,
        // player_id will be automatically included by the event emitter
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
