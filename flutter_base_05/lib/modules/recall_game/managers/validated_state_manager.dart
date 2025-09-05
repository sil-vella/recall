import '../../../core/managers/state_manager.dart';
import '../utils/field_specifications.dart';
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
    'turnTimeout': RecallStateFieldSpec(
      type: int,
      defaultValue: 30,
      description: 'Turn timeout duration in seconds',
    ),
    'turnStartTime': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'ISO timestamp when the current turn started',
    ),
    'playerStatus': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Current player status (waiting, ready, playing, drawing_card, etc.)',
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
    'myDrawnCard': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Most recently drawn card for current player',
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
    
    // Game State Fields
    'isGameActive': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether a game is currently active',
    ),
    'playerCount': RecallStateFieldSpec(
      type: int,
      defaultValue: 0,
      description: 'Number of players in current game',
    ),
    'roundNumber': RecallStateFieldSpec(
      type: int,
      defaultValue: 1,
      description: 'Current round number in the game',
    ),
    'currentPlayer': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Current player object with id, name, etc.',
    ),
    'currentPlayerStatus': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Status of current player',
    ),
    'roundStatus': RecallStateFieldSpec(
      type: String,
      required: false,
      description: 'Status of current round',
    ),
    
    // Game Phase Field - Add this missing field
    'gamePhase': RecallStateFieldSpec(
      type: String,
      defaultValue: 'waiting',
      description: 'Current game phase (waiting, playing, finished, etc.)',
    ),
    
    // Game Status Field - Add this missing field
    'gameStatus': RecallStateFieldSpec(
      type: String,
      defaultValue: 'inactive',
      description: 'Current game status (inactive, active, finished, etc.)',
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
      _log.info('🔍 [STATE] Extracted currentPlayer from current game: ${currentPlayer['id']}');
    } else {
      updatedState['currentPlayer'] = null;
      _log.info('🔍 [STATE] No currentPlayer in current game');
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
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final allPlayers = gameState['players'] as List<dynamic>? ?? [];
    
    // Get current user ID (the person using this app instance)
    // Access login state from global state manager since it's in a different module
    final globalState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = globalState['userId']?.toString() ?? '';
    
    // Get current player ID (whose turn it is - could be current user or any opponent)
    // Get currentPlayer from the root state (most up-to-date), fallback to game state
    final currentPlayer = state['currentPlayer'] as Map<String, dynamic>? ?? 
                         gameState['currentPlayer'] as Map<String, dynamic>?;
    final currentPlayerId = currentPlayer?['id']?.toString() ?? '';
    
    _log.info('🔍 [OPPONENTS_PANEL] currentUserId: $currentUserId');
    _log.info('🔍 [OPPONENTS_PANEL] currentPlayer: $currentPlayer');
    _log.info('🔍 [OPPONENTS_PANEL] currentPlayerId: $currentPlayerId');
    _log.info('🔍 [OPPONENTS_PANEL] allPlayers count: ${allPlayers.length}');
    
    // Filter out current user to get opponents only (everyone except the current user)
    final opponents = allPlayers.where((player) {
      final playerData = player as Map<String, dynamic>? ?? {};
      final playerId = playerData['id']?.toString() ?? '';
      final isNotCurrentUser = playerId != currentUserId;
      _log.info('🔍 [OPPONENTS_PANEL] Checking player: $playerId vs currentUserId: $currentUserId -> isNotCurrentUser: $isNotCurrentUser');
      return isNotCurrentUser;
    }).toList();
    
    _log.info('🔍 [OPPONENTS_PANEL] opponents count after filtering: ${opponents.length}');
    
    // Find which opponent is the current player (whose turn it is)
    int currentTurnIndex = -1;
    for (int i = 0; i < opponents.length; i++) {
      final opponent = opponents[i] as Map<String, dynamic>? ?? {};
      if (opponent['id']?.toString() == currentPlayerId) {
        currentTurnIndex = i;
        break;
      }
    }
    
    _log.info('🔍 [OPPONENTS_PANEL] currentTurnIndex: $currentTurnIndex');
    
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
    
    // Use derived values for other fields (these are set during navigation)
    final gamePhase = currentGame['gamePhase']?.toString() ?? 'waiting';
    final gameStatus = currentGame['gameStatus']?.toString() ?? 'inactive';
    final isRoomOwner = currentGame['isRoomOwner'] ?? false;
    final isInGame = currentGame['isInGame'] ?? false;
    
    // Read player count and max players from the actual game data (single source of truth)
    final currentSize = gameState['playerCount'] ?? 0;
    final maxSize = gameState['maxPlayers'] ?? 4;
    
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

/// Centralized game state accessor for recall game operations
/// Provides type-safe methods to retrieve game state for specific game IDs
class RecallGameStateAccessor {
  static final Logger _log = Logger();
  static RecallGameStateAccessor? _instance;
  static RecallGameStateAccessor get instance {
    _instance ??= RecallGameStateAccessor._internal();
    return _instance!;
  }
  
  RecallGameStateAccessor._internal();
  
  // Dependencies
  final StateManager _stateManager = StateManager();
  
  /// Get the complete state for a specific game ID
  /// Returns null if the game is not found
  Map<String, dynamic>? getGameStateForId(String gameId) {
    try {
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final games = currentState['games'] as Map<String, dynamic>? ?? {};
      
      if (!games.containsKey(gameId)) {
        _log.debug('🔍 Game $gameId not found in games map');
        return null;
      }
      
      final gameState = games[gameId] as Map<String, dynamic>? ?? {};
      _log.debug('🔍 Retrieved game state for game $gameId');
      return gameState;
      
    } catch (e) {
      _log.error('❌ Error retrieving game state for game $gameId: $e');
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
      _log.debug('🔍 Retrieved game data for game $gameId');
      return gameData;
      
    } catch (e) {
      _log.error('❌ Error retrieving game data for game $gameId: $e');
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
      _log.debug('🔍 Retrieved game state data for game $gameId');
      return gameState;
      
    } catch (e) {
      _log.error('❌ Error retrieving game state data for game $gameId: $e');
      return null;
    }
  }
  
  /// Get the current active game ID
  String getCurrentGameId() {
    try {
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      _log.debug('🔍 Current game ID: $currentGameId');
      return currentGameId;
      
    } catch (e) {
      _log.error('❌ Error retrieving current game ID: $e');
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
      _log.debug('🔍 Game $gameId type: $gameType');
      return gameType;
      
    } catch (e) {
      _log.error('❌ Error retrieving game type for game $gameId: $e');
      return 'normal';
    }
  }
  
  /// Check if a specific game is a practice game
  bool isPracticeGame(String gameId) {
    final gameType = getGameType(gameId);
    return gameType == 'practice';
  }
  
  /// Check if the current active game is a practice game
  bool isCurrentGamePractice() {
    final currentGameId = getCurrentGameId();
    if (currentGameId.isEmpty) return false;
    return isPracticeGame(currentGameId);
  }
}
