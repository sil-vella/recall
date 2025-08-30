import '../../../tools/logging/logger.dart';
import '../utils/validated_event_emitter.dart';

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

  // ========= CARD ACTIONS =========

  /// Draw a card from the specified pile
  static PlayerAction playerDraw({
    required String pileType, // 'draw_pile' or 'discard_pile'
    required String gameId,
    String? playerId, // Optional, will be resolved from session if not provided
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.drawCard,
      eventName: 'draw_card',
      payload: {
        'game_id': gameId,
        'player_id': playerId, // Will be resolved from session if null
        'source': pileType, // Backend expects 'source' not 'pile_type'
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
