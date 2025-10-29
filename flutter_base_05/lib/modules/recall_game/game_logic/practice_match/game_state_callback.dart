/// Game State Callback Interface
///
/// This interface abstracts the communication layer between GameRound and
/// the state management system. This allows GameRound to work identically
/// in both Flutter practice (StateManager) and Dart backend (WebSocket broadcasts).

abstract class GameStateCallback {
  /// Update player status for a specific player or all players
  /// 
  /// [status] The new status to set
  /// [playerId] Optional player ID. If null, updates all players
  /// [updateMainState] Whether to also update the main game state playerStatus
  /// [triggerInstructions] Whether to trigger contextual instructions after status update
  void onPlayerStatusChanged(String status, {
    String? playerId,
    bool updateMainState = true,
    bool triggerInstructions = false,
  });

  /// Update game state with provided updates
  /// 
  /// [updates] Map of state updates to apply
  void onGameStateChanged(Map<String, dynamic> updates);

  /// Notify that discard pile has been updated
  void onDiscardPileChanged();

  /// Notify of an action error
  /// 
  /// [message] Error message
  /// [data] Optional additional error data
  void onActionError(String message, {Map<String, dynamic>? data});

  /// Get card by ID from game state
  /// 
  /// [gameState] Current game state
  /// [cardId] Card ID to find
  /// Returns full card data or null if not found
  Map<String, dynamic>? getCardById(Map<String, dynamic> gameState, String cardId);

  /// Get current game state
  /// Returns the current game state map
  Map<String, dynamic> getCurrentGameState();

  /// Get current games map
  /// Returns the current games map from state
  Map<String, dynamic> get currentGamesMap;
}
