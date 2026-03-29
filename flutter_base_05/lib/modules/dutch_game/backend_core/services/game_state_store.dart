import '../../utils/platform/shared_imports.dart';

const bool LOGGING_SWITCH = false; // Enabled for match start / state store

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
        'drawPile': <Map<String, dynamic>>[],
      },
      // Removed lastUpdated - causes unnecessary state updates
    });
  }

  /// Get the full room state (mutable map).
  Map<String, dynamic> getState(String roomId) {
    final state = ensure(roomId);
    if (state.containsKey('isClearAndCollect')) {
      final value = state['isClearAndCollect'];
      if (LOGGING_SWITCH) {
        _logger.info('🔍 GameStateStore.getState: isClearAndCollect in state: value=$value (type: ${value.runtimeType})');
      }
    }
    return state;
  }

  /// Merge updates into the room state root.
  void mergeRoot(String roomId, Map<String, dynamic> updates) {
    final state = ensure(roomId);
    
    // Log isClearAndCollect if present in updates
    if (updates.containsKey('isClearAndCollect')) {
      final value = updates['isClearAndCollect'];
      if (LOGGING_SWITCH) {
        _logger.info('💾 GameStateStore.mergeRoot: isClearAndCollect in updates: value=$value (type: ${value.runtimeType})');
      }
    }
    
    // Log turn_events if present in updates
    if (updates.containsKey('turn_events')) {
      final turnEvents = updates['turn_events'] as List<dynamic>? ?? [];
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - mergeRoot received turn_events: ${turnEvents.length} events');
      }
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${turnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}');
      }
      
      // Log previous turn_events in state before merge
      final previousTurnEvents = state['turn_events'] as List<dynamic>? ?? [];
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - Previous turn_events in state before merge: ${previousTurnEvents.length} events');
      }
    }
    
    updates.forEach((k, v) => state[k] = v);
    // Removed lastUpdated - causes unnecessary state updates
    if (LOGGING_SWITCH) {
      _logger.info('GameStateStore: merged root for $roomId -> keys: ${updates.keys}');
    }
    
    // Log turn_events after merge
    if (updates.containsKey('turn_events')) {
      final mergedTurnEvents = state['turn_events'] as List<dynamic>? ?? [];
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - turn_events in state after merge: ${mergedTurnEvents.length} events');
      }
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${mergedTurnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}');
      }
    }
  }

  /// Replace the inner game_state map.
  void setGameState(String roomId, Map<String, dynamic> gameState) {
    final state = ensure(roomId);
    // Log isClearAndCollect if present in gameState
    if (gameState.containsKey('isClearAndCollect')) {
      final value = gameState['isClearAndCollect'];
      if (LOGGING_SWITCH) {
        _logger.info('💾 GameStateStore.setGameState: isClearAndCollect in gameState: value=$value (type: ${value.runtimeType})');
      }
    }
    state['game_state'] = gameState;
    // Removed lastUpdated - causes unnecessary state updates
    if (LOGGING_SWITCH) {
      _logger.info('GameStateStore: set game_state for $roomId');
    }
  }

  Map<String, dynamic> getGameState(String roomId) {
    final gameState = ensure(roomId)['game_state'] as Map<String, dynamic>;
    if (gameState.containsKey('isClearAndCollect')) {
      final value = gameState['isClearAndCollect'];
      if (LOGGING_SWITCH) {
        _logger.info('🔍 GameStateStore.getGameState: isClearAndCollect in gameState: value=$value (type: ${value.runtimeType})');
      }
    }
    return gameState;
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

  /// Clear all room state (reset to init). Use when clearing all games (e.g. mode switch).
  void clearAll() {
    _roomIdToState.clear();
    if (LOGGING_SWITCH) {
      _logger.info('GameStateStore: clearAll() - cleared all room state');
    }
  }
}


