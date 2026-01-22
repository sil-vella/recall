import 'dart:convert';

import '../../../core/managers/state_manager.dart';
import '../../../core/managers/state/immutable_state.dart';
import '../../../tools/logging/logger.dart';
import '../utils/state_queue_validator.dart';
import '../../dutch_game/models/state/dutch_game_state.dart';
import '../models/state/games_map.dart';
import '../../dutch_game/managers/dutch_event_handler_callbacks.dart';
// ignore: unused_import
import '../models/state/my_hand_state.dart'; // For future migration
// ignore: unused_import
import '../models/state/center_board_state.dart'; // For future migration
// ignore: unused_import
import '../models/state/opponents_panel_state.dart'; // For future migration
import '../../dutch_game/utils/card_animation_detector.dart';

/// Validated state updater for dutch game state management
/// Ensures all state updates follow consistent structure and validation rules
class DutchGameStateUpdater {
  static DutchGameStateUpdater? _instance;
  static DutchGameStateUpdater get instance {
    _instance ??= DutchGameStateUpdater._internal();
    return _instance!;
  }
  
  // Logger and constants (must be declared before constructor)
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = true; // Enabled for animation system testing and joinedGamesSlice debugging
  
  // Dependencies
  final StateManager _stateManager = StateManager();
  final StateQueueValidator _validator = StateQueueValidator.instance;
  
  DutchGameStateUpdater._internal() {
    if (LOGGING_SWITCH) {
      _logger.info('🎬 DutchGameStateUpdater: Instance created (singleton initialization)');
    }
    
    // Set update handler to apply validated updates
    final validator = StateQueueValidator.instance;
    if (LOGGING_SWITCH) {
      _logger.info('🎬 DutchGameStateUpdater: Setting update handler on StateQueueValidator');
    }
    
    validator.setUpdateHandler((Map<String, dynamic> validatedUpdates) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameStateUpdater: Handler callback invoked with keys: ${validatedUpdates.keys.toList()}');
      }
      try {
        _applyValidatedUpdates(validatedUpdates);
        if (LOGGING_SWITCH) {
          _logger.info('🎬 DutchGameStateUpdater: Handler callback completed successfully');
        }
      } catch (e, stackTrace) {
        if (LOGGING_SWITCH) {
          _logger.error('🎬 DutchGameStateUpdater: Exception in handler callback: $e', error: e, stackTrace: stackTrace);
        }
        rethrow;
      }
    });
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 DutchGameStateUpdater: Initialization complete - handler set and ready');
    }
  }
  
  // Note: State schema validation has been moved to StateQueueValidator
  // See state_queue_validator.dart for the complete schema
  
  /// Widget slice dependencies - only rebuild when these fields change
  /// Note: playerStatus and currentPlayerStatus are now computed from SSOT (games[gameId].gameData.game_state.players[])
  /// Widgets depend on 'games' to trigger recomputation when player status changes
  static const Map<String, Set<String>> _widgetDependencies = {
    'actionBar': {'currentGameId', 'games', 'isRoomOwner', 'isGameActive', 'isMyTurn'},
    'statusBar': {'currentGameId', 'games', 'gamePhase', 'isGameActive'},
    'myHand': {'currentGameId', 'games', 'isMyTurn', 'turn_events'},
    'centerBoard': {'currentGameId', 'games', 'gamePhase', 'isGameActive', 'discardPile', 'drawPile'},
    'opponentsPanel': {'currentGameId', 'games', 'currentPlayer', 'turn_events'},
    'gameInfo': {'currentGameId', 'games', 'gamePhase', 'isGameActive'},
    'joinedGamesSlice': {'games'}, // SIMPLIFIED: Compute from games map (SSOT) instead of joinedGames list
  };
  
  /// Update state with validation
  /// Uses StateQueueValidator for validation, then applies widget slice computation
  /// 
  /// MIGRATION NOTE: This method accepts Map<String, dynamic> for backward compatibility.
  /// For immutable state updates, use updateStateImmutable() instead.
  void updateState(Map<String, dynamic> updates) {
    try {
      // Use StateQueueValidator to validate and queue the update
      // The validator will call our update handler with validated updates
      _validator.enqueueUpdate(updates);
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('DutchGameStateUpdater: State update failed: $e', error: e);
      }
      rethrow;
    }
  }
  
  /// Update state synchronously (bypasses async queue)
  /// Validates the update and applies it immediately to StateManager
  /// Use this for critical flags that need to be set before async operations complete
  /// (e.g., isRandomJoinInProgress before emitting WebSocket events)
  void updateStateSync(Map<String, dynamic> updates) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameStateUpdater: Synchronous state update with keys: ${updates.keys.toList()}');
      }
      
      // Validate the update using the validator (but don't queue it)
      final validatedUpdates = _validator.validateUpdate(updates);
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 DutchGameStateUpdater: Validation passed, applying updates synchronously');
      }
      
      // Apply validated updates directly to StateManager (synchronous)
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final newState = {
        ...currentState,
        ...validatedUpdates,
      };
      
      _stateManager.updateModuleState('dutch_game', newState);
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameStateUpdater: Synchronous state update completed successfully');
      }
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('DutchGameStateUpdater: Synchronous state update failed: $e', error: e);
      }
      rethrow;
    }
  }
  
  /// Update state using immutable DutchGameState object
  /// This is the preferred method for new code
  void updateStateImmutable(DutchGameState newState) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameStateUpdater: Immutable state update');
      }
      _stateManager.updateModuleState('dutch_game', newState);
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('DutchGameStateUpdater: Immutable state update failed: $e', error: e);
      }
      rethrow;
    }
  }
  
  /// Helper: Convert legacy map-based games to GamesMap (for migration)
  GamesMap _convertLegacyGamesToImmutable(Map<String, dynamic> gamesMap) {
    try {
      return GamesMap.fromJson(gamesMap);
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('DutchGameStateUpdater: Failed to convert legacy games to immutable: $e', error: e);
      }
      return const GamesMap.empty();
    }
  }
  
  /// Helper: Get immutable DutchGameState from current state (for gradual migration)
  DutchGameState? _tryGetImmutableState() {
    try {
      return _stateManager.getModuleState<DutchGameState>('dutch_game');
    } catch (e) {
      return null;
    }
  }
  
  /// Apply validated updates with widget slice computation
  /// This is called by StateQueueValidator after validation
  /// Supports both legacy map-based updates and immutable state updates
  void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
    if (LOGGING_SWITCH) {
      _logger.info('🎬 DutchGameStateUpdater: _applyValidatedUpdates START with keys: ${validatedUpdates.keys.toList()}');
    }
    try {
      // Get current state (legacy map-based for now)
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 DutchGameStateUpdater: Getting current state from StateManager');
      }
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 DutchGameStateUpdater: Current state keys: ${currentState.keys.toList()}');
      }
      
      // Check if there are actual changes (excluding lastUpdated)
      // Use reference equality for immutable objects, structural equality for legacy data
      bool hasActualChanges = false;
      for (final key in validatedUpdates.keys) {
        if (key == 'lastUpdated') continue;
        
        final currentValue = currentState[key];
        final newValue = validatedUpdates[key];
        
        // Fast path: reference equality (works for immutable objects)
        if (identical(currentValue, newValue)) {
          continue;
        }
        
        // For immutable state objects, use equality operator
        if (currentValue is ImmutableState && newValue is ImmutableState) {
          if (currentValue == newValue) {
            continue;
          }
          hasActualChanges = true;
          break;
        }
        
        // For simple types, use direct comparison
        if (currentValue == newValue) {
          continue;
        }
        
        // For complex types (legacy maps/lists), use JSON comparison
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
        if (LOGGING_SWITCH) {
          _logger.info('🎬 DutchGameStateUpdater: No actual changes detected, skipping update');
        }
        return;
      }
      
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameStateUpdater: Has actual changes, proceeding with state update');
      }
      
      // Apply only the validated updates
      // Deep convert validatedUpdates to ensure all nested maps are Map<String, dynamic> (not LinkedMap from JSON decode)
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 DutchGameStateUpdater: Converting validated updates to Map<String, dynamic>');
      }
      final convertedValidatedUpdates = _deepConvertToMapStringDynamic(validatedUpdates) as Map<String, dynamic>;
      
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 DutchGameStateUpdater: Merging current state with validated updates');
      }
      final newState = {
        ...currentState,
        ...convertedValidatedUpdates,
      };
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 DutchGameStateUpdater: New state keys: ${newState.keys.toList()}');
      }
      
      // ========== ANIMATION DETECTION ==========
      // CRITICAL: Capture previous state slices BEFORE widget recomputation
      // This preserves the old state for the animation layer to use
      // The animation layer will animate from OLD state positions to NEW state positions
      // 
      // NOTE: Only widget slices (myHand, centerBoard, opponentsPanel) are from OLD state
      // The players state (with action fields) comes from NEW state (newState parameter)
      // The animation detector extracts players from newState['games'][gameId]['gameData']['game_state']['players']
      final previousSlices = {
        'myHand': currentState['myHand'],      // OLD state - before widget recomputation
        'centerBoard': currentState['centerBoard'],  // OLD state - before widget recomputation
        'opponentsPanel': currentState['opponentsPanel'], // OLD state - before widget recomputation
      };
      
      if (LOGGING_SWITCH) {
        // Log widget slice state BEFORE recomputation (OLD state - passed to animation detector)
        final myHandBefore = previousSlices['myHand'] as Map<String, dynamic>?;
        final centerBoardBefore = previousSlices['centerBoard'] as Map<String, dynamic>?;
        final opponentsPanelBefore = previousSlices['opponentsPanel'] as Map<String, dynamic>?;
        
        final beforeSummary = {
          'myHand': myHandBefore != null ? {
            'cards': (myHandBefore['cards'] as List?)?.length ?? 0,
            'selectedIndex': myHandBefore['selectedIndex'] ?? -1,
            'playerStatus': myHandBefore['playerStatus'] ?? 'unknown',
          } : null,
          'centerBoard': centerBoardBefore != null ? {
            'drawPileCount': centerBoardBefore['drawPileCount'] ?? 0,
            'topDiscard': centerBoardBefore['topDiscard'] != null ? 'present' : 'null',
            'topDraw': centerBoardBefore['topDraw'] != null ? 'present' : 'null',
          } : null,
          'opponentsPanel': opponentsPanelBefore != null ? {
            'opponents': (opponentsPanelBefore['opponents'] as List?)?.length ?? 0,
            'opponentsData': (opponentsPanelBefore['opponents'] as List?)?.map((opp) {
              if (opp is Map<String, dynamic>) {
                return {
                  'id': opp['id']?.toString() ?? 'unknown',
                  'handCount': (opp['hand'] as List?)?.length ?? 0,
                  'status': opp['status']?.toString() ?? 'unknown',
                  'score': opp['score'] ?? 0,
                  'hasAction': opp['action'] != null ? opp['action'].toString() : null,
                };
              }
              return null;
            }).where((e) => e != null).toList(),
            'currentTurnIndex': opponentsPanelBefore['currentTurnIndex'] ?? -1,
            'turn_events': (opponentsPanelBefore['turn_events'] as List?)?.length ?? 0,
            'currentPlayerStatus': opponentsPanelBefore['currentPlayerStatus']?.toString() ?? 'unknown',
          } : null,
        };
        
        _logger.info('🎬 DutchGameStateUpdater: Widget slices BEFORE recomputation (OLD state - passed to animation detector): $beforeSummary');
        
        // Log players state from newState (NEW state - contains action fields for detection)
        try {
          final currentGameId = newState['currentGameId']?.toString() ?? '';
          if (currentGameId.isNotEmpty) {
            final games = newState['games'] as Map<String, dynamic>? ?? {};
            final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
            final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
            final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
            final newPlayers = gameState['players'] as List<dynamic>? ?? [];
            
            final newPlayersWithActions = <String, String>{};
            for (final player in newPlayers) {
              if (player is Map<String, dynamic>) {
                final playerId = player['id']?.toString() ?? '';
                final action = player['action']?.toString();
                if (playerId.isNotEmpty && action != null && action.isNotEmpty) {
                  newPlayersWithActions[playerId] = action;
                }
              }
            }
            
            _logger.info('🎬 DutchGameStateUpdater: Players state in newState (NEW state - for action detection): count=${newPlayers.length}, playersWithActions=${newPlayersWithActions.isEmpty ? 'none' : newPlayersWithActions}');
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.debug('🎬 DutchGameStateUpdater: Failed to extract new players state: $e');
          }
        }
        
        _logger.info('🎬 DutchGameStateUpdater: Passing state to animation detector - currentGameId: ${newState['currentGameId']}, games: ${(newState['games'] as Map<String, dynamic>? ?? {}).length}');
      }
      
      // Pass state to animation detector BEFORE widget recomputation
      // The detector will:
      // - Detect actions from newState (contains action data in players)
      // - Capture previousSlices (OLD state) in CardAnimationManager for animation layer
      // - Queue animations
      // - Clear actions from newState (to prevent re-queueing)
      try {
        CardAnimationDetector().detectAndQueueActionsFromState(previousSlices, newState);
      } catch (e, stackTrace) {
        // Non-blocking error handling - animation detection should not block state updates
        if (LOGGING_SWITCH) {
          _logger.error('🎬 DutchGameStateUpdater: Error in animation detection (non-blocking): $e', error: e, stackTrace: stackTrace);
        }
      }
      
      // Rebuild dependent widget slices only if relevant fields changed
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 DutchGameStateUpdater: Updating widget slices for changed keys: ${validatedUpdates.keys.toSet()}');
      }
      final updatedStateWithSlices = _updateWidgetSlices(
        currentState,
        newState,
        validatedUpdates.keys.toSet(),
      );
      
      // Log state AFTER widget slices computed
      if (LOGGING_SWITCH) {
        final finalGameId = updatedStateWithSlices['currentGameId']?.toString() ?? '';
        final finalGames = updatedStateWithSlices['games'] as Map<String, dynamic>? ?? {};
        final finalGameCount = finalGames.length;
        
        // Log detailed widget slice state AFTER recomputation
        final myHandAfter = updatedStateWithSlices['myHand'] as Map<String, dynamic>?;
        final centerBoardAfter = updatedStateWithSlices['centerBoard'] as Map<String, dynamic>?;
        final opponentsPanelAfter = updatedStateWithSlices['opponentsPanel'] as Map<String, dynamic>?;
        
        final afterSummary = {
          'myHand': myHandAfter != null ? {
            'cards': (myHandAfter['cards'] as List?)?.length ?? 0,
            'selectedIndex': myHandAfter['selectedIndex'] ?? -1,
            'playerStatus': myHandAfter['playerStatus'] ?? 'unknown',
          } : null,
          'centerBoard': centerBoardAfter != null ? {
            'drawPileCount': centerBoardAfter['drawPileCount'] ?? 0,
            'topDiscard': centerBoardAfter['topDiscard'] != null ? 'present' : 'null',
            'topDraw': centerBoardAfter['topDraw'] != null ? 'present' : 'null',
          } : null,
          'opponentsPanel': opponentsPanelAfter != null ? {
            'opponents': (opponentsPanelAfter['opponents'] as List?)?.length ?? 0,
            'opponentsData': (opponentsPanelAfter['opponents'] as List?)?.map((opp) {
              if (opp is Map<String, dynamic>) {
                return {
                  'id': opp['id']?.toString() ?? 'unknown',
                  'handCount': (opp['hand'] as List?)?.length ?? 0,
                  'status': opp['status']?.toString() ?? 'unknown',
                  'score': opp['score'] ?? 0,
                  'hasAction': opp['action'] != null ? opp['action'].toString() : null,
                };
              }
              return null;
            }).where((e) => e != null).toList(),
            'currentTurnIndex': opponentsPanelAfter['currentTurnIndex'] ?? -1,
            'turn_events': (opponentsPanelAfter['turn_events'] as List?)?.length ?? 0,
            'currentPlayerStatus': opponentsPanelAfter['currentPlayerStatus']?.toString() ?? 'unknown',
          } : null,
          'joinedGamesSlice': updatedStateWithSlices['joinedGamesSlice'] != null ? 'present' : 'null',
          'gameInfo': updatedStateWithSlices['gameInfo'] != null ? 'present' : 'null',
        };
        
        _logger.info('🎬 DutchGameStateUpdater: Widget slices AFTER recomputation: $afterSummary');
        _logger.info('🎬 DutchGameStateUpdater: State AFTER widget slices computed - currentGameId: $finalGameId, games: $finalGameCount');
      }
      
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 DutchGameStateUpdater: Widget slices updated, final state keys: ${updatedStateWithSlices.keys.toList()}');
      }
      
      // Update StateManager
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 DutchGameStateUpdater: Updating StateManager with merged state');
      }
      _stateManager.updateModuleState('dutch_game', updatedStateWithSlices);
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameStateUpdater: StateManager updated successfully');
      }

    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('DutchGameStateUpdater: Failed to apply validated updates: $e', error: e);
      }
      rethrow;
    }
  }
  /// Recursively convert LinkedMap and other Map types to Map<String, dynamic>
  /// This ensures type safety when merging state from different sources (JSON decode vs. already-processed state)
  /// Returns the converted value (Map, List, or primitive)
  dynamic _deepConvertToMapStringDynamic(dynamic value) {
    if (value is Map) {
      // Convert map and recursively convert all nested values
      return Map<String, dynamic>.from(
        value.map((key, val) => MapEntry(
          key.toString(),
          _deepConvertToMapStringDynamic(val),
        )),
      );
    } else if (value is List) {
      // Convert list and recursively convert all nested values
      return value.map((item) => _deepConvertToMapStringDynamic(item)).toList();
    } else {
      // Primitive types, return as-is
      return value;
    }
  }
  
  /// Update widget slices based on dependency tracking
  Map<String, dynamic> _updateWidgetSlices(
    Map<String, dynamic> oldState,
    Map<String, dynamic> newState,
    Set<String> changedFields,
  ) {
    // Deep convert to ensure all nested maps are Map<String, dynamic> (not LinkedMap)
    final updatedState = _deepConvertToMapStringDynamic(newState) as Map<String, dynamic>;
    
    if (LOGGING_SWITCH) {
      _logger.debug('🎬 DutchGameStateUpdater: _updateWidgetSlices - Changed fields: $changedFields');
    }
    
    // CRITICAL: Always ensure joinedGamesSlice matches games map state
    // - If games map is empty, clear joinedGamesSlice
    // - If games field changed, always recompute the slice (games were added/removed)
    // - If slice is missing/empty but games map has games, recompute it
    // This ensures lobby screen shows correct games and clears stale data when switching modes
    final gamesMap = updatedState['games'] as Map<String, dynamic>? ?? {};
    final existingJoinedGamesSlice = updatedState['joinedGamesSlice'] as Map<String, dynamic>? ?? {};
    final existingJoinedGames = existingJoinedGamesSlice['games'] as List<dynamic>? ?? [];
    
    // Check if games field changed (this indicates games were added/removed)
    final gamesChanged = changedFields.contains('games');
    
    if (gamesMap.isEmpty) {
      // Games map is empty - clear joinedGamesSlice to match
      if (existingJoinedGames.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('🎬 DutchGameStateUpdater: Games map is empty but joinedGamesSlice has ${existingJoinedGames.length} games - clearing slice');
        }
        updatedState['joinedGamesSlice'] = {
          'games': <Map<String, dynamic>>[],
          'totalGames': 0,
          'isLoadingGames': false,
        };
      }
    } else if (gamesChanged) {
      // Games map changed - always recompute the slice to reflect current state
      // This ensures removed games are immediately removed from the slice
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameStateUpdater: Games map changed - recomputing joinedGamesSlice (games map has ${gamesMap.length} games)');
      }
      updatedState['joinedGamesSlice'] = _computeJoinedGamesSlice(newState);
    } else if (existingJoinedGamesSlice.isEmpty || !existingJoinedGamesSlice.containsKey('games')) {
      // Games map has games but slice is missing/empty - compute it
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameStateUpdater: Games map has ${gamesMap.length} games but joinedGamesSlice missing/empty - computing it');
      }
      updatedState['joinedGamesSlice'] = _computeJoinedGamesSlice(newState);
    }
    
    // Only rebuild slices that depend on changed fields
    for (final entry in _widgetDependencies.entries) {
      final sliceName = entry.key;
      final dependencies = entry.value;
      
      if (changedFields.any(dependencies.contains)) {
        if (LOGGING_SWITCH) {
          _logger.debug('🎬 DutchGameStateUpdater: Recomputing slice "$sliceName" due to changed fields: ${changedFields.where(dependencies.contains).toList()}');
        }
        
        switch (sliceName) {
          case 'actionBar':
            updatedState['actionBar'] = _computeActionBarSlice(newState);
            break;
          case 'statusBar':
            updatedState['statusBar'] = _computeStatusBarSlice(newState);
            break;
          case 'myHand':
            updatedState['myHand'] = _computeMyHandSlice(newState);
            break;
          case 'centerBoard':
            updatedState['centerBoard'] = _computeCenterBoardSlice(newState);
            break;
          case 'opponentsPanel':
            updatedState['opponentsPanel'] = _computeOpponentsPanelSlice(newState);
            break;
          case 'gameInfo':
            final gameInfoSlice = _computeGameInfoSlice(newState);
            updatedState['gameInfo'] = gameInfoSlice;
            if (LOGGING_SWITCH) {
              _logger.info('🎬 DutchGameStateUpdater: gameInfo slice recomputed - gamePhase: ${gameInfoSlice['gamePhase']}, currentGameId: ${gameInfoSlice['currentGameId']}');
            }
            break;
          case 'joinedGamesSlice':
            updatedState['joinedGamesSlice'] = _computeJoinedGamesSlice(newState);
            break;
        }
      }
    }
    
    // Extract currentPlayer from current game data and put it in main state
    final currentGameId = updatedState['currentGameId']?.toString() ?? '';
    final currentGame = gamesMap[currentGameId] as Map<String, dynamic>? ?? {};
    
    // Look for currentPlayer in the nested gameData.game_state structure
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final currentPlayer = gameState['currentPlayer'];
    
    if (currentPlayer != null) {
      updatedState['currentPlayer'] = currentPlayer;
    } else {
      updatedState['currentPlayer'] = null;
    }
    
    return updatedState;
  }
  
  /// Get current user status from SSOT (games[gameId].gameData.game_state.players[])
  /// Returns the status of the current user (the actual user playing the game)
  String _getCurrentUserStatus(Map<String, dynamic> state) {
    final currentGameId = state['currentGameId']?.toString() ?? '';
    final games = state['games'] as Map<String, dynamic>? ?? {};
    
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      return 'unknown';
    }
    
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final players = gameState['players'] as List<dynamic>? ?? [];
    
    // Get current user ID - use helper that handles both practice and multiplayer modes
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
    
    if (currentUserId.isEmpty) {
      return 'unknown';
    }
    
    for (final player in players) {
      if (player is Map<String, dynamic> && player['id']?.toString() == currentUserId) {
        return player['status']?.toString() ?? 'unknown';
      }
    }
    return 'unknown';
  }


  /// Get current player status from SSOT (games[gameId].gameData.game_state.currentPlayer)
  /// Returns the status of the current player (the player whose turn it is)
  String _getCurrentPlayerStatus(Map<String, dynamic> state) {
    final currentGameId = state['currentGameId']?.toString() ?? '';
    final games = state['games'] as Map<String, dynamic>? ?? {};
    
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      return 'unknown';
    }
    
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    
    if (currentPlayer != null) {
      return currentPlayer['status']?.toString() ?? 'unknown';
    }
    return 'unknown';
  }
  
  /// Compute action bar widget slice
  Map<String, dynamic> _computeActionBarSlice(Map<String, dynamic> state) {
    final isRoomOwner = state['isRoomOwner'] ?? false;
    final isGameActive = state['isGameActive'] ?? false;
    final isMyTurn = state['isMyTurn'] ?? false;
    final canCallDutch = state['canCallDutch'] ?? false;
    final canPlayCard = state['canPlayCard'] ?? false;
    final gamePhase = state['gamePhase'] ?? 'waiting';
    
    // Show start button if room owner and game is still in waiting phase
    final showStartButton = isRoomOwner && gamePhase == 'waiting';
    
    // Debug logging for action bar computation
    
    return {
      'showStartButton': showStartButton,
      'canPlayCard': canPlayCard && isMyTurn,
      'canCallDutch': canCallDutch && isMyTurn,
      'isGameStarted': isGameActive,
    };
  }
  
  /// Compute status bar widget slice
  Map<String, dynamic> _computeStatusBarSlice(Map<String, dynamic> state) {
    final gamePhase = state['gamePhase'] ?? 'waiting';
    final gameStatus = state['gameStatus'] ?? 'inactive';
    final playerCount = state['playerCount'] ?? 0;
    final turnNumber = state['turnNumber'] ?? 0;
    final roundNumber = state['roundNumber'] ?? 0;
    final isConnected = state['isConnected'] ?? false;
    
    // Derive current user status from SSOT
    final playerStatus = _getCurrentUserStatus(state);
    
    String turnInfo = '';
    if (gamePhase == 'playing') {
      turnInfo = 'Turn $turnNumber, Round $roundNumber';
    } else if (gamePhase == 'waiting') {
      turnInfo = 'Waiting for players ($playerCount)';
    }
    
    return {
      'currentPhase': gamePhase,
      'turnInfo': turnInfo,
      'playerCount': playerCount,
      'gameStatus': gameStatus,
      'connectionStatus': isConnected ? 'connected' : 'disconnected',
      'playerStatus': playerStatus, // Computed from SSOT
    };
  }
  
  /// Compute my hand widget slice
  Map<String, dynamic> _computeMyHandSlice(Map<String, dynamic> state) {
    final currentGameId = state['currentGameId']?.toString() ?? '';
    final games = state['games'] as Map<String, dynamic>? ?? {};
    
    // If no current game or game not found in games map
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      return {
        'cards': [],
        'selectedIndex': -1,
        'canSelectCards': false,
        'playerStatus': 'unknown', // Computed from SSOT
      };
    }
    
    // Get current game data from games map
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final isMyTurn = currentGame['isMyTurn'] ?? false;
    final canPlayCard = currentGame['canPlayCard'] ?? false;
    
    // Get turn_events from main state
    final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
    
    // Derive current user status from SSOT
    final playerStatus = _getCurrentUserStatus(state);
    
    return {
      'cards': currentGame['myHandCards'] ?? [],
      'selectedIndex': currentGame['selectedCardIndex'] ?? -1,
      'canSelectCards': isMyTurn && canPlayCard,
      'turn_events': turnEvents,
      'playerStatus': playerStatus, // Computed from SSOT
    };
  }
  
  /// Compute center board widget slice
  Map<String, dynamic> _computeCenterBoardSlice(Map<String, dynamic> state) {
    final currentGameId = state['currentGameId']?.toString() ?? '';
    final games = state['games'] as Map<String, dynamic>? ?? {};
    
    // If no current game or game not found in games map
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      return {
        'drawPileCount': 0,
        'topDiscard': null,
        'topDraw': null,
        'canDrawFromDeck': false,
        'canTakeFromDiscard': false,
        'playerStatus': 'unknown', // Computed from SSOT
        'matchPot': 0,
      };
    }
    
    // Get current game data from games map
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get pile information from game state
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final drawPileCount = drawPile.length;
    
    // Get match pot from game state (stored at game start)
    final matchPot = gameState['match_pot'] as int? ?? 0;
    
    // Get top draw card (convert ID-only to full data)
    Map<String, dynamic>? topDraw;
    if (drawPile.isNotEmpty) {
      final topDrawIdOnly = drawPile.last as Map<String, dynamic>?;
      if (topDrawIdOnly != null) {
        final topDrawCardId = topDrawIdOnly['cardId']?.toString();
        if (topDrawCardId != null) {
          // Convert ID-only card to full card data by looking up in originalDeck
          final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];
          for (final card in originalDeck) {
            if (card is Map<String, dynamic> && card['cardId']?.toString() == topDrawCardId) {
              topDraw = card;
              break;
            }
          }
        }
      }
    }
    
    // Derive current user status from SSOT
    final playerStatus = _getCurrentUserStatus(state);
    
    final result = {
      'drawPileCount': drawPileCount,
      'topDiscard': discardPile.isNotEmpty ? discardPile.last : null,
      'topDraw': topDraw,
      'canDrawFromDeck': drawPileCount > 0,
      'canTakeFromDiscard': discardPile.isNotEmpty,
      'playerStatus': playerStatus, // Computed from SSOT
      'matchPot': matchPot, // Match pot amount (coins collected from all players)
    };
    
    return result;
  }
  
  /// Compute opponents panel widget slice
  Map<String, dynamic> _computeOpponentsPanelSlice(Map<String, dynamic> state) {
    final currentGameId = state['currentGameId']?.toString() ?? '';
    final games = state['games'] as Map<String, dynamic>? ?? {};
    
    // If no current game or game not found in games map
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      return {
        'opponents': [],
        'currentTurnIndex': -1,
      };
    }
    
    // Get current game data from games map
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get all players from game state (includes full player data with status)
    final allPlayers = gameState['players'] as List<dynamic>? ?? [];
    
    // Get current user ID to filter out self from opponents
    // Use helper that handles both practice and multiplayer modes
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
    
    // Find current user's index in allPlayers list
    int currentUserIndex = -1;
    for (int i = 0; i < allPlayers.length; i++) {
      if (allPlayers[i]['id']?.toString() == currentUserId) {
        currentUserIndex = i;
        break;
      }
    }
    
    // Filter out current player and reorder opponents list
    // Order: Start from player after current user, wrap around to player before current user
    // Example: [A, B, Current, C, D] -> opponents display: [C, D, A, B]
    List<dynamic> opponents = [];
    if (currentUserIndex >= 0) {
      // Add players after current user
      for (int i = currentUserIndex + 1; i < allPlayers.length; i++) {
        opponents.add(allPlayers[i]);
      }
      // Add players before current user (wraps around)
      for (int i = 0; i < currentUserIndex; i++) {
        opponents.add(allPlayers[i]);
      }
    } else {
      // Fallback: if current user not found, just filter them out
      opponents = allPlayers.where((player) => 
        player['id']?.toString() != currentUserId
      ).toList();
    }
    
    // Find current player index in the reordered opponents list
    final currentPlayer = gameState['currentPlayer'];
    int currentTurnIndex = -1;
    if (currentPlayer != null) {
      final currentPlayerId = currentPlayer['id']?.toString() ?? '';
      currentTurnIndex = opponents.indexWhere((player) => 
        player['id']?.toString() == currentPlayerId
      );
    }
    
    // Get turn_events from main state
    final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
    
    // Derive current player status from SSOT
    final currentPlayerStatus = _getCurrentPlayerStatus(state);
    
    return {
      'opponents': opponents,
      'currentTurnIndex': currentTurnIndex,
      'turn_events': turnEvents,
      'currentPlayerStatus': currentPlayerStatus, // Computed from SSOT
    };
  }

  /// Compute game info widget slice
  Map<String, dynamic> _computeGameInfoSlice(Map<String, dynamic> state) {
    final currentGameId = state['currentGameId']?.toString() ?? '';
    final games = state['games'] as Map<String, dynamic>? ?? {};
    
    // If no current game or game not found in games map
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      return {
        'currentGameId': '',
        'currentSize': 0,
        'maxSize': 4,
        'gamePhase': 'waiting',
        'gameStatus': 'inactive',
        'isRoomOwner': false,
        'isInGame': false,
      };
    }
    
    // Get current game data from games map
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Use derived values for other fields (these are set during navigation)
    final gamePhase = state['gamePhase']?.toString() ?? 'waiting';
    final gameStatus = currentGame['gameStatus']?.toString() ?? 'inactive';
    final isRoomOwner = currentGame['isRoomOwner'] ?? false;
    final isInGame = currentGame['isInGame'] ?? false;
    
    // Read player count and max players from the actual game data (single source of truth)
    final currentSize = gameState['playerCount'] ?? 0;
    final maxSize = gameState['maxPlayers'] ?? 4;
    
    return {
      'currentGameId': currentGameId,
      'currentSize': currentSize,
      'maxSize': maxSize,
      'gamePhase': gamePhase,
      'gameStatus': gameStatus,
      'isRoomOwner': isRoomOwner,
      'isInGame': isInGame,
    };
  }

  /// Compute joined games widget slice
  /// SIMPLIFIED: Compute from games map - if a game is in the games map, the user has joined it
  /// No need to check userId/player IDs - the games map is the source of truth
  Map<String, dynamic> _computeJoinedGamesSlice(Map<String, dynamic> state) {
    final games = state['games'] as Map<String, dynamic>? ?? {};
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 DutchGameStateUpdater: Computing joinedGamesSlice - games map has ${games.length} games');
    }
    
    // Build joined games list from games map (single source of truth)
    // If a game is in the games map, the user has joined it - no need to check player IDs
    final joinedGamesList = <Map<String, dynamic>>[];
    
    // Collect invalid game IDs to remove after iteration
    final invalidGameIds = <String>[];
    
    for (final entry in games.entries) {
      final gameId = entry.key;
      final gameEntry = entry.value as Map<String, dynamic>? ?? {};
      final gameData = gameEntry['gameData'] as Map<String, dynamic>? ?? {};
      
      // Only include games with valid gameData and valid game_id
      // CRITICAL: Skip games with null or empty game_id (these are stale/invalid entries)
      final gameIdFromData = gameData['game_id']?.toString();
      if (gameData.isNotEmpty && gameIdFromData != null && gameIdFromData.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.debug('🎬 DutchGameStateUpdater: Adding game $gameId to joinedGamesSlice');
        }
        joinedGamesList.add(gameData);
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('🎬 DutchGameStateUpdater: Game $gameId skipped - gameData empty: ${gameData.isEmpty}, game_id: $gameIdFromData (invalid entry, will be removed)');
        }
        invalidGameIds.add(gameId);
      }
    }
    
    // CRITICAL: Remove invalid game entries from games map to prevent stale data
    // This ensures the games map only contains valid games
    if (invalidGameIds.isNotEmpty) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 DutchGameStateUpdater: Removing ${invalidGameIds.length} invalid game(s) from games map: ${invalidGameIds.join(", ")}');
      }
      // Trigger state update to remove invalid games using the state updater
      // This ensures proper validation and widget slice recomputation
      final updatedGames = Map<String, dynamic>.from(games);
      for (final invalidId in invalidGameIds) {
        updatedGames.remove(invalidId);
      }
      // Use state updater to remove invalid games (this will trigger proper recomputation)
      updateState({
        'games': updatedGames,
      });
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 DutchGameStateUpdater: Computed joinedGamesSlice from games map - found ${joinedGamesList.length} games');
    }
    
    return {
      'games': joinedGamesList,
      'totalGames': joinedGamesList.length,
      'isLoadingGames': false,
    };
  }
  
}

/// Centralized game state accessor for dutch game operations
/// Provides type-safe methods to retrieve game state for specific game IDs
class DutchGameStateAccessor {
  static DutchGameStateAccessor? _instance;
  static DutchGameStateAccessor get instance {
    _instance ??= DutchGameStateAccessor._internal();
    return _instance!;
  }
  
  DutchGameStateAccessor._internal();
  
  // Dependencies
  final StateManager _stateManager = StateManager();
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = true; // Enabled for animation system testing and joinedGamesSlice debugging
  
  /// Get the complete state for a specific game ID
  /// Returns null if the game is not found
  Map<String, dynamic>? getGameStateForId(String gameId) {
    try {
      if (LOGGING_SWITCH) {
        _logger.debug('DutchGameStateAccessor: Getting game state for ID: $gameId');
      }
      
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = currentState['games'] as Map<String, dynamic>? ?? {};
      
      if (!games.containsKey(gameId)) {
        if (LOGGING_SWITCH) {
          _logger.debug('DutchGameStateAccessor: Game ID "$gameId" not found in games map');
        }
        return null;
      }
      
      final gameState = games[gameId] as Map<String, dynamic>? ?? {};
      
      if (LOGGING_SWITCH) {
        _logger.debug('DutchGameStateAccessor: Successfully retrieved game state for ID: $gameId');
      }
      
      return gameState;
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('DutchGameStateAccessor: Error getting game state for ID "$gameId": $e', error: e);
      }
      return null;
    }
  }
  
  /// Get the game data for a specific game ID
  /// This contains the backend game data structure
  Map<String, dynamic>? getGameDataForId(String gameId) {
    try {
      final game = getGameStateForId(gameId);
      if (game == null) return null;
      
      final gameData = game['gameData'] as Map<String, dynamic>? ?? {};
      return gameData;
      
    } catch (e) {
      return null;
    }
  }
  
  /// Get the game state data for a specific game ID
  /// This contains the core game state (gameType, phase, status, etc.)
  Map<String, dynamic>? getGameStateDataForId(String gameId) {
    try {
      final gameData = getGameDataForId(gameId);
      if (gameData == null) return null;
      
      final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
      return gameState;
      
    } catch (e) {
      return null;
    }
  }
  
  /// Get the current active game ID
  String getCurrentGameId() {
    try {
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
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
      final gameState = getGameStateDataForId(gameId);
      if (gameState == null) return 'normal';
      
      final gameType = gameState['gameType']?.toString() ?? 'normal';
      return gameType;
      
    } catch (e) {
      return 'normal';
    }
  }
  
  /// Check if a specific game is a dutch game
  bool isPracticeGame(String gameId) {
    final gameType = getGameType(gameId);
    return gameType == 'practice';
  }
  
  /// Check if the current active game is a dutch game
  bool isCurrentGamePractice() {
    final currentGameId = getCurrentGameId();
    if (currentGameId.isEmpty) return false;
    return isPracticeGame(currentGameId);
  }

  /// Check if a specific game is a demo game
  bool isDemoGame(String gameId) {
    return gameId.startsWith('demo_game_');
  }

  /// Check if the current active game is a demo game
  bool isCurrentGameDemo() {
    final currentGameId = getCurrentGameId();
    if (currentGameId.isEmpty) return false;
    return isDemoGame(currentGameId);
  }
}
