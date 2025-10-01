/// Practice Game Coordinator for Recall Game
///
/// This class provides a simplified game coordinator for practice sessions,
/// allowing players to learn the game mechanics without full WebSocket integration.

import 'package:recall/tools/logging/logger.dart';
import '../../../core/managers/state_manager.dart';
import '../utils/field_specifications.dart';
import 'models/player.dart';
import 'models/card.dart';
import 'utils/deck_factory.dart';

const bool LOGGING_SWITCH = true;

class PracticeGameCoordinator {
  /// Coordinates practice game sessions for the Recall game
  
  late final dynamic gameStateManager;
  final StateManager _stateManager = StateManager();
  List<String> registeredEvents = [];
  String? _currentPracticeGameId;
  List<Player> _aiPlayers = [];
  
  /// Practice game state schema for validation
  static const Map<String, RecallStateFieldSpec> _practiceStateSchema = {
    // Practice Game Context
    'gameId': RecallStateFieldSpec(
      type: String,
      required: true,
      description: 'Practice game ID',
    ),
    'gameType': RecallStateFieldSpec(
      type: String,
      required: true,
      allowedValues: ['practice'],
      description: 'Game type (always practice for practice games)',
    ),
    'phase': RecallStateFieldSpec(
      type: String,
      required: true,
      allowedValues: ['waiting', 'playing', 'ended'],
      description: 'Current practice game phase',
    ),
    'gamePhase': RecallStateFieldSpec(
      type: String,
      required: true,
      allowedValues: ['waiting', 'playing', 'ended'],
      description: 'Current practice game phase (UI display)',
    ),
    'isGameActive': RecallStateFieldSpec(
      type: bool,
      required: true,
      description: 'Whether practice game is currently active',
    ),
    'isPracticeMode': RecallStateFieldSpec(
      type: bool,
      required: true,
      defaultValue: true,
      description: 'Whether this is a practice mode game',
    ),
    'currentPlayer': RecallStateFieldSpec(
      type: Map,
      required: false,
      nullable: true,
      description: 'Current player object',
    ),
    'players': RecallStateFieldSpec(
      type: List,
      defaultValue: [],
      description: 'List of players in practice game',
    ),
    
    // Practice Game Data Structure
    'gameData': RecallStateFieldSpec(
      type: Map,
      required: true,
      description: 'Complete practice game data structure',
    ),
    
    // Practice Game State (nested in gameData)
    'game_state': RecallStateFieldSpec(
      type: Map,
      required: true,
      description: 'Practice game state data',
    ),
    
    // Room Information
    'room_info': RecallStateFieldSpec(
      type: Map,
      required: true,
      description: 'Practice room configuration',
    ),
    
    // Session Information
    'session_info': RecallStateFieldSpec(
      type: Map,
      required: true,
      description: 'Practice session metadata',
    ),
    
    // Timestamps
    'lastUpdated': RecallStateFieldSpec(
      type: String,
      required: true,
      description: 'Last update timestamp',
    ),
  };
  
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
  
  /// Get practice game state schema for debugging
  Map<String, RecallStateFieldSpec> getPracticeStateSchema() {
    return Map.from(_practiceStateSchema);
  }
  
  /// Validate a practice game state against schema (public method)
  Map<String, dynamic> validatePracticeState(Map<String, dynamic> state) {
    return _validatePracticeGameState(state);
  }
  
  /// Create AI players for practice game
  List<Player> createAIPlayers(int numberOfOpponents, String difficultyLevel) {
    try {
      Logger().info('Practice: Creating $numberOfOpponents AI players with difficulty: $difficultyLevel', isOn: LOGGING_SWITCH);
      
      final aiPlayers = <Player>[];
      final aiNames = _generateAINames(numberOfOpponents);
      
      for (int i = 0; i < numberOfOpponents; i++) {
        final playerId = 'ai_player_${i + 1}_${DateTime.now().millisecondsSinceEpoch}';
        final playerName = aiNames[i];
        
        final aiPlayer = ComputerPlayer(
          playerId: playerId,
          name: playerName,
          difficulty: difficultyLevel,
        );
        
        // Initialize AI player with 4 face-down cards
        aiPlayer.hand = List<Card?>.filled(4, null);
        aiPlayer.cardsRemaining = 4;
        aiPlayer.status = PlayerStatus.waiting;
        
        aiPlayers.add(aiPlayer);
        
        Logger().info('Practice: Created AI player "$playerName" (ID: $playerId)', isOn: LOGGING_SWITCH);
      }
      
      _aiPlayers = aiPlayers;
      Logger().info('Practice: Successfully created ${aiPlayers.length} AI players', isOn: LOGGING_SWITCH);
      
      return aiPlayers;
      
    } catch (e) {
      Logger().error('Practice: Failed to create AI players: $e', isOn: LOGGING_SWITCH);
      return [];
    }
  }
  
  /// Generate AI player names
  List<String> _generateAINames(int count) {
    final aiNames = [
      'Alex', 'Blake', 'Casey', 'Drew', 'Emery', 'Finley', 'Gray', 'Hayden',
      'Iris', 'Jordan', 'Kai', 'Lane', 'Morgan', 'Nova', 'Onyx', 'Parker',
      'Quinn', 'Riley', 'Sage', 'Taylor', 'Uma', 'Vale', 'Wren', 'Xara',
      'Yara', 'Zion'
    ];
    
    // Shuffle and take the requested number
    final shuffled = List<String>.from(aiNames)..shuffle();
    return shuffled.take(count).toList();
  }
  
  
  /// Convert player to Flutter format
  Map<String, dynamic> _convertPlayerToFlutter(Player player) {
    // Convert PlayerStatus enum to proper string format
    String statusString;
    switch (player.status) {
      case PlayerStatus.waiting:
        statusString = 'waiting';
        break;
      case PlayerStatus.ready:
        statusString = 'ready';
        break;
      case PlayerStatus.playing:
        statusString = 'playing';
        break;
      case PlayerStatus.sameRankWindow:
        statusString = 'same_rank_window';
        break;
      case PlayerStatus.playingCard:
        statusString = 'playing_card';
        break;
      case PlayerStatus.drawingCard:
        statusString = 'drawing_card';
        break;
      case PlayerStatus.queenPeek:
        statusString = 'queen_peek';
        break;
      case PlayerStatus.jackSwap:
        statusString = 'jack_swap';
        break;
      case PlayerStatus.peeking:
        statusString = 'peeking';
        break;
      case PlayerStatus.initialPeek:
        statusString = 'initial_peek';
        break;
      case PlayerStatus.finished:
        statusString = 'finished';
        break;
      case PlayerStatus.disconnected:
        statusString = 'disconnected';
        break;
      case PlayerStatus.winner:
        statusString = 'winner';
        break;
    }
    
    Logger().info('Practice: Converting player ${player.name} (${player.playerId}) - Status: ${player.status} -> $statusString', isOn: LOGGING_SWITCH);
    
    return {
      'id': player.playerId,
      'name': player.name,
      'type': player.playerType.name.toLowerCase(),
      'hand': player.hand.map((card) => card != null ? _convertCardToFlutter(card) : null).toList(),
      'visibleCards': player.visibleCards.map((card) => _convertCardToFlutter(card)).toList(),
      'cardsToPeek': player.cardsToPeek.map((card) => _convertCardToFlutter(card)).toList(),
      'score': player.calculatePoints(),
      'status': statusString,
      'isCurrentPlayer': false,
      'hasCalledRecall': player.hasCalledRecall,
      'drawnCard': player.drawnCard != null ? _convertCardToFlutter(player.drawnCard!) : null,
      'cardsRemaining': player.cardsRemaining,
      'isActive': player.isActive,
      'initialPeeksRemaining': player.initialPeeksRemaining,
    };
  }
  
  /// Convert card to Flutter format
  Map<String, dynamic> _convertCardToFlutter(Card card) {
    final rankMapping = {
      '2': 'two', '3': 'three', '4': 'four', '5': 'five',
      '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten'
    };
    
    return {
      'cardId': card.cardId,
      'suit': card.suit,
      'rank': rankMapping[card.rank] ?? card.rank,
      'points': card.points,
      'displayName': card.toString(),
      'color': ['hearts', 'diamonds'].contains(card.suit) ? 'red' : 'black',
      'isVisible': card.isVisible,
    };
  }
  
  /// Get AI players list
  List<Player> get aiPlayers => List.from(_aiPlayers);
  
  /// Get AI player by ID
  Player? getAIPlayerById(String playerId) {
    try {
      return _aiPlayers.firstWhere((player) => player.playerId == playerId);
    } catch (e) {
      return null;
    }
  }
  
  /// Clear AI players
  void clearAIPlayers() {
    _aiPlayers.clear();
    Logger().info('Practice: Cleared all AI players', isOn: LOGGING_SWITCH);
  }
  
  // Practice event handlers
  
  bool _handleStartMatch(String sessionId, Map<String, dynamic> data) {
    Logger().info('Practice: Starting match for session $sessionId', isOn: LOGGING_SWITCH);
    
    try {
      // Generate practice game ID
      _currentPracticeGameId = 'practice_${DateTime.now().millisecondsSinceEpoch}';
      
      // Extract practice game settings
      final numberOfOpponents = data['numberOfOpponents'] ?? 3;
      final difficultyLevel = data['difficultyLevel'] ?? 'medium';
      
      Logger().info('Practice: Starting match with $numberOfOpponents AI opponents (difficulty: $difficultyLevel)', isOn: LOGGING_SWITCH);
      
      // ========= PHASE 1: CREATE DECK =========
      Logger().info('Practice: Phase 1 - Creating deck', isOn: LOGGING_SWITCH);
      final deck = _createDeck();
      if (deck.isEmpty) {
        Logger().error('Practice: Failed to create deck', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // ========= PHASE 2: CREATE AI PLAYERS =========
      Logger().info('Practice: Phase 2 - Creating AI players', isOn: LOGGING_SWITCH);
      final aiPlayers = createAIPlayers(numberOfOpponents, difficultyLevel);
      if (aiPlayers.isEmpty) {
        Logger().error('Practice: Failed to create AI players', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // ========= PHASE 3: CREATE HUMAN PLAYER =========
      Logger().info('Practice: Phase 3 - Creating human player', isOn: LOGGING_SWITCH);
      final humanPlayer = Player(
        playerId: 'human_player_${DateTime.now().millisecondsSinceEpoch}',
        name: 'You',
        playerType: PlayerType.human,
      );
      humanPlayer.hand = <Card>[];
      humanPlayer.cardsRemaining = 0;
      humanPlayer.status = PlayerStatus.waiting;
      
      // ========= PHASE 4: COMBINE ALL PLAYERS =========
      final allPlayers = [humanPlayer, ...aiPlayers];
      Logger().info('Practice: Phase 4 - Combined ${allPlayers.length} players (1 human + ${aiPlayers.length} AI)', isOn: LOGGING_SWITCH);
      
      // ========= PHASE 5: DEAL CARDS =========
      Logger().info('Practice: Phase 5 - Dealing cards', isOn: LOGGING_SWITCH);
      _dealCards(deck, allPlayers);
      
      // ========= PHASE 6: SET UP PILES =========
      Logger().info('Practice: Phase 6 - Setting up draw/discard piles', isOn: LOGGING_SWITCH);
      final cardsUsed = allPlayers.length * 4; // 4 cards per player
      final pilesData = _setupPiles(deck, cardsUsed);
      
      // ========= PHASE 7: UPDATE PLAYER STATUS =========
      Logger().info('Practice: Phase 7 - Updating player status', isOn: LOGGING_SWITCH);
      _updateAllPlayersStatus(allPlayers);
      
      // ========= PHASE 8: START INITIAL PEEK =========
      Logger().info('Practice: Phase 8 - Starting initial peek phase', isOn: LOGGING_SWITCH);
      _startInitialPeekPhase(allPlayers);
      
      // ========= PHASE 9: CREATE GAME STATE =========
      Logger().info('Practice: Phase 9 - Creating game state', isOn: LOGGING_SWITCH);
      final practiceGameState = _createPracticeGameStateWithPlayersAndDeck(data, allPlayers, pilesData);
      
      // ========= PHASE 10: UPDATE GLOBAL STATE =========
      Logger().info('Practice: Phase 10 - Updating global state', isOn: LOGGING_SWITCH);
      _updatePracticeGameState(practiceGameState);
      
      // Call game state manager if available
      final gameStateResult = gameStateManager?.onStartMatch(sessionId, data) ?? true;
      
      Logger().info('Practice: Match started successfully with ID $_currentPracticeGameId', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Game setup complete - ${allPlayers.length} players, ${pilesData['drawPileCount']} cards in draw pile', isOn: LOGGING_SWITCH);
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
  
  
  /// Create practice game state with players and deck information
  Map<String, dynamic> _createPracticeGameStateWithPlayersAndDeck(Map<String, dynamic> data, List<Player> allPlayers, Map<String, dynamic> pilesData) {
    final gameId = _currentPracticeGameId!;
    final timestamp = DateTime.now().toIso8601String();

    // Convert all players to Flutter format
    final playersFlutter = allPlayers.map((player) => _convertPlayerToFlutter(player)).toList();

    Logger().info('Practice: Created game state with ${playersFlutter.length} players', isOn: LOGGING_SWITCH);

    return {
      'gameId': gameId,
      'gameType': 'practice',
      'phase': 'initial_peek', // Start in initial peek phase
      'gamePhase': 'initial_peek',
      'isGameActive': true,
      'isPracticeMode': true,
      'currentPlayer': null, // No current player during initial peek
      'players': playersFlutter,
      'gameData': {
        'game_state': {
          'game_id': gameId,
          'phase': 'initial_peek',
          'current_player_id': null,
          'players': playersFlutter,
          'playerCount': playersFlutter.length,
          'maxPlayers': (data['numberOfOpponents'] ?? 3) + 1, // +1 for human player
          'deck': <Map<String, dynamic>>[], // Empty deck after dealing
          'draw_pile': (pilesData['drawPile'] as List<Card>).map((card) => _convertCardToFlutter(card)).toList(),
          'discard_pile': (pilesData['discardPile'] as List<Card>).map((card) => _convertCardToFlutter(card)).toList(),
          'game_ended': false,
          'winner': null,
          'recall_called_by': null,
          'last_action_time': timestamp,
          'game_start_time': timestamp,
        },
        'room_info': {
          'room_id': gameId,
          'max_players': (data['numberOfOpponents'] ?? 3) + 1, // +1 for human player
          'min_players': 2,
          'permission': 'practice',
          'game_type': 'practice',
          'turn_time_limit': data['turnTimer'] ?? 30,
          'difficulty_level': data['difficultyLevel'] ?? 'medium',
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

  
  /// Update practice game state in global state manager with validation
  void _updatePracticeGameState(Map<String, dynamic> practiceGameState) {
    try {
      // Validate practice game state before updating
      final validatedState = _validatePracticeGameState(practiceGameState);
      
      // Get current games map
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      // Add validated practice game to games map
      currentGames[_currentPracticeGameId!] = validatedState;
      
      // Get players from validated state
      final players = validatedState['players'] as List<dynamic>;
      final humanPlayer = players.firstWhere((p) => p['type'] == 'human', orElse: () => <String, dynamic>{});

      // Set fake currentUserId for practice mode so OpponentsPanelWidget can filter properly
      final humanPlayerId = humanPlayer['id']?.toString() ?? 'practice_human_player';
      _stateManager.updateModuleState('login', {
        'userId': humanPlayerId,
        'isLoggedIn': true,
        'username': 'Practice Player',
      });

      // Update global state directly to avoid main schema validation conflicts
      _stateManager.updateModuleState('recall_game', {
        'games': currentGames,
        'currentGameId': _currentPracticeGameId,
        'isInRoom': true,
        'currentRoomId': _currentPracticeGameId,
        'gamePhase': 'initial_peek',
        'isGameActive': true,
        'isInGame': true,
        'isMyTurn': false,
        'playerStatus': 'initial_peek',
        'gameInfo': {
          'currentGameId': _currentPracticeGameId,
          'currentSize': players.length,
          'maxSize': players.length,
          'gamePhase': 'initial_peek',
          'gameStatus': 'active',
          'isRoomOwner': true, // Practice game user is always the owner
          'isInGame': true,
        },
        'myHand': {
          'cards': humanPlayer?['hand'] as List<dynamic>? ?? <Map<String, dynamic>>[],
          'selectedIndex': -1,
          'selectedCard': null,
        },
        'opponentsPanel': {
          'opponents': players, // Include ALL players (human + AI) so widget can filter
          'currentTurnIndex': -1,
        },
        'centerBoard': {
          'drawPileCount': _getDrawPileCount(validatedState),
          'canDrawFromDeck': false,
          'topDiscard': _getTopDiscardCard(validatedState),
          'canTakeFromDiscard': false,
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      Logger().info('Practice: Updated validated game state for $_currentPracticeGameId', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to update game state: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Validate practice game state against schema
  Map<String, dynamic> _validatePracticeGameState(Map<String, dynamic> state) {
    try {
      Logger().info('Practice: Validating practice game state with ${state.length} fields', isOn: LOGGING_SWITCH);
      
      final validatedState = <String, dynamic>{};
      final validFields = <String>[];
      final invalidFields = <String>[];
      
      for (final entry in state.entries) {
        final key = entry.key;
        final value = entry.value;
        
        // Check if field exists in practice schema
        final fieldSpec = _practiceStateSchema[key];
        if (fieldSpec == null) {
          Logger().warning('Practice: Unknown field "$key" in practice game state', isOn: LOGGING_SWITCH);
          continue; // Skip unknown fields for practice games
        }
        
        // Validate field value
        try {
          final validatedValue = _validatePracticeFieldValue(key, value, fieldSpec);
          validatedState[key] = validatedValue;
          validFields.add(key);
          
          Logger().debug('Practice: Field "$key" validated successfully', isOn: LOGGING_SWITCH);
        } catch (e) {
          Logger().error('Practice: Field validation failed for "$key": $e', isOn: LOGGING_SWITCH);
          invalidFields.add(key);
          // Use default value for invalid fields
          if (fieldSpec.defaultValue != null) {
            validatedState[key] = fieldSpec.defaultValue;
            Logger().info('Practice: Using default value for invalid field "$key"', isOn: LOGGING_SWITCH);
          }
        }
      }
      
      // Add timestamp if not present
      if (!validatedState.containsKey('lastUpdated')) {
        validatedState['lastUpdated'] = DateTime.now().toIso8601String();
      }
      
      Logger().info('Practice: Validation completed - ${validFields.length} valid, ${invalidFields.length} invalid', isOn: LOGGING_SWITCH);
      
      return validatedState;
      
    } catch (e) {
      Logger().error('Practice: State validation failed: $e', isOn: LOGGING_SWITCH);
      // Return minimal valid state on validation failure
      return {
        'gameId': _currentPracticeGameId ?? 'unknown',
        'gameType': 'practice',
        'phase': 'waiting',
        'gamePhase': 'waiting',
        'isGameActive': false,
        'isPracticeMode': true,
        'players': [],
        'gameData': {},
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }
  }
  
  /// Validate individual practice field value
  dynamic _validatePracticeFieldValue(String key, dynamic value, RecallStateFieldSpec spec) {
    // Handle null values
    if (value == null) {
      if (spec.required) {
        throw RecallStateException('Field "$key" is required and cannot be null', fieldName: key);
      }
      if (spec.nullable == true) {
        return null;
      }
      return spec.defaultValue;
    }
    
    // Type validation
    if (!ValidationUtils.isValidType(value, spec.type)) {
      throw RecallStateException('Field "$key" must be of type ${spec.type}, got ${value.runtimeType}', fieldName: key);
    }
    
    // Allowed values validation
    if (spec.allowedValues != null && !ValidationUtils.isAllowedValue(value, spec.allowedValues!)) {
      throw RecallStateException('Field "$key" value "$value" is not allowed. Allowed values: ${spec.allowedValues!.join(', ')}', fieldName: key);
    }
    
    // Range validation for numbers
    if (value is int) {
      if (!ValidationUtils.isValidRange(value, min: spec.min, max: spec.max)) {
        final rangeDesc = [
          if (spec.min != null) 'min: ${spec.min}',
          if (spec.max != null) 'max: ${spec.max}',
        ].join(', ');
        throw RecallStateException('Field "$key" value $value is out of range ($rangeDesc)', fieldName: key);
      }
    }
    
    return value;
  }
  
  /// Update practice game action in state with validation
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
        
        // Create updated game state
        final updatedGame = {
          ...currentGame,
          'gameData': {
            ...currentGameData,
            'game_state': updatedGameState,
          },
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        // Validate the updated game state
        final validatedGame = _validatePracticeGameState(updatedGame);
        
        // Update the games map with validated state
        currentGames[_currentPracticeGameId!] = validatedGame;
        
        // Get players from validated state for UI updates
        final players = validatedGame['players'] as List<dynamic>? ?? [];
        final humanPlayer = players.firstWhere((p) => p['type'] == 'human', orElse: () => <String, dynamic>{});

        // Update global state directly to avoid main schema validation conflicts
        _stateManager.updateModuleState('recall_game', {
          'games': currentGames,
          'currentGameId': _currentPracticeGameId,
          'isInRoom': true,
          'currentRoomId': _currentPracticeGameId,
          'gamePhase': validatedGame['gamePhase'] ?? 'waiting',
          'isGameActive': validatedGame['isGameActive'] ?? false,
          'isInGame': true,
          'isMyTurn': false,
          'playerStatus': validatedGame['gamePhase'] ?? 'initial_peek',
          'gameInfo': {
            'currentGameId': _currentPracticeGameId,
            'currentSize': players.length,
            'maxSize': players.length,
            'gamePhase': validatedGame['gamePhase'] ?? 'waiting',
            'gameStatus': 'active',
            'isRoomOwner': true,
            'isInGame': true,
          },
          'myHand': {
            'cards': humanPlayer?['hand'] as List<dynamic>? ?? <Map<String, dynamic>>[],
            'selectedIndex': -1,
            'selectedCard': null,
          },
          'opponentsPanel': {
            'opponents': players,
            'currentTurnIndex': -1,
          },
          'centerBoard': {
            'drawPileCount': _getDrawPileCount(validatedGame),
            'canDrawFromDeck': false,
            'topDiscard': _getTopDiscardCard(validatedGame),
            'canTakeFromDiscard': false,
          },
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        Logger().info('Practice: Updated validated action $action for $_currentPracticeGameId', isOn: LOGGING_SWITCH);
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
      
      try {
        // Get current state
        final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
        
        // Remove the practice game from games map
        currentGames.remove(_currentPracticeGameId);
        
        // Update global state to clear practice game
        _stateManager.updateModuleState('recall_game', {
          'games': currentGames,
          'currentGameId': null,
          'isInRoom': false,
          'currentRoomId': null,
          'gamePhase': 'waiting',
          'isGameActive': false,
          'isInGame': false,
          'isMyTurn': false,
          'playerStatus': 'unknown',
          'gameInfo': {
            'currentGameId': '',
            'currentSize': 0,
            'maxSize': 4,
            'gamePhase': 'waiting',
            'gameStatus': 'inactive',
            'isRoomOwner': false,
            'isInGame': false,
          },
          'myHand': {
            'cards': <Map<String, dynamic>>[],
            'selectedIndex': -1,
            'selectedCard': null,
          },
          'opponentsPanel': {
            'opponents': <Map<String, dynamic>>[],
            'currentTurnIndex': -1,
          },
          'centerBoard': {
            'drawPileCount': 0,
            'canDrawFromDeck': false,
            'topDiscard': null,
            'canTakeFromDiscard': false,
          },
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        Logger().info('Practice: Cleared practice game state', isOn: LOGGING_SWITCH);
        
      } catch (e) {
        Logger().error('Practice: Failed to clear practice game state: $e', isOn: LOGGING_SWITCH);
      }
      
      // Clear AI players
      clearAIPlayers();
      
      // Clear current practice game ID
      _currentPracticeGameId = null;
      
      Logger().info('Practice: AI players cleared', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Create and shuffle a full deck for practice game
  List<Card> _createDeck() {
    try {
      final gameId = _currentPracticeGameId ?? 'practice_${DateTime.now().millisecondsSinceEpoch}';
      final factory = DeckFactory(gameId);
      final deck = factory.buildDeck(includeJokers: true);
      
      Logger().info('Practice: Created deck with ${deck.length} cards', isOn: LOGGING_SWITCH);
      return deck;
    } catch (e) {
      Logger().error('Practice: Failed to create deck: $e', isOn: LOGGING_SWITCH);
      return [];
    }
  }
  
  /// Deal 4 cards to each player (human + AI)
  void _dealCards(List<Card> deck, List<Player> allPlayers) {
    try {
      int cardIndex = 0;
      
      // Deal 4 cards to each player
      for (final player in allPlayers) {
        final playerHand = <Card>[];
        
        // Deal 4 cards to this player
        for (int i = 0; i < 4; i++) {
          if (cardIndex < deck.length) {
            final card = deck[cardIndex];
            card.ownerId = player.playerId;
            card.isVisible = false; // Face down initially
            playerHand.add(card);
            cardIndex++;
          }
        }
        
        // Set player's hand
        player.hand = playerHand;
        player.cardsRemaining = playerHand.length;
        player.status = PlayerStatus.waiting;
        
        Logger().info('Practice: Dealt ${playerHand.length} cards to ${player.name}', isOn: LOGGING_SWITCH);
      }
      
      Logger().info('Practice: Card dealing complete. Used $cardIndex cards from deck', isOn: LOGGING_SWITCH);
    } catch (e) {
      Logger().error('Practice: Failed to deal cards: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Set up draw and discard piles
  Map<String, dynamic> _setupPiles(List<Card> deck, int cardsUsed) {
    try {
      // Remaining cards become draw pile
      final drawPile = deck.skip(cardsUsed).toList();
      
      // Discard pile starts with first card from draw pile (like backend)
      final discardPile = <Card>[];
      if (drawPile.isNotEmpty) {
        final firstCard = drawPile.removeAt(0);
        discardPile.add(firstCard);
        Logger().info('Practice: Moved first card (${firstCard.rank} of ${firstCard.suit}) to discard pile', isOn: LOGGING_SWITCH);
      }
      
      Logger().info('Practice: Set up piles - Draw pile: ${drawPile.length} cards, Discard pile: ${discardPile.length} cards', isOn: LOGGING_SWITCH);
      
      return {
        'drawPile': drawPile,
        'discardPile': discardPile,
        'drawPileCount': drawPile.length,
        'discardPileCount': discardPile.length,
      };
    } catch (e) {
      Logger().error('Practice: Failed to setup piles: $e', isOn: LOGGING_SWITCH);
      return {
        'drawPile': <Card>[],
        'discardPile': <Card>[],
        'drawPileCount': 0,
        'discardPileCount': 0,
      };
    }
  }
  
  /// Update all players' status to READY
  void _updateAllPlayersStatus(List<Player> allPlayers) {
    try {
      for (final player in allPlayers) {
        player.status = PlayerStatus.ready;
      }
      
      Logger().info('Practice: Updated ${allPlayers.length} players status to READY', isOn: LOGGING_SWITCH);
    } catch (e) {
      Logger().error('Practice: Failed to update player status: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Start initial peek phase (10-second timer simulation)
  void _startInitialPeekPhase(List<Player> allPlayers) {
    try {
      // Set all players to INITIAL_PEEK status
      for (final player in allPlayers) {
        Logger().info('Practice: Setting ${player.name} (${player.playerId}) status to INITIAL_PEEK', isOn: LOGGING_SWITCH);
        player.status = PlayerStatus.initialPeek;
        Logger().info('Practice: ${player.name} status is now: ${player.status}', isOn: LOGGING_SWITCH);
      }
      
      Logger().info('Practice: Initial peek phase started for ${allPlayers.length} players', isOn: LOGGING_SWITCH);
      
      // In a real game, this would start a 10-second timer
      // For practice, we'll simulate this phase
      Logger().info('Practice: Initial peek phase - players can look at 2 of their 4 cards', isOn: LOGGING_SWITCH);
    } catch (e) {
      Logger().error('Practice: Failed to start initial peek phase: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Get draw pile count from game state
  int _getDrawPileCount(Map<String, dynamic> gameState) {
    try {
      final gameData = gameState['gameData'] as Map<String, dynamic>? ?? {};
      final gameStateData = gameData['game_state'] as Map<String, dynamic>? ?? {};
      final drawPile = gameStateData['draw_pile'] as List<dynamic>? ?? [];
      return drawPile.length;
    } catch (e) {
      Logger().error('Practice: Failed to get draw pile count: $e', isOn: LOGGING_SWITCH);
      return 0;
    }
  }
  
  /// Get top discard card from game state
  Map<String, dynamic>? _getTopDiscardCard(Map<String, dynamic> gameState) {
    try {
      final gameData = gameState['gameData'] as Map<String, dynamic>? ?? {};
      final gameStateData = gameData['game_state'] as Map<String, dynamic>? ?? {};
      final discardPile = gameStateData['discard_pile'] as List<dynamic>? ?? [];
      
      if (discardPile.isNotEmpty) {
        return discardPile.last as Map<String, dynamic>?;
      }
      
      return null;
    } catch (e) {
      Logger().error('Practice: Failed to get top discard card: $e', isOn: LOGGING_SWITCH);
      return null;
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
