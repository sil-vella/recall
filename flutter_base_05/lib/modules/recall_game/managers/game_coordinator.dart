import 'dart:async';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import 'validated_event_emitter.dart';
import 'validated_state_manager.dart';
import '../game_logic/practice_match/practice_game.dart';

const bool LOGGING_SWITCH = true;

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
    // Get current game state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      return false;
    }
    
    // Check if this is a practice game
    final stateAccessor = RecallGameStateAccessor.instance;
    final isPractice = stateAccessor.isCurrentGamePractice();
    
    if (isPractice) {
      // Route to practice coordinator
      Logger().info('GameCoordinator: Detected practice game, routing to PracticeGameCoordinator', isOn: LOGGING_SWITCH);
      
      // Import and use practice coordinator
      final practiceCoordinator = PracticeGameCoordinator.instance;
      practiceCoordinator.startGame();
      
      return true;
    } else {
      // Normal game - use existing logic
      Logger().info('GameCoordinator: Normal game detected, using standard start match flow', isOn: LOGGING_SWITCH);
      
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
}