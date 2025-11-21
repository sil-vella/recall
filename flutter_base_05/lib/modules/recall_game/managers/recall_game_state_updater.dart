import 'dart:convert';

import '../../../core/managers/state_manager.dart';
import '../../../tools/logging/logger.dart';
import '../utils/state_queue_validator.dart';

/// Validated state updater for recall game state management
/// Ensures all state updates follow consistent structure and validation rules
class RecallGameStateUpdater {
  static RecallGameStateUpdater? _instance;
  static RecallGameStateUpdater get instance {
    _instance ??= RecallGameStateUpdater._internal();
    return _instance!;
  }
  
  // Logger and constants (must be declared before constructor)
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = true;
  
  // Dependencies
  final StateManager _stateManager = StateManager();
  final StateQueueValidator _validator = StateQueueValidator.instance;
  
  RecallGameStateUpdater._internal() {
    print('🎬🎬🎬 RecallGameStateUpdater: CONSTRUCTOR CALLED - Instance created (singleton initialization)');
    _logger.info('🎬 RecallGameStateUpdater: Instance created (singleton initialization)', isOn: LOGGING_SWITCH);
    
    // Set update handler to apply validated updates
    final validator = StateQueueValidator.instance;
    print('🎬🎬🎬 RecallGameStateUpdater: Got StateQueueValidator.instance, about to set handler');
    _logger.info('🎬 RecallGameStateUpdater: Setting update handler on StateQueueValidator', isOn: LOGGING_SWITCH);
    
    validator.setUpdateHandler((Map<String, dynamic> validatedUpdates) {
      print('🎬🎬🎬 RecallGameStateUpdater: HANDLER CALLBACK DEFINED - This closure was created');
      // CRITICAL: First log to verify this callback is actually being called
      print('🎬🎬🎬 RecallGameStateUpdater: HANDLER CALLBACK EXECUTING! Keys: ${validatedUpdates.keys.toList()}');
      _logger.info('🎬 RecallGameStateUpdater: Handler callback invoked with keys: ${validatedUpdates.keys.toList()}', isOn: LOGGING_SWITCH);
      try {
        print('🎬🎬🎬 RecallGameStateUpdater: About to call _applyValidatedUpdates');
        _applyValidatedUpdates(validatedUpdates);
        print('🎬🎬🎬 RecallGameStateUpdater: _applyValidatedUpdates returned');
        _logger.info('🎬 RecallGameStateUpdater: Handler callback completed successfully', isOn: LOGGING_SWITCH);
      } catch (e, stackTrace) {
        print('🎬🎬🎬 RecallGameStateUpdater: EXCEPTION in handler: $e');
        _logger.error('🎬 RecallGameStateUpdater: Exception in handler callback: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
        rethrow;
      }
    });
    
    _logger.info('🎬 RecallGameStateUpdater: Initialization complete - handler set and ready', isOn: LOGGING_SWITCH);
  }
  
  // Note: State schema validation has been moved to StateQueueValidator
  // See state_queue_validator.dart for the complete schema
  
  // NOTE: Widget slice computation has been removed.
  // Widgets now read directly from main state keys.
  
  /// Update state with validation
  /// Uses StateQueueValidator for validation, then applies widget slice computation
  void updateState(Map<String, dynamic> updates) {
    try {
      // Use StateQueueValidator to validate and queue the update
      // The validator will call our update handler with validated updates
      _validator.enqueueUpdate(updates);
      
    } catch (e) {
      _logger.error('RecallGameStateUpdater: State update failed: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }
  
  /// Apply validated updates - simplified to just merge and update state
  /// This is called by StateQueueValidator after validation
  /// Widgets now read directly from main state, no slice computation needed
  void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
    _logger.info('🎬 RecallGameStateUpdater: _applyValidatedUpdates START with keys: ${validatedUpdates.keys.toList()}', isOn: LOGGING_SWITCH);
    try {
      // Get current state
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      
      // Check if there are actual changes (excluding lastUpdated)
      // For complex objects (Maps, Lists), we need deep comparison
      bool hasActualChanges = false;
      for (final key in validatedUpdates.keys) {
        if (key == 'lastUpdated') continue;
        
        final currentValue = currentState[key];
        final newValue = validatedUpdates[key];
        
        // For simple types, use direct comparison
        if (currentValue == newValue) {
          continue;
        }
        
        // For complex types, use JSON comparison
        if (currentValue is Map || currentValue is List || newValue is Map || newValue is List) {
          try {
            final currentJson = jsonEncode(currentValue);
            final newJson = jsonEncode(newValue);
            if (currentJson != newJson) {
              hasActualChanges = true;
              break;
            }
          } catch (e) {
            // If JSON encoding fails, assume there's a change
            hasActualChanges = true;
            break;
          }
        } else {
          // For other types, if they're not equal, there's a change
          hasActualChanges = true;
          break;
        }
      }
      
      // Only proceed if there are actual changes
      if (!hasActualChanges) {
        _logger.info('🎬 RecallGameStateUpdater: No actual changes detected, skipping update', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('🎬 RecallGameStateUpdater: Has actual changes, proceeding with state update', isOn: LOGGING_SWITCH);
      
      // Merge and update state directly - no slice computation needed
      final newState = {
        ...currentState,
        ...validatedUpdates,
      };
      
      // Update StateManager directly
      _stateManager.updateModuleState('recall_game', newState);
      _logger.info('🎬 RecallGameStateUpdater: StateManager updated successfully', isOn: LOGGING_SWITCH);

    } catch (e) {
      _logger.error('RecallGameStateUpdater: Failed to apply validated updates: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }
  // NOTE: All widget slice computation methods have been removed.
  // Widgets now read directly from main state keys (games[currentGameId], etc.)
  
}

/// Centralized game state accessor for recall game operations
/// Provides type-safe methods to retrieve game state for specific game IDs
class RecallGameStateAccessor {
  static RecallGameStateAccessor? _instance;
  static RecallGameStateAccessor get instance {
    _instance ??= RecallGameStateAccessor._internal();
    return _instance!;
  }
  
  RecallGameStateAccessor._internal();
  
  // Dependencies
  final StateManager _stateManager = StateManager();
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = true;
  
  /// Get the complete state for a specific game ID
  /// Returns null if the game is not found
  Map<String, dynamic>? getGameStateForId(String gameId) {
    try {
      _logger.debug('RecallGameStateAccessor: Getting game state for ID: $gameId', isOn: LOGGING_SWITCH);
      
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final games = currentState['games'] as Map<String, dynamic>? ?? {};
      
      if (!games.containsKey(gameId)) {
        _logger.debug('RecallGameStateAccessor: Game ID "$gameId" not found in games map', isOn: LOGGING_SWITCH);
        return null;
      }
      
      final gameState = games[gameId] as Map<String, dynamic>? ?? {};
      
      _logger.debug('RecallGameStateAccessor: Successfully retrieved game state for ID: $gameId', isOn: LOGGING_SWITCH);
      
      return gameState;
      
    } catch (e) {
      _logger.error('RecallGameStateAccessor: Error getting game state for ID "$gameId": $e', isOn: true);
      return null;
    }
  }
  
  /// Get the game data for a specific game ID
  /// NOTE: With flattened structure, this returns the same as getGameStateForId
  /// Kept for backward compatibility
  Map<String, dynamic>? getGameDataForId(String gameId) {
    // With flattened structure, game data is the same as game state
    return getGameStateForId(gameId);
  }
  
  /// Get the game state data for a specific game ID
  /// NOTE: With flattened structure, this returns the same as getGameStateForId
  /// Kept for backward compatibility
  Map<String, dynamic>? getGameStateDataForId(String gameId) {
    // With flattened structure, game state data is the same as game state
    return getGameStateForId(gameId);
  }
  
  /// Get the current active game ID
  String getCurrentGameId() {
    try {
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      return currentGameId;
      
    } catch (e) {
      return '';
    }
  }
  
  /// Get the current active game state
  Map<String, dynamic>? getCurrentGameState() {
    final currentGameId = getCurrentGameId();
    if (currentGameId.isEmpty) return null;
    return getGameStateForId(currentGameId);
  }
  
  /// Get the current active game data
  Map<String, dynamic>? getCurrentGameData() {
    final currentGameId = getCurrentGameId();
    if (currentGameId.isEmpty) return null;
    return getGameDataForId(currentGameId);
  }
  
  /// Get the current active game state data
  Map<String, dynamic>? getCurrentGameStateData() {
    final currentGameId = getCurrentGameId();
    if (currentGameId.isEmpty) return null;
    return getGameStateDataForId(currentGameId);
  }
  
  /// Check if a specific game ID is the current active game
  bool isCurrentGame(String gameId) {
    final currentGameId = getCurrentGameId();
    return currentGameId == gameId;
  }
  
  /// Get the game type for a specific game ID
  String getGameType(String gameId) {
    try {
      final gameState = getGameStateForId(gameId);
      if (gameState == null) return 'normal';
      
      // With flattened structure, gameType is directly in games[gameId]
      final gameType = gameState['gameType']?.toString() ?? 'normal';
      return gameType;
      
    } catch (e) {
      return 'normal';
    }
  }
  
  /// Check if a specific game is a recall game
  bool isPracticeGame(String gameId) {
    final gameType = getGameType(gameId);
    return gameType == 'practice';
  }
  
  /// Check if the current active game is a recall game
  bool isCurrentGamePractice() {
    final currentGameId = getCurrentGameId();
    if (currentGameId.isEmpty) return false;
    return isPracticeGame(currentGameId);
  }
}
