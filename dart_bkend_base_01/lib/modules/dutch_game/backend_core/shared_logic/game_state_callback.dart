import '../../utils/platform/shared_imports.dart';

/// Game State Callback Interface
///
/// This interface abstracts the communication layer between GameRound and
/// the state management system. This allows GameRound to work identically
/// in both Flutter dutch (StateManager) and Dart backend (WebSocket broadcasts).

abstract class GameStateCallback {
  /// Update game state with provided updates
  /// 
  /// [updates] Map of state updates to apply
  void onGameStateChanged(Map<String, dynamic> updates);

  /// Send game state update to a single player (for sensitive data like drawn card details)
  /// 
  /// [playerId] The player ID (session ID) to send the update to
  /// [updates] Map of state updates to apply and send
  void sendGameStateToPlayer(String playerId, Map<String, dynamic> updates);

  /// Broadcast game state update to all players except one (for hiding sensitive data from specific player)
  /// 
  /// [excludePlayerId] The player ID (session ID) to exclude from the broadcast
  /// [updates] Map of state updates to apply and broadcast
  void broadcastGameStateExcept(String excludePlayerId, Map<String, dynamic> updates);

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

  /// Get current turn_events list from main state
  /// Returns a copy of the current turn_events list
  List<Map<String, dynamic>> getCurrentTurnEvents();

  /// Get currentPlayer from main state
  /// Returns the currentPlayer map or null if not available
  Map<String, dynamic>? getMainStateCurrentPlayer();

  /// Get timer configuration for player actions
  /// Returns map with 'turnTimeLimit' (int) and 'showInstructions' (bool, default false)
  Map<String, dynamic> getTimerConfig();

  /// Trigger leave room for a player (auto-kick on missed actions)
  /// 
  /// [playerId] The player ID (session ID) to remove from the room
  /// This should only be called for multiplayer matches, not practice matches
  void triggerLeaveRoom(String playerId);

  /// Called when game ends - allows callback implementation to handle stats update
  /// 
  /// [winners] List of winner information with playerId, playerName, winType
  /// [allPlayers] List of all players with their final state
  /// [matchPot] The total pot amount (coin_cost × active_players) to be awarded to winner(s)
  /// This should only be called for multiplayer matches, not practice matches
  void onGameEnded(List<Map<String, dynamic>> winners, List<Map<String, dynamic>> allPlayers, {int? matchPot});
}
