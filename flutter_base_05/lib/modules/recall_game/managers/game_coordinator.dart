import 'dart:async';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../utils/validated_event_emitter.dart';

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
  
  /// Create and execute a draw card action
  Future<bool> drawCard({String source = 'deck'}) async {
    _log.info('🎮 [GameCoordinator] Creating draw card action');
    
    // Get current game state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final playerId = loginState['userId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _log.error('❌ [GameCoordinator] No current game ID found for draw card action');
      return false;
    }
    
    if (playerId.isEmpty) {
      _log.error('❌ [GameCoordinator] No player ID found for draw card action');
      return false;
    }
    
    // Create game data for draw card (using validated event emitter fields)
    final gameData = {
      'game_id': currentGameId,
      'player_id': playerId,
      'source': source, // 'deck' or 'discard'
    };
    
    // Create and execute the player action
    final action = PlayerAction(
      eventName: 'draw_card',
      gameData: gameData,
    );
    
    return await action.execute();
  }
  
  /// Create and execute a play card action
  Future<bool> playCard(String cardId, {int? replaceIndex}) async {
    _log.info('🎮 [GameCoordinator] Creating play card action');
    
    // Get current game state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final playerId = loginState['userId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _log.error('❌ [GameCoordinator] No current game ID found for play card action');
      return false;
    }
    
    if (playerId.isEmpty) {
      _log.error('❌ [GameCoordinator] No player ID found for play card action');
      return false;
    }
    
    if (cardId.isEmpty) {
      _log.error('❌ [GameCoordinator] No card ID provided for play card action');
      return false;
    }
    
    // Create game data for play card (using validated event emitter fields)
    final gameData = {
      'game_id': currentGameId,
      'card_id': cardId,
      'player_id': playerId,
      if (replaceIndex != null) 'replace_index': replaceIndex,
    };
    
    // Create and execute the player action
    final action = PlayerAction(
      eventName: 'play_card',
      gameData: gameData,
    );
    
    return await action.execute();
  }
  
  /// Create and execute a discard card action
  Future<bool> discardCard(String cardId) async {
    _log.info('🎮 [GameCoordinator] Creating discard card action');
    
    // Get current game state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final playerId = loginState['userId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _log.error('❌ [GameCoordinator] No current game ID found for discard card action');
      return false;
    }
    
    if (playerId.isEmpty) {
      _log.error('❌ [GameCoordinator] No player ID found for discard card action');
      return false;
    }
    
    if (cardId.isEmpty) {
      _log.error('❌ [GameCoordinator] No card ID provided for discard card action');
      return false;
    }
    
    // Create game data for discard card (using validated event emitter fields)
    final gameData = {
      'game_id': currentGameId,
      'card_id': cardId,
      'player_id': playerId,
    };
    
    // Create and execute the player action
    final action = PlayerAction(
      eventName: 'discard_card',
      gameData: gameData,
    );
    
    return await action.execute();
  }
  
  /// Create and execute a take from discard action
  Future<bool> takeFromDiscard() async {
    _log.info('🎮 [GameCoordinator] Creating take from discard action');
    
    // Use the draw card action with 'discard' source
    return await drawCard(source: 'discard');
  }
  
  /// Create and execute a call recall action
  Future<bool> callRecall() async {
    _log.info('🎮 [GameCoordinator] Creating call recall action');
    
    // Get current game state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final playerId = loginState['userId']?.toString() ?? '';
    
    if (currentGameId.isEmpty) {
      _log.error('❌ [GameCoordinator] No current game ID found for call recall action');
      return false;
    }
    
    if (playerId.isEmpty) {
      _log.error('❌ [GameCoordinator] No player ID found for call recall action');
      return false;
    }
    
    // Create game data for call recall (using validated event emitter fields)
    final gameData = {
      'game_id': currentGameId,
      'player_id': playerId,
    };
    
    // Create and execute the player action
    final action = PlayerAction(
      eventName: 'call_recall',
      gameData: gameData,
    );
    
    return await action.execute();
  }
}
