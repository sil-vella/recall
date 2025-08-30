import 'dart:async';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';

/// PlayerAction class for handling individual player actions
class PlayerAction {
  static final Logger _log = Logger();
  
  final String eventName;
  final Map<String, dynamic> gameData;
  final DateTime timestamp;
  
  PlayerAction({
    required this.eventName,
    required this.gameData,
  }) : timestamp = DateTime.now();
  
    /// Execute the player action
  Future<bool> execute() async {
    _log.info('🎮 [PlayerAction] Executing action: $eventName');
    _log.info('🎮 [PlayerAction] Game data: $gameData');
    
    try {
      // Get WebSocket manager instance
      final wsManager = WebSocketManager.instance;
      
      // Check if WebSocket is connected
      if (!wsManager.isConnected) {
        _log.error('❌ [PlayerAction] WebSocket not connected, cannot execute action: $eventName');
        return false;
      }
      
      // Send the action directly via WebSocket
      final result = await wsManager.sendCustomEvent(eventName, gameData);
      
      if (result['success'] == true) {
        _log.info('✅ [PlayerAction] Action $eventName sent successfully');
        return true;
      } else {
        _log.error('❌ [PlayerAction] Failed to send action: $eventName - ${result['error']}');
        return false;
      }
    } catch (e) {
      _log.error('❌ [PlayerAction] Error executing action $eventName: $e');
      return false;
    }
  }
  
  @override
  String toString() {
    return 'PlayerAction(eventName: $eventName, gameData: $gameData, timestamp: $timestamp)';
  }
}

/// Game Coordinator for handling all player game actions
/// 
/// This class centralizes all player game actions and ensures they go through
/// a consistent flow before being sent to the backend.
class GameCoordinator {
  static final Logger _log = Logger();
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
    _log.info('🎮 [GameCoordinator] Creating join game action');
    
    // Create game data for join game
    final gameData = {
      if (gameId != null) 'game_id': gameId,
      'player_name': playerName,
      'player_type': playerType,
      'max_players': maxPlayers,
    };
    
    // Create and execute the player action
    final action = PlayerAction(
      eventName: 'join_game',
      gameData: gameData,
    );
    
    return await action.execute();
  }
  
  /// Leave a game
  Future<bool> leaveGame({
    required String gameId,
  }) async {
    _log.info('🎮 [GameCoordinator] Creating leave game action');
    
    // Create game data for leave game
    final gameData = {
      'game_id': gameId,
    };
    
    // Create and execute the player action
    final action = PlayerAction(
      eventName: 'recall_leave_game',
      gameData: gameData,
    );
    
    return await action.execute();
  }
  
  /// Create and execute a start match action
  Future<bool> startMatch() async {
    _log.info('🎮 [GameCoordinator] Creating start match action');
    
    // Get current game state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _log.error('❌ [GameCoordinator] No current game ID found for start match action');
      return false;
    }
    
    // Create game data for start match (using game_id as per validated event emitter)
    final gameData = {
      'game_id': currentGameId,
    };
    
    // Create and execute the player action
    final action = PlayerAction(
      eventName: 'start_match',
      gameData: gameData,
    );
    
    return await action.execute();
  }
}