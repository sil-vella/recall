import '../../../utils/server_logger.dart';

const bool LOGGING_SWITCH = true;

/// In-memory game state store keyed by roomId.
/// Holds a mutable Map<String,dynamic> representing the current game state
/// that the GameRound reads/writes through the ServerGameStateCallback.
class GameStateStore {
  static final GameStateStore instance = GameStateStore._internal();
  final Map<String, Map<String, dynamic>> _roomIdToState = {};
  final Logger _logger = Logger();

  GameStateStore._internal();

  /// Ensure a state map exists for the room.
  Map<String, dynamic> ensure(String roomId) {
    return _roomIdToState.putIfAbsent(roomId, () => {
      'game_id': roomId,
      'game_state': {
        'gameId': roomId,
        'players': <Map<String, dynamic>>[],
        'discardPile': <Map<String, dynamic>>[],
        'drawPile': <String>[],
      },
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  /// Get the full room state (mutable map).
  Map<String, dynamic> getState(String roomId) {
    return ensure(roomId);
  }

  /// Merge updates into the room state root.
  void mergeRoot(String roomId, Map<String, dynamic> updates) {
    final state = ensure(roomId);
    
    // Log turn_events if present in updates
    if (updates.containsKey('turn_events')) {
      final turnEvents = updates['turn_events'] as List<dynamic>? ?? [];
      _logger.info('🔍 TURN_EVENTS DEBUG - mergeRoot received turn_events: ${turnEvents.length} events', isOn: LOGGING_SWITCH);
      _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${turnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}', isOn: LOGGING_SWITCH);
      
      // Log previous turn_events in state before merge
      final previousTurnEvents = state['turn_events'] as List<dynamic>? ?? [];
      _logger.info('🔍 TURN_EVENTS DEBUG - Previous turn_events in state before merge: ${previousTurnEvents.length} events', isOn: LOGGING_SWITCH);
    }
    
    updates.forEach((k, v) => state[k] = v);
    state['lastUpdated'] = DateTime.now().toIso8601String();
    _logger.info('GameStateStore: merged root for $roomId -> keys: ${updates.keys}', isOn: LOGGING_SWITCH);
    
    // Log turn_events after merge
    if (updates.containsKey('turn_events')) {
      final mergedTurnEvents = state['turn_events'] as List<dynamic>? ?? [];
      _logger.info('🔍 TURN_EVENTS DEBUG - turn_events in state after merge: ${mergedTurnEvents.length} events', isOn: LOGGING_SWITCH);
      _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${mergedTurnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}', isOn: LOGGING_SWITCH);
    }
  }

  /// Replace the inner game_state map.
  void setGameState(String roomId, Map<String, dynamic> gameState) {
    final state = ensure(roomId);
    state['game_state'] = gameState;
    state['lastUpdated'] = DateTime.now().toIso8601String();
    _logger.info('GameStateStore: set game_state for $roomId', isOn: LOGGING_SWITCH);
  }

  Map<String, dynamic> getGameState(String roomId) {
    return ensure(roomId)['game_state'] as Map<String, dynamic>;
  }

  /// Utility to find a full card by id from the current game_state.
  Map<String, dynamic>? getCardById(String roomId, String cardId) {
    final gameState = getGameState(roomId);
    final originalDeck = (gameState['originalDeck'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>();
    for (final c in originalDeck) {
      if (c['cardId'] == cardId) return c;
    }
    return null;
  }

  void clear(String roomId) {
    _roomIdToState.remove(roomId);
  }
}


