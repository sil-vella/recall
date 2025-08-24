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
    'gamePhase': RecallStateFieldSpec(
      type: String,
      allowedValues: ['waiting', 'playing', 'finished'],
      defaultValue: 'waiting',
      description: 'Current phase of the game',
    ),
    'gameStatus': RecallStateFieldSpec(
      type: String,
      allowedValues: ['inactive', 'active', 'paused', 'ended'],
      defaultValue: 'inactive',
      description: 'Current status of the game',
    ),
    'isGameActive': RecallStateFieldSpec(
      type: bool,
      defaultValue: false,
      description: 'Whether game is currently active',
    ),
    'turnNumber': RecallStateFieldSpec(
      type: int,
      min: 0,
      defaultValue: 0,
      description: 'Current turn number in the game',
    ),
    'roundNumber': RecallStateFieldSpec(
      type: int,
      min: 0,
      defaultValue: 0,
      description: 'Current round number in the game',
    ),
    'playerCount': RecallStateFieldSpec(
      type: int,
      min: 0,
      max: 8,
      defaultValue: 0,
      description: 'Number of players in current game',
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
    'gameState': RecallStateFieldSpec(
      type: Map,
      required: false,
      description: 'Full game state object',
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
    'actionBar': {'isRoomOwner', 'isGameActive', 'isMyTurn', 'canCallRecall', 'canPlayCard'},
    'statusBar': {'gamePhase', 'gameStatus', 'playerCount', 'turnNumber', 'roundNumber', 'isConnected'},
    'myHand': {'playerId', 'isMyTurn', 'canPlayCard'},
    'centerBoard': {'gamePhase', 'isGameActive', 'turnNumber'},
    'opponentsPanel': {'playerCount', 'isMyTurn', 'gamePhase'},
  };
  
  /// Update state with validation
  void updateState(Map<String, dynamic> updates) {
    try {
      // 🎯 Validate each field before updating
      final validatedUpdates = _validateAndParseStateUpdates(updates);
      
      // Get current state
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      
      // Apply only the validated updates
      final newState = {
        ...currentState,
        ...validatedUpdates,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      // Rebuild dependent widget slices only if relevant fields changed
      final updatedStateWithSlices = _updateWidgetSlices(
        currentState,
        newState,
        validatedUpdates.keys.toSet(),
      );
      
      // Update StateManager
      _stateManager.updateModuleState('recall_game', updatedStateWithSlices);
      
      // Log successful update
      _logStateUpdate(validatedUpdates);
      
    } catch (e) {
      // Log validation errors
      _logStateError(updates, e);
      rethrow;
    }
  }
  
  /// Validate and parse state updates
  Map<String, dynamic> _validateAndParseStateUpdates(Map<String, dynamic> updates) {
    final validatedUpdates = <String, dynamic>{};
    
    for (final entry in updates.entries) {
      final key = entry.key;
      final value = entry.value;
      
      // 🚨 Check if field exists in schema
      final fieldSpec = _stateSchema[key];
      if (fieldSpec == null) {
        throw RecallStateException(
          'Unknown state field: "$key". '
          'Allowed fields: ${_stateSchema.keys.join(', ')}',
          fieldName: key,
        );
      }
      
      // 🚨 Validate field value
      final validatedValue = _validateStateFieldValue(key, value, fieldSpec);
      validatedUpdates[key] = validatedValue;
    }
    
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
    final isMyTurn = state['isMyTurn'] ?? false;
    final canPlayCard = state['canPlayCard'] ?? false;
    
    return {
      'cards': state['myHandCards'] ?? [],
      'selectedIndex': state['selectedCardIndex'],
      'canSelectCards': isMyTurn && canPlayCard,
    };
  }
  
  /// Compute center board widget slice
  Map<String, dynamic> _computeCenterBoardSlice(Map<String, dynamic> state) {
    final gamePhase = state['gamePhase'] ?? 'waiting';
    final isGameActive = state['isGameActive'] ?? false;
    
    return {
      'discardPile': state['discardPile'] ?? [],
      'drawPileCount': state['drawPileCount'] ?? 0,
      'lastPlayedCard': state['lastPlayedCard'],
      'showCards': isGameActive && gamePhase == 'playing',
    };
  }
  
  /// Compute opponents panel widget slice
  Map<String, dynamic> _computeOpponentsPanelSlice(Map<String, dynamic> state) {
    final playerCount = state['playerCount'] ?? 0;
    final gamePhase = state['gamePhase'] ?? 'waiting';
    
    return {
      'players': state['opponentPlayers'] ?? [],
      'currentPlayerIndex': state['currentPlayerIndex'] ?? -1,
      'showPlayerInfo': playerCount > 1,
      'gamePhase': gamePhase,
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
