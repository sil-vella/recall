import 'dart:convert';

import '../../../core/managers/state_manager.dart';
import '../../../core/managers/state/immutable_state.dart';
import '../../../tools/logging/logger.dart';
import '../utils/state_queue_validator.dart';
import '../../cleco_game/models/state/cleco_game_state.dart';
import '../models/state/games_map.dart';
import '../../cleco_game/managers/cleco_event_handler_callbacks.dart';
// ignore: unused_import
import '../models/state/my_hand_state.dart'; // For future migration
// ignore: unused_import
import '../models/state/center_board_state.dart'; // For future migration
// ignore: unused_import
import '../models/state/opponents_panel_state.dart'; // For future migration

/// Validated state updater for cleco game state management
/// Ensures all state updates follow consistent structure and validation rules
class ClecoGameStateUpdater {
  static ClecoGameStateUpdater? _instance;
  static ClecoGameStateUpdater get instance {
    _instance ??= ClecoGameStateUpdater._internal();
    return _instance!;
  }
  
  // Logger and constants (must be declared before constructor)
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false; // Enabled for draw card debugging
  
  // Dependencies
  final StateManager _stateManager = StateManager();
  final StateQueueValidator _validator = StateQueueValidator.instance;
  
  ClecoGameStateUpdater._internal() {
    _logger.info('🎬 ClecoGameStateUpdater: Instance created (singleton initialization)', isOn: LOGGING_SWITCH);
    
    // Set update handler to apply validated updates
    final validator = StateQueueValidator.instance;
    _logger.info('🎬 ClecoGameStateUpdater: Setting update handler on StateQueueValidator', isOn: LOGGING_SWITCH);
    
    validator.setUpdateHandler((Map<String, dynamic> validatedUpdates) {
      _logger.info('🎬 ClecoGameStateUpdater: Handler callback invoked with keys: ${validatedUpdates.keys.toList()}', isOn: LOGGING_SWITCH);
      try {
        _applyValidatedUpdates(validatedUpdates);
        _logger.info('🎬 ClecoGameStateUpdater: Handler callback completed successfully', isOn: LOGGING_SWITCH);
      } catch (e, stackTrace) {
        _logger.error('🎬 ClecoGameStateUpdater: Exception in handler callback: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
        rethrow;
      }
    });
    
    _logger.info('🎬 ClecoGameStateUpdater: Initialization complete - handler set and ready', isOn: LOGGING_SWITCH);
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
    'joinedGamesSlice': {'joinedGames', 'totalJoinedGames', 'joinedGamesTimestamp'},
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
      _logger.error('ClecoGameStateUpdater: State update failed: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }
  
  /// Update state synchronously (bypasses async queue)
  /// Validates the update and applies it immediately to StateManager
  /// Use this for critical flags that need to be set before async operations complete
  /// (e.g., isRandomJoinInProgress before emitting WebSocket events)
  void updateStateSync(Map<String, dynamic> updates) {
    try {
      _logger.info('🎬 ClecoGameStateUpdater: Synchronous state update with keys: ${updates.keys.toList()}', isOn: LOGGING_SWITCH);
      
      // Validate the update using the validator (but don't queue it)
      final validatedUpdates = _validator.validateUpdate(updates);
      _logger.debug('🎬 ClecoGameStateUpdater: Validation passed, applying updates synchronously', isOn: LOGGING_SWITCH);
      
      // Apply validated updates directly to StateManager (synchronous)
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final newState = {
        ...currentState,
        ...validatedUpdates,
      };
      
      _stateManager.updateModuleState('cleco_game', newState);
      _logger.info('🎬 ClecoGameStateUpdater: Synchronous state update completed successfully', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      _logger.error('ClecoGameStateUpdater: Synchronous state update failed: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }
  
  /// Update state using immutable ClecoGameState object
  /// This is the preferred method for new code
  void updateStateImmutable(ClecoGameState newState) {
    try {
      _logger.info('🎬 ClecoGameStateUpdater: Immutable state update', isOn: LOGGING_SWITCH);
      _stateManager.updateModuleState('cleco_game', newState);
    } catch (e) {
      _logger.error('ClecoGameStateUpdater: Immutable state update failed: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }
  
  /// Helper: Convert legacy map-based games to GamesMap (for migration)
  GamesMap _convertLegacyGamesToImmutable(Map<String, dynamic> gamesMap) {
    try {
      return GamesMap.fromJson(gamesMap);
    } catch (e) {
      _logger.error('ClecoGameStateUpdater: Failed to convert legacy games to immutable: $e', isOn: LOGGING_SWITCH);
      return const GamesMap.empty();
    }
  }
  
  /// Helper: Get immutable ClecoGameState from current state (for gradual migration)
  ClecoGameState? _tryGetImmutableState() {
    try {
      return _stateManager.getModuleState<ClecoGameState>('cleco_game');
    } catch (e) {
      return null;
    }
  }
  
  /// Apply validated updates with widget slice computation
  /// This is called by StateQueueValidator after validation
  /// Supports both legacy map-based updates and immutable state updates
  void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
    _logger.info('🎬 ClecoGameStateUpdater: _applyValidatedUpdates START with keys: ${validatedUpdates.keys.toList()}', isOn: LOGGING_SWITCH);
    try {
      // Get current state (legacy map-based for now)
      _logger.debug('🎬 ClecoGameStateUpdater: Getting current state from StateManager', isOn: LOGGING_SWITCH);
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      _logger.debug('🎬 ClecoGameStateUpdater: Current state keys: ${currentState.keys.toList()}', isOn: LOGGING_SWITCH);
      
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
        _logger.info('🎬 ClecoGameStateUpdater: No actual changes detected, skipping update', isOn: LOGGING_SWITCH);
        return;
      }
      
      _logger.info('🎬 ClecoGameStateUpdater: Has actual changes, proceeding with state update', isOn: LOGGING_SWITCH);
      
      // Apply only the validated updates
      // Deep convert validatedUpdates to ensure all nested maps are Map<String, dynamic> (not LinkedMap from JSON decode)
      _logger.debug('🎬 ClecoGameStateUpdater: Converting validated updates to Map<String, dynamic>', isOn: LOGGING_SWITCH);
      final convertedValidatedUpdates = _deepConvertToMapStringDynamic(validatedUpdates) as Map<String, dynamic>;
      
      _logger.debug('🎬 ClecoGameStateUpdater: Merging current state with validated updates', isOn: LOGGING_SWITCH);
      final newState = {
        ...currentState,
        ...convertedValidatedUpdates,
      };
      _logger.debug('🎬 ClecoGameStateUpdater: New state keys: ${newState.keys.toList()}', isOn: LOGGING_SWITCH);
      
      // Rebuild dependent widget slices only if relevant fields changed
      _logger.debug('🎬 ClecoGameStateUpdater: Updating widget slices for changed keys: ${validatedUpdates.keys.toSet()}', isOn: LOGGING_SWITCH);
      final updatedStateWithSlices = _updateWidgetSlices(
        currentState,
        newState,
        validatedUpdates.keys.toSet(),
      );
      _logger.debug('🎬 ClecoGameStateUpdater: Widget slices updated, final state keys: ${updatedStateWithSlices.keys.toList()}', isOn: LOGGING_SWITCH);
      
      // Update StateManager
      _logger.debug('🎬 ClecoGameStateUpdater: Updating StateManager with merged state', isOn: LOGGING_SWITCH);
      _stateManager.updateModuleState('cleco_game', updatedStateWithSlices);
      _logger.info('🎬 ClecoGameStateUpdater: StateManager updated successfully', isOn: LOGGING_SWITCH);

    } catch (e) {
      _logger.error('ClecoGameStateUpdater: Failed to apply validated updates: $e', isOn: LOGGING_SWITCH);
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
    
    _logger.debug('🎬 ClecoGameStateUpdater: _updateWidgetSlices - Changed fields: $changedFields', isOn: LOGGING_SWITCH);
    
    // Only rebuild slices that depend on changed fields
    for (final entry in _widgetDependencies.entries) {
      final sliceName = entry.key;
      final dependencies = entry.value;
      
      if (changedFields.any(dependencies.contains)) {
        _logger.debug('🎬 ClecoGameStateUpdater: Recomputing slice "$sliceName" due to changed fields: ${changedFields.where(dependencies.contains).toList()}', isOn: LOGGING_SWITCH);
        
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
            _logger.info('🎬 ClecoGameStateUpdater: gameInfo slice recomputed - gamePhase: ${gameInfoSlice['gamePhase']}, currentGameId: ${gameInfoSlice['currentGameId']}', isOn: LOGGING_SWITCH);
            break;
          case 'joinedGamesSlice':
            updatedState['joinedGamesSlice'] = _computeJoinedGamesSlice(newState);
            break;
        }
      }
    }
    
    // Extract currentPlayer from current game data and put it in main state
    final currentGameId = updatedState['currentGameId']?.toString() ?? '';
    final games = updatedState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    
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
    final currentUserId = ClecoEventHandlerCallbacks.getCurrentUserId();
    
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
    final canCallCleco = state['canCallCleco'] ?? false;
    final canPlayCard = state['canPlayCard'] ?? false;
    final gamePhase = state['gamePhase'] ?? 'waiting';
    
    // Show start button if room owner and game is still in waiting phase
    final showStartButton = isRoomOwner && gamePhase == 'waiting';
    
    // Debug logging for action bar computation
    
    return {
      'showStartButton': showStartButton,
      'canPlayCard': canPlayCard && isMyTurn,
      'canCallCleco': canCallCleco && isMyTurn,
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
    final currentUserId = ClecoEventHandlerCallbacks.getCurrentUserId();
    
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
  Map<String, dynamic> _computeJoinedGamesSlice(Map<String, dynamic> state) {
    final joinedGames = state['joinedGames'] as List<dynamic>? ?? [];
    final totalJoinedGames = state['totalJoinedGames'] ?? 0;
    final joinedGamesTimestamp = state['joinedGamesTimestamp']?.toString() ?? '';
    
    return {
      'games': joinedGames,
      'totalGames': totalJoinedGames,
      'timestamp': joinedGamesTimestamp,
      'isLoadingGames': false,
    };
  }
  
}

/// Centralized game state accessor for cleco game operations
/// Provides type-safe methods to retrieve game state for specific game IDs
class ClecoGameStateAccessor {
  static ClecoGameStateAccessor? _instance;
  static ClecoGameStateAccessor get instance {
    _instance ??= ClecoGameStateAccessor._internal();
    return _instance!;
  }
  
  ClecoGameStateAccessor._internal();
  
  // Dependencies
  final StateManager _stateManager = StateManager();
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = false; // Enabled for draw card debugging
  
  /// Get the complete state for a specific game ID
  /// Returns null if the game is not found
  Map<String, dynamic>? getGameStateForId(String gameId) {
    try {
      _logger.debug('ClecoGameStateAccessor: Getting game state for ID: $gameId', isOn: LOGGING_SWITCH);
      
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final games = currentState['games'] as Map<String, dynamic>? ?? {};
      
      if (!games.containsKey(gameId)) {
        _logger.debug('ClecoGameStateAccessor: Game ID "$gameId" not found in games map', isOn: LOGGING_SWITCH);
        return null;
      }
      
      final gameState = games[gameId] as Map<String, dynamic>? ?? {};
      
      _logger.debug('ClecoGameStateAccessor: Successfully retrieved game state for ID: $gameId', isOn: LOGGING_SWITCH);
      
      return gameState;
      
    } catch (e) {
      _logger.error('ClecoGameStateAccessor: Error getting game state for ID "$gameId": $e', isOn: LOGGING_SWITCH);
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
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
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
  
  /// Check if a specific game is a cleco game
  bool isPracticeGame(String gameId) {
    final gameType = getGameType(gameId);
    return gameType == 'practice';
  }
  
  /// Check if the current active game is a cleco game
  bool isCurrentGamePractice() {
    final currentGameId = getCurrentGameId();
    if (currentGameId.isEmpty) return false;
    return isPracticeGame(currentGameId);
  }
}
