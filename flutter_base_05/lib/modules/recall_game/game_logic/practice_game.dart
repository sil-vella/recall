/// Practice Game Coordinator for Recall Game
///
/// This class provides a simplified game coordinator for practice sessions,
/// allowing players to learn the game mechanics without full WebSocket integration.

import 'package:recall/tools/logging/logger.dart';
import '../../../core/managers/state_manager.dart';
import '../utils/recall_game_helpers.dart';

const bool LOGGING_SWITCH = true;

class PracticeGameCoordinator {
  /// Coordinates practice game sessions for the Recall game
  
  late final dynamic gameStateManager;
  final StateManager _stateManager = StateManager();
  List<String> registeredEvents = [];
  String? _currentPracticeGameId;
  
  /// Constructor
  PracticeGameCoordinator({dynamic gameStateManager}) {
    this.gameStateManager = gameStateManager;
    _initializeGameEvents();
  }
  
  /// Initialize all game events for practice sessions
  void _initializeGameEvents() {
    Logger().info('Initializing practice game events', isOn: LOGGING_SWITCH);
    
    // Define all game events that can occur in practice mode
    final gameEvents = _getGameEvents();
    
    // Register each event for practice mode
    for (String eventName in gameEvents) {
      _registerPracticeEvent(eventName);
    }
    
    Logger().info('Practice game events initialized: ${gameEvents.length} events', isOn: LOGGING_SWITCH);
  }
  
  /// Get all available game events for practice sessions
  List<String> _getGameEvents() {
    return [
      'start_match',
      'draw_card', 
      'play_card',
      'discard_card',
      'take_from_discard',
      'call_recall',
      'same_rank_play',
      'jack_swap',
      'queen_peek',
      'completed_initial_peek'
    ];
  }
  
  /// Register a practice event handler
  void _registerPracticeEvent(String eventName) {
    if (!registeredEvents.contains(eventName)) {
      registeredEvents.add(eventName);
      Logger().info('Registered practice event: $eventName', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Handle practice game events
  bool handlePracticeEvent(String sessionId, String eventName, Map<String, dynamic> data) {
    try {
      Logger().info('Handling practice event: $eventName with data: $data', isOn: LOGGING_SWITCH);
      
      // Validate event is registered
      if (!registeredEvents.contains(eventName)) {
        Logger().warning('Unregistered practice event: $eventName', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Route to appropriate practice handler
      switch (eventName) {
        case 'start_match':
          return _handleStartMatch(sessionId, data);
        case 'draw_card':
          return _handleDrawCard(sessionId, data);
        case 'play_card':
          return _handlePlayCard(sessionId, data);
        case 'discard_card':
          return _handleDiscardCard(sessionId, data);
        case 'take_from_discard':
          return _handleTakeFromDiscard(sessionId, data);
        case 'call_recall':
          return _handleCallRecall(sessionId, data);
        case 'same_rank_play':
          return _handleSameRankPlay(sessionId, data);
        case 'jack_swap':
          return _handleJackSwap(sessionId, data);
        case 'queen_peek':
          return _handleQueenPeek(sessionId, data);
        case 'completed_initial_peek':
          return _handleCompletedInitialPeek(sessionId, data);
        default:
          Logger().warning('Unknown practice event: $eventName', isOn: LOGGING_SWITCH);
          return false;
      }
    } catch (e) {
      Logger().error('Error handling practice event $eventName: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }
  
  /// Get list of all registered practice events
  List<String> getRegisteredEvents() {
    return List.from(registeredEvents);
  }
  
  /// Check if an event is registered for practice
  bool isEventRegistered(String eventName) {
    return registeredEvents.contains(eventName);
  }
  
  /// Get count of registered events
  int getEventCount() {
    return registeredEvents.length;
  }
  
  // Practice event handlers
  
  bool _handleStartMatch(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Starting match for session $sessionId', isOn: LOGGING_SWITCH);
    
    try {
      // Generate practice game ID
      _currentPracticeGameId = 'practice_${DateTime.now().millisecondsSinceEpoch}';
      
      // Create practice game state
      final practiceGameState = _createPracticeGameState(data);
      
      // Update global state with practice game
      _updatePracticeGameState(practiceGameState);
      
      // Call game state manager if available
      final gameStateResult = gameStateManager?.onStartMatch(sessionId, data) ?? true;
      
      Logger().info('Practice: Match started successfully with ID $_currentPracticeGameId', isOn: LOGGING_SWITCH);
      return gameStateResult;
      
    } catch (e) {
      Logger().error('Practice: Failed to start match: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }
  
  bool _handleDrawCard(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Drawing card for session $sessionId', isOn: LOGGING_SWITCH);
    
    if (!isPracticeGameActive) {
      Logger().warning('Practice: No active practice game for draw card action', isOn: LOGGING_SWITCH);
      return false;
    }
    
    // Update game state for draw card action
    _updatePracticeGameAction('draw_card', data);
    
    final dataWithAction = {...data, 'action': 'draw_from_deck'};
    return _handlePlayerActionThroughRound(sessionId, dataWithAction);
  }
  
  bool _handlePlayCard(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Playing card for session $sessionId', isOn: LOGGING_SWITCH);
    final dataWithAction = {...data, 'action': 'play_card'};
    return _handlePlayerActionThroughRound(sessionId, dataWithAction);
  }
  
  bool _handleDiscardCard(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Discarding card for session $sessionId', isOn: LOGGING_SWITCH);
    final dataWithAction = {...data, 'action': 'discard_card'};
    return _handlePlayerActionThroughRound(sessionId, dataWithAction);
  }
  
  bool _handleTakeFromDiscard(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Taking from discard for session $sessionId', isOn: LOGGING_SWITCH);
    final dataWithAction = {...data, 'action': 'take_from_discard'};
    return _handlePlayerActionThroughRound(sessionId, dataWithAction);
  }
  
  bool _handleCallRecall(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Calling recall for session $sessionId', isOn: LOGGING_SWITCH);
    final dataWithAction = {...data, 'action': 'call_recall'};
    return _handlePlayerActionThroughRound(sessionId, dataWithAction);
  }
  
  bool _handleSameRankPlay(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Same rank play for session $sessionId', isOn: LOGGING_SWITCH);
    final dataWithAction = {...data, 'action': 'same_rank_play'};
    return _handlePlayerActionThroughRound(sessionId, dataWithAction);
  }
  
  bool _handleJackSwap(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Jack swap for session $sessionId', isOn: LOGGING_SWITCH);
    final dataWithAction = {...data, 'action': 'jack_swap'};
    return _handlePlayerActionThroughRound(sessionId, dataWithAction);
  }
  
  bool _handleQueenPeek(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Queen peek for session $sessionId', isOn: LOGGING_SWITCH);
    final dataWithAction = {...data, 'action': 'queen_peek'};
    return _handlePlayerActionThroughRound(sessionId, dataWithAction);
  }
  
  bool _handleCompletedInitialPeek(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Completed initial peek for session $sessionId', isOn: LOGGING_SWITCH);
    return gameStateManager?.onCompletedInitialPeek(sessionId, data) ?? false;
  }
  
  /// Handle player actions through game round (common pattern)
  bool _handlePlayerActionThroughRound(String sessionId, Map<String, dynamic> data) {
    try {
      // This would typically route through the game round manager
      // For practice mode, we can simulate the action
      Logger().info('Practice: Handling player action through round', isOn: LOGGING_SWITCH);
      return true; // Simulate successful action
    } catch (e) {
      Logger().error('Error in practice player action: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }
  
  /// Create practice game state from session data
  Map<String, dynamic> _createPracticeGameState(Map<String, dynamic> data) {
    final gameId = _currentPracticeGameId!;
    final timestamp = DateTime.now().toIso8601String();
    
    return {
      'gameId': gameId,
      'gameType': 'practice',
      'phase': 'waiting',
      'gamePhase': 'waiting',
      'isGameActive': true,
      'isPracticeMode': true,
      'currentPlayer': null,
      'players': <Map<String, dynamic>>[],
      'gameData': {
        'game_state': {
          'game_id': gameId,
          'phase': 'waiting',
          'current_player_id': null,
          'players': <Map<String, dynamic>>[],
          'deck': <Map<String, dynamic>>[],
          'draw_pile': <Map<String, dynamic>>[],
          'discard_pile': <Map<String, dynamic>>[],
          'game_ended': false,
          'winner': null,
          'recall_called_by': null,
          'last_action_time': timestamp,
          'game_start_time': timestamp,
        },
        'room_info': {
          'room_id': gameId,
          'max_players': data['numberOfOpponents'] ?? 4,
          'min_players': 2,
          'permission': 'practice',
          'game_type': 'practice',
          'turn_time_limit': data['turnTimer'] ?? 30,
          'difficulty_level': data['difficultyLevel'] ?? 'easy',
        },
        'session_info': {
          'session_id': data['sessionId'] ?? '',
          'created_at': timestamp,
          'last_updated': timestamp,
        }
      },
      'lastUpdated': timestamp,
    };
  }
  
  /// Update practice game state in global state manager
  void _updatePracticeGameState(Map<String, dynamic> practiceGameState) {
    try {
      // Get current games map
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      // Add practice game to games map
      currentGames[_currentPracticeGameId!] = practiceGameState;
      
      // Update global state
      RecallGameHelpers.updateUIState({
        'games': currentGames,
        'currentGameId': _currentPracticeGameId,
        'isInRoom': true,
        'currentRoomId': _currentPracticeGameId,
      });
      
      Logger().info('Practice: Updated game state for $_currentPracticeGameId', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to update game state: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Update practice game action in state
  void _updatePracticeGameAction(String action, Map<String, dynamic> data) {
    if (!isPracticeGameActive) return;
    
    try {
      // Get current games map
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      if (currentGames.containsKey(_currentPracticeGameId!)) {
        final currentGame = currentGames[_currentPracticeGameId!] as Map<String, dynamic>;
        final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final currentGameState = currentGameData['game_state'] as Map<String, dynamic>? ?? {};
        
        // Update game state with action
        final updatedGameState = Map<String, dynamic>.from(currentGameState);
        updatedGameState['last_action'] = action;
        updatedGameState['last_action_time'] = DateTime.now().toIso8601String();
        updatedGameState['last_action_data'] = data;
        
        // Update the game
        currentGames[_currentPracticeGameId!] = {
          ...currentGame,
          'gameData': {
            ...currentGameData,
            'game_state': updatedGameState,
          },
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        // Update global state
        RecallGameHelpers.updateUIState({
          'games': currentGames,
        });
        
        Logger().info('Practice: Updated action $action for $_currentPracticeGameId', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Failed to update game action: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Get current practice game ID
  String? get currentPracticeGameId => _currentPracticeGameId;
  
  /// Check if practice game is active
  bool get isPracticeGameActive => _currentPracticeGameId != null;
  
  /// End practice game
  void endPracticeGame() {
    if (_currentPracticeGameId != null) {
      Logger().info('Practice: Ending practice game $_currentPracticeGameId', isOn: LOGGING_SWITCH);
      
      // Update game state to ended
      _updatePracticeGameState({
        'gameId': _currentPracticeGameId!,
        'phase': 'ended',
        'gamePhase': 'ended',
        'isGameActive': false,
        'gameData': {
          'game_state': {
            'game_ended': true,
            'winner': 'practice_completed',
          }
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      _currentPracticeGameId = null;
    }
  }
  
  /// Dispose of practice coordinator resources
  void dispose() {
    // End any active practice game
    endPracticeGame();
    
    registeredEvents.clear();
    Logger().info('Practice game coordinator disposed', isOn: LOGGING_SWITCH);
  }
}
