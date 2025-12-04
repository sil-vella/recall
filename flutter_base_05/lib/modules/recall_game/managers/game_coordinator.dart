import 'dart:async';
import '../../../../core/managers/state_manager.dart';
import 'player_action.dart';

/// Game Coordinator for handling all player game actions
/// 
/// This class centralizes all player game actions and ensures they go through
/// a consistent flow before being sent to the backend.
class GameCoordinator {
  static final GameCoordinator _instance = GameCoordinator._internal();
  
  factory GameCoordinator() => _instance;
  GameCoordinator._internal();
  
  /// Join a game
  Future<bool> joinGame({
    String? gameId,
    required String playerName,
    String playerType = 'human',
    int maxPlayers = 4,
  }) async {
    try {
      if (gameId == null || gameId.isEmpty) {
        return false;
      }
      
      final action = PlayerAction.joinGame(
        gameId: gameId,
        playerName: playerName,
        playerType: playerType,
        maxPlayers: maxPlayers,
      );
      await action.execute();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Leave a game
  Future<bool> leaveGame({
    required String gameId,
  }) async {
    try {
      final action = PlayerAction.leaveGame(gameId: gameId);
      await action.execute();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Create and execute a start match action
  Future<bool> startMatch() async {
    try {
      // Get current game state
      final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
      
      if (currentGameId.isEmpty) {
        return false;
      }
      
      // Get practice settings if this is a practice game (for showInstructions)
      final bool? showInstructions;
      if (currentGameId.startsWith('practice_room_')) {
        final practiceSettings = recallGameState['practiceSettings'] as Map<String, dynamic>?;
        showInstructions = practiceSettings?['showInstructions'] as bool?;
      } else {
        showInstructions = null; // Multiplayer games don't use showInstructions
      }
      
      // Create and execute the player action
      final action = PlayerAction.startMatch(
        gameId: currentGameId,
        showInstructions: showInstructions,
      );
      
      await action.execute();
      return true;
    } catch (e) {
      return false;
    }
  }
}