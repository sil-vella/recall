import '../../../tools/logging/logger.dart';
import '../utils/validated_event_emitter.dart';
import '../../../core/managers/state_manager.dart';

/// Player action types for the Recall game
enum PlayerActionType {
  // Game flow actions
  joinGame,
  leaveGame,
  startMatch,
  
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
  static final StateManager _stateManager = StateManager();

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

  // ========= VALIDATION LOGIC =========



  /// Get selected card from state manager
  static Map<String, dynamic>? _getSelectedCard() {
    final gamePlayState = _stateManager.getModuleState<Map<String, dynamic>>('game_play_screen') ?? {};
    return gamePlayState['selectedCard'] as Map<String, dynamic>?;
  }

  /// Get pending drawn card from state manager
  static Map<String, dynamic>? _getPendingDrawnCard() {
    final gamePlayState = _stateManager.getModuleState<Map<String, dynamic>>('game_play_screen') ?? {};
    return gamePlayState['pendingDrawnCard'] as Map<String, dynamic>?;
  }

  // ========= GAME FLOW ACTIONS =========

  /// Join a game
  static PlayerAction joinGame({
    String? gameId,
    required String playerName,
    String playerType = 'human',
    int maxPlayers = 4,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.joinGame,
      eventName: 'join_game',
      payload: {
        if (gameId != null) 'game_id': gameId,
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
      actionType: PlayerActionType.leaveGame,
      eventName: 'recall_leave_game',
      payload: {
        'game_id': gameId,
      },
    );
  }

  /// Start a match
  static PlayerAction startMatch({
    required String gameId,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.startMatch,
      eventName: 'start_match',
      payload: {
        'game_id': gameId,
      },
    );
  }



  /// Use a special power (Queen peek, Jack switch, etc.)
  static PlayerAction useSpecialPower({
    required String gameId,
    required String cardId,
    required String powerType,
    String? targetPlayerId,
    int? targetCardIndex,
    int? sourceCardIndex,
    Map<String, dynamic>? additionalData,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.useSpecialPower,
      eventName: 'recall_use_special_power',
      payload: {
        'game_id': gameId,
        'card_id': cardId,
        'power_type': powerType,
        if (targetPlayerId != null) 'target_player_id': targetPlayerId,
        if (targetCardIndex != null) 'target_card_index': targetCardIndex,
        if (sourceCardIndex != null) 'source_card_index': sourceCardIndex,
        if (additionalData != null) ...additionalData,
      },
    );
  }

  /// Peek at initial cards
  static PlayerAction initialPeek({
    required String gameId,
    required List<int> cardIndices,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.initialPeek,
      eventName: 'recall_initial_peek',
      payload: {
        'game_id': gameId,
        'card_indices': cardIndices,
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
