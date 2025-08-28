import '../../../core/managers/state_manager.dart';
import 'field_specifications.dart';
import '../../../tools/logging/logger.dart';

/// Validated state updater for recall game state management
/// Ensures all state updates follow consistent structure and validation rules
class RecallGameStateUpdater {
  static final Logger _log = Logger();
  static RecallGameStateUpdater? _instance;
  static RecallGameStateUpdater get instance {
    _instance ??= RecallGameStateUpdater._internal();
    return _instance!;
  }
  
  RecallGameStateUpdater._internal();
  
  // Dependencies
  final StateManager _stateManager = StateManager();
  
  /// Define the complete state schema with validation rules
  static const Map<String, RecallStateFieldSpec> _stateSchema = {
    // User Context
    'userId': RecallStateFieldSpec(
      type: String,
      required: true,
      description: 'Current user ID from authentication',
    ),
    'username': RecallStateFieldSpec(
      type: String,
      required: true,
      description: 'Current username from authentication',
    ),
    'playerId': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Player ID in current game session',
    ),
    'isRoomOwner': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether current user is the room owner',
    ),
    'isMyTurn': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether it is currently the user\'s turn',
    ),
    'canCallRecall': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether user can call recall in current game state',
    ),
    'canPlayCard': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether user can play a card in current game state',
    ),
    
    // Room Context
    'currentRoomId': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'ID of currently joined room',
    ),
    'roomName': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Name of current room',
    ),
    'permission': RecallStateFieldSpec(
      type: String,
      allowedValues: ['public', 'private'],
      defaultValue: 'public',
      description: 'Room visibility setting',
    ),
    'currentSize': RecallStateFieldSpec(
      type: int,
      min: 0,
      max: 12,
      defaultValue: 0,
      description: 'Current number of players in room',
    ),
    'maxSize': RecallStateFieldSpec(
      type: int,
      min: 2,
      max: 12,
      defaultValue: 4,
      description: 'Maximum allowed players in room',
    ),
    'minSize': RecallStateFieldSpec(
      type: int,
      min: 2,
      max: 8,
      defaultValue: 2,
      description: 'Minimum required players to start game',
    ),
    'isInRoom': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether user is currently in a room',
    ),
    
    // Game Context
    'currentGameId': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'ID of currently active game',
    ),
    'games': RecallStateFieldSpec(
      type: Map,
      defaultValue: {},
      description: 'Map of games by ID with their complete state data',
    ),
    
    // Room Lists
    'myCreatedRooms': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of rooms created by the current user',
    ),
    'currentRoom': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Current room information',
    ),
    
    // Game Tracking (Map<String, Map<String, dynamic>>)
    'activeGames': RecallStateFieldSpec(
      type: Map,
      defaultValue: {},
      description: 'Map of active games by ID with their status and metadata',
    ),
    'availableGames': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of available games that can be joined',
    ),
    
    // 🎯 NEW: Joined Games Tracking (Raw Data)
    'joinedGames': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of games the user is currently in',
    ),
    'joinedGamesSlice': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'games': [],
        'totalGames': 0,
        'timestamp': '',
        'isLoadingGames': false,
      },
      description: 'Joined games widget state slice',
    ),
    'totalJoinedGames': RecallStateFieldSpec(
      type: int,
      defaultValue: 0,
      description: 'Total number of games the user is currently in',
    ),
    'joinedGamesTimestamp': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Timestamp of last joined games update',
    ),
    
    // Widget Slices
    'actionBar': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'showStartButton': false,
        'canPlayCard': false,
        'canCallRecall': false,
        'isGameStarted': false,
      },
      description: 'Action bar widget state slice',
    ),
    'statusBar': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'currentPhase': 'waiting',
        'turnInfo': '',
        'playerCount': 0,
        'gameStatus': 'inactive',
        'turnNumber': 0,
        'roundNumber': 1,
      },
      description: 'Status bar widget state slice',
    ),
    'myHand': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'cards': [],
        'selectedIndex': -1,
        'selectedCard': null,
      },
      description: 'My hand widget state slice',
    ),
    'centerBoard': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'drawPileCount': 0,
        'topDiscard': null,
        'canDrawFromDeck': false,
        'canTakeFromDiscard': false,
      },
      description: 'Center board widget state slice',
    ),
    'opponentsPanel': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'opponents': [],
        'currentTurnIndex': -1,
      },
      description: 'Opponents panel widget state slice',
    ),
    'gameInfo': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'currentGameId': '',
        'roomName': '',
        'currentSize': 0,
        'maxSize': 4,
        'gamePhase': 'waiting',
        'gameStatus': 'inactive',
        'isRoomOwner': false,
        'isInGame': false,
      },
      description: 'Game info widget state slice',
    ),
    'gameState': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Full game state object',
    ),
    'drawPileCount': RecallStateFieldSpec(
      type: int,
      defaultValue: 0,
      description: 'Number of cards in draw pile',
    ),
    'discardPile': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'Cards in discard pile',
    ),
    'opponentPlayers': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of opponent players',
    ),
    'currentPlayerIndex': RecallStateFieldSpec(
      type: int,
      defaultValue: -1,
      description: 'Index of current player',
    ),
    'currentGameData': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Current game data object',
    ),
    'myScore': RecallStateFieldSpec(
      type: int,
      defaultValue: 0,
      description: 'Current player\'s total score',
    ),
    
    // Message State
    'messages': RecallStateFieldSpec(
      type: Map,
      defaultValue: {
        'session': [],
        'rooms': {},
      },
      description: 'Message boards for session and rooms',
    ),
    
    // UI State
    'selectedCard': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Currently selected card in hand',
    ),
    'selectedCardIndex': RecallStateFieldSpec(
      type: int,
      required: false,
      description: 'Index of currently selected card in hand',
    ),
    
    // Connection State
    'isConnected': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether WebSocket is connected',
    ),
    'isLoading': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether a loading operation is in progress',
    ),
    'lastError': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Last error message, if any',
    ),
    'lastUpdated': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Timestamp of last state update',
    ),
  };
  
  /// Widget slice dependencies - only rebuild when these fields change
  static const Map<String, Set<String>> _widgetDependencies = {
    'actionBar': {'currentGameId', 'games'},
    'statusBar': {'currentGameId', 'games'},
    'myHand': {'currentGameId', 'games'},
    'centerBoard': {'currentGameId', 'games'},
    'opponentsPanel': {'currentGameId', 'games'},
    'gameInfo': {'currentGameId', 'games'},
    'joinedGamesSlice': {'joinedGames', 'totalJoinedGames', 'joinedGamesTimestamp'},
  };
  
  /// Update state with validation
  void updateState(Map<String, dynamic> updates) {
    _log.info('🎯 [RecallStateUpdater] ===== UPDATING RECALL GAME STATE =====');
    _log.info('🎯 [RecallStateUpdater] Input updates: $updates');
    _log.info('🎯 [RecallStateUpdater] Update keys: ${updates.keys.toList()}');
    _log.info('🎯 [RecallStateUpdater] Update count: ${updates.length} fields');
    
    try {
      // 🎯 Validate each field before updating
      _log.info('🔍 [RecallStateUpdater] Starting field validation...');
      final validatedUpdates = _validateAndParseStateUpdates(updates);
      _log.info('✅ [RecallStateUpdater] Field validation completed');
      _log.info('🔍 [RecallStateUpdater] Validated updates: $validatedUpdates');
      
      // Get current state
      _log.info('🔍 [RecallStateUpdater] Getting current state...');
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      _log.info('🔍 [RecallStateUpdater] Current state keys: ${currentState.keys.toList()}');
      
      // Apply only the validated updates
      final newState = {
        ...currentState,
        ...validatedUpdates,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      _log.info('🔍 [RecallStateUpdater] New state created with timestamp');
      _log.info('🔍 [RecallStateUpdater] New state keys: ${newState.keys.toList()}');
      
      // Rebuild dependent widget slices only if relevant fields changed
      _log.info('🔍 [RecallStateUpdater] Updating widget slices...');
      final updatedStateWithSlices = _updateWidgetSlices(
        currentState,
        newState,
        validatedUpdates.keys.toSet(),
      );
      _log.info('✅ [RecallStateUpdater] Widget slices updated');
      
      // Update StateManager
      _log.info('🔍 [RecallStateUpdater] Calling StateManager.updateModuleState...');
      _stateManager.updateModuleState('recall_game', updatedStateWithSlices);
      _log.info('✅ [RecallStateUpdater] StateManager updated successfully');
      
      // Log successful update
      _logStateUpdate(validatedUpdates);
      _log.info('🎯 [RecallStateUpdater] ===== END STATE UPDATE (SUCCESS) =====');
      
    } catch (e) {
      // Log validation errors
      _logStateError(updates, e);
      _log.error('❌ [RecallStateUpdater] State update failed: $e');
      _log.error('❌ [RecallStateUpdater] Error type: ${e.runtimeType}');
      _log.error('❌ [RecallStateUpdater] Stack trace: ${StackTrace.current}');
      _log.info('🎯 [RecallStateUpdater] ===== END STATE UPDATE (ERROR) =====');
      rethrow;
    }
  }
  
  /// Validate and parse state updates
  Map<String, dynamic> _validateAndParseStateUpdates(Map<String, dynamic> updates) {
    _log.info('🔍 [VALIDATION] ===== VALIDATING STATE UPDATES =====');
    _log.info('🔍 [VALIDATION] Input updates: $updates');
    _log.info('🔍 [VALIDATION] Available schema fields: ${_stateSchema.keys.toList()}');
    
    final validatedUpdates = <String, dynamic>{};
    final validFields = <String>[];
    final invalidFields = <String>[];
    
    for (final entry in updates.entries) {
      final key = entry.key;
      final value = entry.value;
      
      _log.info('🔍 [VALIDATION] Processing field: $key = $value');
      _log.info('🔍 [VALIDATION] Field type: ${value.runtimeType}');
      
      // 🚨 Check if field exists in schema
      final fieldSpec = _stateSchema[key];
      if (fieldSpec == null) {
        final error = 'Unknown state field: "$key". Allowed fields: ${_stateSchema.keys.join(', ')}';
        _log.error('❌ [VALIDATION] $error');
        invalidFields.add(key);
        throw RecallStateException(error, fieldName: key);
      }
      
      _log.info('✅ [VALIDATION] Field exists in schema: $key');
      _log.info('🔍 [VALIDATION] Field spec: type=${fieldSpec.type}, required=${fieldSpec.required}, description=${fieldSpec.description}');
      
      // 🚨 Validate field value
      try {
        final validatedValue = _validateStateFieldValue(key, value, fieldSpec);
        validatedUpdates[key] = validatedValue;
        validFields.add(key);
        _log.info('✅ [VALIDATION] Field validation passed: $key = $validatedValue');
      } catch (e) {
        _log.error('❌ [VALIDATION] Field validation failed: $key - $e');
        invalidFields.add(key);
        rethrow;
      }
    }
    
    _log.info('🔍 [VALIDATION] Validation summary:');
    _log.info('🔍 [VALIDATION] Valid fields: $validFields');
    _log.info('🔍 [VALIDATION] Invalid fields: $invalidFields');
    _log.info('🔍 [VALIDATION] Valid field count: ${validFields.length}/${updates.length}');
    _log.info('🔍 [VALIDATION] Final validated updates: $validatedUpdates');
    _log.info('🔍 [VALIDATION] ===== END VALIDATION =====');
    
    return validatedUpdates;
  }
  
  /// Validate individual state field value
  dynamic _validateStateFieldValue(String key, dynamic value, RecallStateFieldSpec spec) {
    // Handle null values
    if (value == null) {
      if (spec.required) {
        throw RecallStateException(
          'Field "$key" is required and cannot be null',
          fieldName: key,
        );
      }
      return spec.defaultValue;
    }
    
    // Type validation
    if (!ValidationUtils.isValidType(value, spec.type)) {
      throw RecallStateException(
        'Field "$key" must be of type ${spec.type}, got ${value.runtimeType}',
        fieldName: key,
      );
    }
    
    // Allowed values validation
    if (spec.allowedValues != null && !ValidationUtils.isAllowedValue(value, spec.allowedValues!)) {
      throw RecallStateException(
        'Field "$key" value "$value" is not allowed. '
        'Allowed values: ${spec.allowedValues!.join(', ')}',
        fieldName: key,
      );
    }
    
    // Range validation for numbers
    if (value is int) {
      if (!ValidationUtils.isValidRange(value, min: spec.min, max: spec.max)) {
        final rangeDesc = [
          if (spec.min != null) 'min: ${spec.min}',
          if (spec.max != null) 'max: ${spec.max}',
        ].join(', ');
        throw RecallStateException(
          'Field "$key" value $value is out of range ($rangeDesc)',
          fieldName: key,
        );
      }
    }
    
    return value;
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
    _log.info('🎯 [ActionBar] Computing slice:');
    _log.info('  - isRoomOwner: $isRoomOwner');
    _log.info('  - isGameActive: $isGameActive');
    _log.info('  - gamePhase: $gamePhase');
    _log.info('  - showStartButton: $showStartButton (${isRoomOwner} && ${gamePhase} == waiting)');
    
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
    final currentGameId = state['currentGameId']?.toString() ?? '';
    final games = state['games'] as Map<String, dynamic>? ?? {};
    
    // If no current game or game not found in games map
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      return {
        'drawPileCount': 0,
        'topDiscard': null,
        'canDrawFromDeck': false,
        'canTakeFromDiscard': false,
      };
    }
    
    // Get current game data from games map
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final drawPileCount = currentGame['drawPileCount'] ?? 0;
    final discardPile = currentGame['discardPile'] as List<dynamic>? ?? [];
    
    return {
      'drawPileCount': drawPileCount,
      'topDiscard': discardPile.isNotEmpty ? discardPile.last : null,
      'canDrawFromDeck': drawPileCount > 0,
      'canTakeFromDiscard': discardPile.isNotEmpty,
    };
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
    final opponentPlayers = currentGame['opponentPlayers'] as List<dynamic>? ?? [];
    final currentPlayerIndex = currentGame['currentPlayerIndex'] ?? -1;
    
    return {
      'opponents': opponentPlayers,
      'currentTurnIndex': currentPlayerIndex,
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
        'roomName': '',
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
    
    // Extract game information from the single source of truth (gameData)
    final roomName = gameState['gameName']?.toString() ?? 'Game $currentGameId';
    
    // Read player count and max players from the actual game data (single source of truth)
    final currentSize = gameState['playerCount'] ?? 0;
    final maxSize = gameState['maxPlayers'] ?? 4;  // This comes from the backend game_state data
    
    // Debug logging to see what's in gameState
    _log.info('🎮 [GameInfoSlice] gameState keys: ${gameState.keys.toList()}');
    _log.info('🎮 [GameInfoSlice] playerCount: $currentSize, maxPlayers: ${gameState['maxPlayers']}');
    
    // Use derived values for other fields (these are set during navigation)
    final gamePhase = currentGame['gamePhase']?.toString() ?? 'waiting';
    final gameStatus = currentGame['gameStatus']?.toString() ?? 'inactive';
    final isRoomOwner = currentGame['isRoomOwner'] ?? false;
    final isInGame = currentGame['isInGame'] ?? false;
    
    return {
      'currentGameId': currentGameId,
      'roomName': roomName,
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
  
  /// Log successful state update
  void _logStateUpdate(Map<String, dynamic> updates) {
    _log.info('🎯 [RecallStateUpdater] Updated ${updates.length} fields: ${updates.keys.join(', ')}');
  }
  
  /// Log validation errors
  void _logStateError(Map<String, dynamic> originalUpdates, dynamic error) {
    _log.error('❌ [RecallStateUpdater] Validation failed:');
    _log.error('   Error: $error');
    _log.error('   Attempted fields: ${originalUpdates.keys.join(', ')}');
  }
}
