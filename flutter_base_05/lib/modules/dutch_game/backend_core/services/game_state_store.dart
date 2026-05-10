import '../../utils/platform/shared_imports.dart';


/// In-memory game state store keyed by roomId.
/// Holds a mutable Map<String,dynamic> representing the current game state
/// that the GameRound reads/writes through the ServerGameStateCallback.
class GameStateStore {
  static final GameStateStore instance = GameStateStore._internal();
  final Map<String, Map<String, dynamic>> _roomIdToState = {};
  /// Per-room wire sequence for `game_state_updated` (embedded Dart server / practice).
  /// Client dedupe keys on this when present; must bump on every distinct outbound snapshot.
  final Map<String, int> _outboundStateSeqByRoom = {};
  GameStateStore._internal();

  /// Returns the next monotonic version for [roomId] (starts at 1).
  int bumpOutboundStateVersion(String roomId) {
    final next = (_outboundStateSeqByRoom[roomId] ?? 0) + 1;
    _outboundStateSeqByRoom[roomId] = next;
    return next;
  }

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
      
    }
    return state;
  }

  /// Merge updates into the room state root.
  void mergeRoot(String roomId, Map<String, dynamic> updates) {
    final state = ensure(roomId);
    
    // Log isClearAndCollect if present in updates
    if (updates.containsKey('isClearAndCollect')) {
      final value = updates['isClearAndCollect'];
      
    }
    
    // Log turn_events if present in updates
    if (updates.containsKey('turn_events')) {
      final turnEvents = updates['turn_events'] as List<dynamic>? ?? [];
      
      
      
      // Log previous turn_events in state before merge
      final previousTurnEvents = state['turn_events'] as List<dynamic>? ?? [];
      
    }
    
    updates.forEach((k, v) => state[k] = v);
    // Removed lastUpdated - causes unnecessary state updates
    
    
    // Log turn_events after merge
    if (updates.containsKey('turn_events')) {
      final mergedTurnEvents = state['turn_events'] as List<dynamic>? ?? [];
      
      
    }
  }

  /// Replace the inner game_state map.
  void setGameState(String roomId, Map<String, dynamic> gameState) {
    final state = ensure(roomId);
    // Log isClearAndCollect if present in gameState
    if (gameState.containsKey('isClearAndCollect')) {
      final value = gameState['isClearAndCollect'];
      
    }
    state['game_state'] = gameState;
    // Removed lastUpdated - causes unnecessary state updates
    
  }

  Map<String, dynamic> getGameState(String roomId) {
    final gameState = ensure(roomId)['game_state'] as Map<String, dynamic>;
    if (gameState.containsKey('isClearAndCollect')) {
      final value = gameState['isClearAndCollect'];
      
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
    _outboundStateSeqByRoom.remove(roomId);
  }

  /// Clear all room state (reset to init). Use when clearing all games (e.g. mode switch).
  void clearAll() {
    _roomIdToState.clear();
    _outboundStateSeqByRoom.clear();
    
  }
}


