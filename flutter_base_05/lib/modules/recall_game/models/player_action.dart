import '../../../tools/logging/logger.dart';
import '../utils/validated_event_emitter.dart';
import '../../../core/managers/state_manager.dart';
import 'turn_phase.dart';

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
      
      // Validate action is allowed in current turn phase
      if (!_isActionAllowed(actionType)) {
        final currentPhase = _getCurrentTurnPhase();
        _log.warning('🎮 Action ${actionType.name} not allowed in current phase: ${currentPhase.name}');
        throw Exception('Action ${actionType.name} not allowed in current turn phase: ${currentPhase.name}');
      }
      
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

  /// Get current turn phase from state manager
  static PlayerTurnPhase _getCurrentTurnPhase() {
    final gamePlayState = _stateManager.getModuleState<Map<String, dynamic>>('game_play_screen') ?? {};
    final phaseString = gamePlayState['currentTurnPhase'] as String?;
    
    if (phaseString != null) {
      try {
        return PlayerTurnPhase.values.firstWhere((phase) => phase.name == phaseString);
      } catch (e) {
        _log.warning('⚠️ Unknown turn phase: $phaseString, defaulting to waiting');
      }
    }
    
    return PlayerTurnPhase.waiting;
  }

  /// Check if action is allowed in current turn phase
  static bool _isActionAllowed(PlayerActionType actionType) {
    final currentPhase = _getCurrentTurnPhase();
    
    switch (currentPhase) {
      case PlayerTurnPhase.waiting:
        return actionType == PlayerActionType.joinGame || 
               actionType == PlayerActionType.getPublicRooms ||
               actionType == PlayerActionType.startMatch;
               
      case PlayerTurnPhase.mustDraw:
        return actionType == PlayerActionType.drawCard;
        
      case PlayerTurnPhase.hasDrawnCard:
        return actionType == PlayerActionType.playCard || 
               actionType == PlayerActionType.replaceCard;
               
      case PlayerTurnPhase.canPlay:
        return actionType == PlayerActionType.playCard || 
               actionType == PlayerActionType.callRecall ||
               actionType == PlayerActionType.useSpecialPower;
               
      case PlayerTurnPhase.outOfTurn:
        return actionType == PlayerActionType.playOutOfTurn;
        
      case PlayerTurnPhase.recallOpportunity:
        return actionType == PlayerActionType.callRecall;
    }
  }

  /// Update turn phase in state manager
  static void _updateTurnPhase(PlayerTurnPhase newPhase) {
    final currentState = _stateManager.getModuleState<Map<String, dynamic>>('game_play_screen') ?? {};
    currentState['currentTurnPhase'] = newPhase.name;
    _stateManager.updateModuleState('game_play_screen', currentState);
    _log.info('🎮 Turn phase updated to: ${newPhase.name}');
  }

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

  // ========= CARD ACTIONS =========

  /// Draw a card from deck or discard pile
  static PlayerAction drawCard({
    required String gameId,
    required String source, // 'deck' or 'discard'
  }) {
    // Additional validation for draw action
    final currentPhase = _getCurrentTurnPhase();
    if (currentPhase != PlayerTurnPhase.mustDraw) {
      _log.warning('🎮 Drawing not allowed in current phase: ${currentPhase.name}');
    }
    
    return PlayerAction._(
      actionType: PlayerActionType.drawCard,
      eventName: 'recall_player_action',
      payload: {
        'game_id': gameId,
        'action': 'draw_card',
        'source': source,
      },
    );
  }

  /// Play a card from hand
  static PlayerAction playCard({
    required String gameId,
    String? cardId,
    String? targetPlayerId,
    int? targetCardIndex,
  }) {
    // Get cardId from selected card if not provided
    String? finalCardId = cardId;
    if (finalCardId == null) {
      final selectedCard = _getSelectedCard();
      if (selectedCard == null) {
        _log.warning('🎮 No card selected for play action');
        throw Exception('No card selected for play action');
      }
      finalCardId = selectedCard['cardId'] as String?;
      if (finalCardId == null) {
        throw Exception('Selected card has no cardId');
      }
    }
    
    // Validate current phase allows playing
    final currentPhase = _getCurrentTurnPhase();
    if (currentPhase != PlayerTurnPhase.canPlay && currentPhase != PlayerTurnPhase.hasDrawnCard) {
      _log.warning('🎮 Playing card not allowed in current phase: ${currentPhase.name}');
    }
    
    return PlayerAction._(
      actionType: PlayerActionType.playCard,
      eventName: 'recall_player_action',
      payload: {
        'game_id': gameId,
        'action': 'play_card',
        'card_id': finalCardId,
        if (targetPlayerId != null) 'target_player_id': targetPlayerId,
        if (targetCardIndex != null) 'target_card_index': targetCardIndex,
      },
    );
  }

  /// Replace a card with drawn card
  static PlayerAction replaceCard({
    required String gameId,
    String? cardId,
    String? drawnCardId,
  }) {
    // Get cardId from selected card if not provided
    String? finalCardId = cardId;
    if (finalCardId == null) {
      final selectedCard = _getSelectedCard();
      if (selectedCard == null) {
        _log.warning('🎮 No card selected for replace action');
        throw Exception('No card selected for replace action');
      }
      finalCardId = selectedCard['cardId'] as String?;
      if (finalCardId == null) {
        throw Exception('Selected card has no cardId');
      }
    }
    
    // Get drawnCardId from pending drawn card if not provided
    String? finalDrawnCardId = drawnCardId;
    if (finalDrawnCardId == null) {
      final pendingDrawnCard = _getPendingDrawnCard();
      if (pendingDrawnCard == null) {
        _log.warning('🎮 No drawn card available for replace action');
        throw Exception('No drawn card available for replace action');
      }
      finalDrawnCardId = pendingDrawnCard['cardId'] as String?;
      if (finalDrawnCardId == null) {
        throw Exception('Pending drawn card has no cardId');
      }
    }
    
    // Validate current phase allows replacing
    final currentPhase = _getCurrentTurnPhase();
    if (currentPhase != PlayerTurnPhase.hasDrawnCard) {
      _log.warning('🎮 Replacing card not allowed in current phase: ${currentPhase.name}');
    }
    
    return PlayerAction._(
      actionType: PlayerActionType.replaceCard,
      eventName: 'recall_player_action',
      payload: {
        'game_id': gameId,
        'action': 'replace_with_drawn',
        'card_id': finalCardId,
        'drawn_card_id': finalDrawnCardId,
      },
    );
  }

  // ========= SPECIAL ACTIONS =========

  /// Call recall to end the game
  static PlayerAction callRecall({
    required String gameId,
  }) {
    return PlayerAction._(
      actionType: PlayerActionType.callRecall,
      eventName: 'recall_call_recall',
      payload: {
        'game_id': gameId,
      },
    );
  }

  /// Play a card out of turn (matching rank)
  static PlayerAction playOutOfTurn({
    required String gameId,
    String? cardId,
  }) {
    // Get cardId from selected card if not provided
    String? finalCardId = cardId;
    if (finalCardId == null) {
      final selectedCard = _getSelectedCard();
      if (selectedCard == null) {
        _log.warning('🎮 No card selected for out-of-turn play');
        throw Exception('No card selected for out-of-turn play');
      }
      finalCardId = selectedCard['cardId'] as String?;
      if (finalCardId == null) {
        throw Exception('Selected card has no cardId');
      }
    }
    
    // Validate current phase allows out-of-turn play
    final currentPhase = _getCurrentTurnPhase();
    if (currentPhase != PlayerTurnPhase.outOfTurn) {
      _log.warning('🎮 Out-of-turn play not allowed in current phase: ${currentPhase.name}');
    }
    
    return PlayerAction._(
      actionType: PlayerActionType.playOutOfTurn,
      eventName: 'recall_play_out_of_turn',
      payload: {
        'game_id': gameId,
        'card_id': finalCardId,
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
