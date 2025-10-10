import 'dart:async';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import 'validated_event_emitter.dart';

/// PlayerAction class for handling individual player actions
class PlayerAction {
  final String eventName;
  final Map<String, dynamic> gameData;
  final DateTime timestamp;
  
  PlayerAction({
    required this.eventName,
    required this.gameData,
  }) : timestamp = DateTime.now();
  
    /// Execute the player action
  Future<bool> execute() async {
    try {
      // Use validated event emitter for consistent validation and user ID injection
      final eventEmitter = RecallGameEventEmitter.instance;
      
      // Send the action via validated event emitter
      await eventEmitter.emit(
        eventType: eventName,
        data: gameData,
      );
      
      // Check if the emission was successful (no exception thrown)
      return true;
    } catch (e) {
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
  static final GameCoordinator _instance = GameCoordinator._internal();
  static const bool LOGGING_SWITCH = true;
  factory GameCoordinator() => _instance;
  GameCoordinator._internal();
  
  /// Join a game
  Future<bool> joinGame({
    String? gameId,
    required String playerName,
    String playerType = 'human',
    int maxPlayers = 4,
  }) async {
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
    // Create game data for leave game
    final gameData = {
      'game_id': gameId,
    };
    
    // Create and execute the player action
    final action = PlayerAction(
      eventName: 'leave_game',
      gameData: gameData,
    );
    
    return await action.execute();
  }
  
  /// Create and execute a start match action
  Future<bool> startMatch() async {
    Logger().info('🎯 GameCoordinator: startMatch() called', isOn: LOGGING_SWITCH);
    
    // Get current game state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    
    Logger().info('🎯 GameCoordinator: Current game ID: $currentGameId', isOn: LOGGING_SWITCH);
    
    if (currentGameId.isEmpty) {
      Logger().warning('🎯 GameCoordinator: No current game ID found', isOn: LOGGING_SWITCH);
      return false;
    }
    
    // Create game data for start match (using game_id as per validated event emitter)
    final gameData = {
      'game_id': currentGameId,
    };
    
    Logger().info('🎯 GameCoordinator: Creating PlayerAction with data: $gameData', isOn: LOGGING_SWITCH);
    
    // Create and execute the player action
    final action = PlayerAction(
      eventName: 'start_match',
      gameData: gameData,
    );
    
    Logger().info('🎯 GameCoordinator: Executing PlayerAction...', isOn: LOGGING_SWITCH);
    final result = await action.execute();
    
    Logger().info('🎯 GameCoordinator: PlayerAction.execute() returned: $result', isOn: LOGGING_SWITCH);
    
    return result;
  }
}