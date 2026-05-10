/// In-memory game state store keyed by roomId.
/// Holds a mutable Map<String,dynamic> representing the current game state
/// that the GameRound reads/writes through the ServerGameStateCallback.
class GameStateStore {
  static final GameStateStore instance = GameStateStore._internal();
  final Map<String, Map<String, dynamic>> _roomIdToState = {};

  GameStateStore._internal();

  /// Ensure a state map exists for the room.
  Map<String, dynamic> ensure(String roomId) {
    return _roomIdToState.putIfAbsent(roomId, () => {
      'game_id': roomId,
      'game_state': {
        'gameId': roomId,
        'phase': 'waiting_for_players',
        'players': <Map<String, dynamic>>[],
        'discardPile': <Map<String, dynamic>>[],
        'drawPile': <Map<String, dynamic>>[],
      },
      // Removed lastUpdated - causes unnecessary state updates
    });
  }

  /// Get the full room state (mutable map).
  Map<String, dynamic> getState(String roomId) {
    return ensure(roomId);
  }

  /// Merge updates into the room state root.
  void mergeRoot(String roomId, Map<String, dynamic> updates) {
    final state = ensure(roomId);
    updates.forEach((k, v) => state[k] = v);
    // Removed lastUpdated - causes unnecessary state updates
  }

  /// Replace the inner game_state map.
  void setGameState(String roomId, Map<String, dynamic> gameState) {
    final state = ensure(roomId);
    state['game_state'] = gameState;
    // Removed lastUpdated - causes unnecessary state updates
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
