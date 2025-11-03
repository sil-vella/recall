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
  
  RecallGameStateUpdater._internal() {
    // Initialize state queue validator with logger callback
    final validator = StateQueueValidator.instance;
    validator.setLogCallback((String message, {bool isError = false}) {
      if (isError) {
        _logger.error(message, isOn: LOGGING_SWITCH);
      } else {
        _logger.debug(message, isOn: LOGGING_SWITCH);
      }
    });
    
    // Set update handler to apply validated updates
    validator.setUpdateHandler((Map<String, dynamic> validatedUpdates) {
      _applyValidatedUpdates(validatedUpdates);
    });
  }
  
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = true;
  // Dependencies
  final StateManager _stateManager = StateManager();
  final StateQueueValidator _validator = StateQueueValidator.instance;
  
  // Note: State schema validation has been moved to StateQueueValidator
  // See state_queue_validator.dart for the complete schema
  
  /// Widget slice dependencies - only rebuild when these fields change
  static const Map<String, Set<String>> _widgetDependencies = {
    'actionBar': {'currentGameId', 'games', 'isRoomOwner', 'isGameActive', 'isMyTurn'},
    'statusBar': {'currentGameId', 'games', 'gamePhase', 'isGameActive', 'playerStatus'},
    'myHand': {'currentGameId', 'games', 'isMyTurn', 'playerStatus'},
    'centerBoard': {'currentGameId', 'games', 'gamePhase', 'isGameActive', 'discardPile'},
    'opponentsPanel': {'currentGameId', 'games', 'currentPlayer', 'currentPlayerStatus'},
    'gameInfo': {'currentGameId', 'games', 'gamePhase', 'isGameActive'},
    'joinedGamesSlice': {'joinedGames', 'totalJoinedGames', 'joinedGamesTimestamp'},
  };
  
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
  
  /// Apply validated updates with widget slice computation
  /// This is called by StateQueueValidator after validation
  void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
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
        return;
      }
      
      // Apply only the validated updates (no timestamp - causes unnecessary updates)
      final newState = {
        ...currentState,
        ...validatedUpdates,
      };
      
      // Rebuild dependent widget slices only if relevant fields changed
      final updatedStateWithSlices = _updateWidgetSlices(
        currentState,
        newState,
        validatedUpdates.keys.toSet(),
      );
      
      // Update StateManager
      _stateManager.updateModuleState('recall_game', updatedStateWithSlices);
      
    } catch (e) {
      _logger.error('RecallGameStateUpdater: Failed to apply validated updates: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }
  
  /// Update widget slices based on dependency tracking
  Map<String, dynamic> _updateWidgetSlices(
    Map<String, dynamic> oldState,
    Map<String, dynamic> newState,
    Set<String> changedFields,
  ) {
    final updatedState = Map<String, dynamic>.from(newState);
    
    // Only rebuild slices that depend on changed fields
    for (final entry in _widgetDependencies.entries) {
      final sliceName = entry.key;
      final dependencies = entry.value;
      
      if (changedFields.any(dependencies.contains)) {
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
            updatedState['gameInfo'] = _computeGameInfoSlice(newState);
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
  
  /// Compute action bar widget slice
  Map<String, dynamic> _computeActionBarSlice(Map<String, dynamic> state) {
    final isRoomOwner = state['isRoomOwner'] ?? false;
    final isGameActive = state['isGameActive'] ?? false;
    final isMyTurn = state['isMyTurn'] ?? false;
    final canCallRecall = state['canCallRecall'] ?? false;
    final canPlayCard = state['canPlayCard'] ?? false;
    final gamePhase = state['gamePhase'] ?? 'waiting';
    
    // Show start button if room owner and game is still in waiting phase
    final showStartButton = isRoomOwner && gamePhase == 'waiting';
    
    // Debug logging for action bar computation
    
    return {
      'showStartButton': showStartButton,
      'canPlayCard': canPlayCard && isMyTurn,
      'canCallRecall': canCallRecall && isMyTurn,
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
      };
    }
    
    // Get current game data from games map
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final isMyTurn = currentGame['isMyTurn'] ?? false;
    final canPlayCard = currentGame['canPlayCard'] ?? false;
    
    return {
      'cards': currentGame['myHandCards'] ?? [],
      'selectedIndex': currentGame['selectedCardIndex'] ?? -1,
      'canSelectCards': isMyTurn && canPlayCard,
    };
  }
  
  /// Compute center board widget slice
  Map<String, dynamic> _computeCenterBoardSlice(Map<String, dynamic> state) {
    print('🔍 DEBUG: _computeCenterBoardSlice CALLED');
    final currentGameId = state['currentGameId']?.toString() ?? '';
    print('🔍 DEBUG: _computeCenterBoardSlice - currentGameId: $currentGameId');
    final games = state['games'] as Map<String, dynamic>? ?? {};
    print('🔍 DEBUG: _computeCenterBoardSlice - games keys: ${games.keys.toList()}');
    
    // If no current game or game not found in games map
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      print('🔍 DEBUG: _computeCenterBoardSlice - No current game found, returning empty slice');
      return {
        'drawPileCount': 0,
        'topDiscard': null,
        'canDrawFromDeck': false,
        'canTakeFromDiscard': false,
      };
    }
    
    // Get current game data from games map
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    print('🔍 DEBUG: _computeCenterBoardSlice - gameState keys: ${gameState.keys.toList()}');
    
    // Get pile information from game state
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final drawPileCount = drawPile.length;
    
    print('🔍 DEBUG: _computeCenterBoardSlice - drawPile length: $drawPileCount');
    print('🔍 DEBUG: _computeCenterBoardSlice - discardPile length: ${discardPile.length}');
    
    // Debug: Log discard pile contents when computing centerBoard slice
    if (discardPile.isNotEmpty) {
      print('🔍 DEBUG: _computeCenterBoardSlice - discardPile has ${discardPile.length} cards');
      print('🔍 DEBUG: _computeCenterBoardSlice - topDiscard will be: ${discardPile.last}');
      print('🔍 DEBUG: _computeCenterBoardSlice - topDiscard cardId: ${discardPile.last['cardId']}');
      print('🔍 DEBUG: _computeCenterBoardSlice - topDiscard rank: ${discardPile.last['rank']}');
      print('🔍 DEBUG: _computeCenterBoardSlice - topDiscard suit: ${discardPile.last['suit']}');
    } else {
      print('🔍 DEBUG: _computeCenterBoardSlice - discardPile is empty');
    }
    
    final result = {
      'drawPileCount': drawPileCount,
      'topDiscard': discardPile.isNotEmpty ? discardPile.last : null,
      'canDrawFromDeck': drawPileCount > 0,
      'canTakeFromDiscard': discardPile.isNotEmpty,
    };
    
    print('🔍 DEBUG: _computeCenterBoardSlice - Returning result with topDiscard: ${result['topDiscard'] != null ? 'NOT NULL' : 'NULL'}');
    
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
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    // Filter out current player from opponents list
    final opponents = allPlayers.where((player) => 
      player['id']?.toString() != currentUserId
    ).toList();
    
    // Find current player index in the opponents list
    final currentPlayer = gameState['currentPlayer'];
    int currentTurnIndex = -1;
    if (currentPlayer != null) {
      final currentPlayerId = currentPlayer['id']?.toString() ?? '';
      currentTurnIndex = opponents.indexWhere((player) => 
        player['id']?.toString() == currentPlayerId
      );
    }
    
    // Debug logging for opponents panel computation
    print('🔍 OPPONENTS PANEL DEBUG:');
    print('  currentGameId: $currentGameId');
    print('  currentUserId: $currentUserId');
    print('  allPlayers: ${allPlayers.map((p) => '${p['name']} (${p['id']}, status: ${p['status']})').join(', ')}');
    print('  opponents: ${opponents.map((p) => '${p['name']} (${p['id']}, status: ${p['status']})').join(', ')}');
    print('  currentPlayer: ${currentPlayer?['name']} (${currentPlayer?['id']})');
    print('  currentTurnIndex: $currentTurnIndex');
    
    return {
      'opponents': opponents,
      'currentTurnIndex': currentTurnIndex,
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
      final gameState = getGameStateDataForId(gameId);
      if (gameState == null) return 'normal';
      
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
