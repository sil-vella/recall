/// Practice Game Coordinator for Recall Game
///
/// This class provides a simplified game coordinator for practice sessions,
/// allowing players to learn the game mechanics without full WebSocket integration.

import 'dart:async';
import 'dart:math';
import 'package:recall/tools/logging/logger.dart';
import '../../../../core/managers/state_manager.dart';
import '../models/player.dart';
import 'practice_game_round.dart';
import 'practice_instructions.dart';
import '../../managers/validated_state_manager.dart';
import 'utils/deck_factory.dart';
import 'models/card.dart';

const bool LOGGING_SWITCH = true;

class PracticeGameCoordinator {
  /// Coordinates practice game sessions for the Recall game
  
  // Singleton pattern
  static final PracticeGameCoordinator _instance = PracticeGameCoordinator._internal();
  factory PracticeGameCoordinator() => _instance;
  
  PracticeGameCoordinator._internal() {

  }
  
  dynamic gameStateManager;
  final StateManager _stateManager = StateManager();
  List<String> registeredEvents = [];
  String? _currentPracticeGameId;
  List<Player> _aiPlayers = [];
  
  // Timer management for initial peek phase
  Timer? _initialPeekTimer;
  static const int _initialPeekDurationSeconds = 10;
  
  // Round management
  PracticeGameRound? _gameRound;
  int _turnTimerSeconds = 30; // User's choice from practice room
  bool _instructionsEnabled = true; // User's choice from practice room
  
  // Practice game settings (set by practice room)
  int _numberOfOpponents = 3;
  String _difficultyLevel = 'easy';
  int? _turnTimer; // null means "Off", seconds for timer values
  bool _isPracticeGameActive = false;
  

  // ========================================
  // INSTRUCTIONS AND MESSAGES
  // ========================================

  /// Show instructions modal with given title and content
  void showInstructions(String title, String content) {
    try {
      if (!_instructionsEnabled) {
        Logger().info('Practice: Instructions disabled, not showing: $title', isOn: LOGGING_SWITCH);
        return;
      }
      
      Logger().info('Practice: Showing instructions - $title', isOn: LOGGING_SWITCH);
      
      // Get current state to preserve games map
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      _stateManager.updateModuleState('recall_game', {
        'games': currentGames, // CRITICAL: Preserve the games map
        'instructions': {
          'isVisible': true,
          'title': title,
          'content': content,
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      Logger().error('Practice: Failed to show instructions: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Hide instructions modal
  void hideInstructions() {
    try {
      Logger().info('Practice: Hiding instructions modal', isOn: LOGGING_SWITCH);
      
      // Get current state to preserve games map
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      _stateManager.updateModuleState('recall_game', {
        'games': currentGames, // CRITICAL: Preserve the games map
        'instructions': {
          'isVisible': false,
          'title': '',
          'content': '',
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      Logger().error('Practice: Failed to hide instructions: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Show message modal with given parameters
  void showMessage(String title, String content, {
    String type = 'info',
    bool showCloseButton = true,
    bool autoClose = false,
    int autoCloseDelay = 3000,
  }) {
    try {
      Logger().info('Practice: Showing message - $title', isOn: LOGGING_SWITCH);
      
      // Get current state to preserve games map
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      _stateManager.updateModuleState('recall_game', {
        'games': currentGames, // CRITICAL: Preserve the games map
        'messages': {
          'isVisible': true,
          'title': title,
          'content': content,
          'type': type,
          'showCloseButton': showCloseButton,
          'autoClose': autoClose,
          'autoCloseDelay': autoCloseDelay,
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      Logger().error('Practice: Failed to show message: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Hide message modal
  void hideMessage() {
    try {
      Logger().info('Practice: Hiding message modal', isOn: LOGGING_SWITCH);
      
      // Get current state to preserve games map
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      _stateManager.updateModuleState('recall_game', {
        'games': currentGames, // CRITICAL: Preserve the games map
        'messages': {
          'isVisible': false,
          'title': '',
          'content': '',
          'type': 'info',
          'showCloseButton': true,
          'autoClose': false,
          'autoCloseDelay': 3000,
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      Logger().error('Practice: Failed to hide message: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Show instructions based on current game phase and player status
  void showContextualInstructions() {
    try {
      if (!_instructionsEnabled) {
        Logger().info('Practice: Instructions disabled, not showing contextual instructions', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Get current game state
      final recallGameState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final gameInfo = recallGameState['gameInfo'] as Map<String, dynamic>? ?? {};
      final gamePhase = gameInfo['gamePhase']?.toString() ?? '';
      final playerStatus = recallGameState['playerStatus']?.toString() ?? '';
      
      Logger().info('Practice: Checking contextual instructions - gamePhase: $gamePhase, playerStatus: $playerStatus', isOn: LOGGING_SWITCH);
      
      // Try player status instructions first (more specific)
      if (playerStatus.isNotEmpty && PracticeInstructions.hasPlayerStatusInstruction(playerStatus)) {
        final instruction = PracticeInstructions.getPlayerStatusInstruction(playerStatus)!;
        final timerText = _turnTimerSeconds == 0 ? "No time limit" : "${_turnTimerSeconds} seconds";
        final content = instruction['content']!.replaceAll('[TIMER]', timerText);
        Logger().info('Practice: Showing player status instructions for: $playerStatus', isOn: LOGGING_SWITCH);
        showInstructions(instruction['title']!, content);
        return;
      }
      
      // Fall back to game phase instructions
      if (gamePhase.isNotEmpty && PracticeInstructions.hasGamePhaseInstruction(gamePhase)) {
        final instruction = PracticeInstructions.getGamePhaseInstruction(gamePhase)!;
        final timerText = _turnTimerSeconds == 0 ? "No time limit" : "${_turnTimerSeconds} seconds";
        final content = instruction['content']!.replaceAll('[TIMER]', timerText);
        Logger().info('Practice: Showing game phase instructions for: $gamePhase', isOn: LOGGING_SWITCH);
        showInstructions(instruction['title']!, content);
        return;
      }
      
      Logger().info('Practice: No contextual instructions found for gamePhase: $gamePhase, playerStatus: $playerStatus', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to show contextual instructions: $e', isOn: LOGGING_SWITCH);
    }
  }

  // ========================================
  // STATE MANAGEMENT WRAPPER METHODS
  // ========================================

  /// Wrapper method to update state using the validated state manager
  /// This ensures all state updates go through proper validation
  void updatePracticeGameState(Map<String, dynamic> updates) {
    try {
      Logger().info('Practice: Updating state with validated state manager', isOn: LOGGING_SWITCH);
      Logger().info('Practice: State updates: $updates', isOn: LOGGING_SWITCH);
      
      // Use the validated state manager to update state
      RecallGameStateUpdater.instance.updateState(updates);
      
      Logger().info('Practice: State updated successfully', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to update state: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }


  // ========================================
  // DECK CREATION
  // ========================================

  /// Create a deck for the practice game using YAML configuration
  Future<List<Map<String, dynamic>>> _createDeck(String gameId) async {
    try {
      Logger().info('Practice: Creating deck for game $gameId', isOn: LOGGING_SWITCH);
      
      // Use YAML-based deck factory from assets
      final configPath = 'assets/deck_config.yaml';
      Logger().info('Practice: Loading YAML config from assets: $configPath', isOn: LOGGING_SWITCH);
      
      final yamlFactory = await YamlDeckFactory.fromFile(gameId, configPath);
      
      // Build deck using configuration
      final deck = yamlFactory.buildDeck(includeJokers: true);
      
      // Convert Card objects to Map format for game state
      final deckMaps = deck.cast<Card>().map<Map<String, dynamic>>((card) => card.toMap()).toList();
      
      Logger().info('Practice: Created deck with ${deckMaps.length} cards using YAML config', isOn: LOGGING_SWITCH);
      
      // Log deck statistics for debugging
      final summary = yamlFactory.getSummary();
      Logger().info('Practice: Deck summary - Testing mode: ${summary['testing_mode']}, Total cards: ${summary['expected_total_cards']}', isOn: LOGGING_SWITCH);
      
      return deckMaps;
      
    } catch (e) {
      Logger().error('Practice: Failed to create deck with YAML config: $e', isOn: LOGGING_SWITCH);
      
      // Fallback to basic deck factory if YAML fails
      Logger().info('Practice: Falling back to basic deck factory', isOn: LOGGING_SWITCH);
      try {
        final basicFactory = getDeckFactory(gameId);
        final basicDeck = basicFactory.buildDeck(includeJokers: true);
        final deckMaps = basicDeck.cast<Card>().map<Map<String, dynamic>>((card) => card.toMap()).toList();
        
        Logger().info('Practice: Created deck with ${deckMaps.length} cards using basic factory', isOn: LOGGING_SWITCH);
        return deckMaps;
        
      } catch (fallbackError) {
        Logger().error('Practice: Fallback deck creation also failed: $fallbackError', isOn: LOGGING_SWITCH);
        
        // Last resort: create a minimal deck manually
        Logger().info('Practice: Creating minimal deck as last resort', isOn: LOGGING_SWITCH);
        return _createMinimalDeck(gameId);
      }
    }
  }

  /// Create a minimal deck as last resort
  List<Map<String, dynamic>> _createMinimalDeck(String gameId) {
    final cards = <Map<String, dynamic>>[];
    
    // Create a simple deck with basic cards
    final suits = ['hearts', 'diamonds', 'clubs', 'spades'];
    final ranks = ['ace', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'jack', 'queen', 'king'];
    
    for (final suit in suits) {
      for (final rank in ranks) {
        final points = _getPointValue(rank);
        final specialPower = _getSpecialPower(rank);
        final cardId = 'card_${gameId}_${rank}_${suit}_${cards.length}';
        
        cards.add({
          'cardId': cardId,
          'rank': rank,
          'suit': suit,
          'points': points,
          'specialPower': specialPower,
        });
      }
    }
    
    // Add 2 jokers
    for (int i = 0; i < 2; i++) {
      cards.add({
        'cardId': 'card_${gameId}_joker_$i',
        'rank': 'joker',
        'suit': 'joker',
        'points': 0,
        'specialPower': null,
      });
    }
    
    Logger().info('Practice: Created minimal deck with ${cards.length} cards', isOn: LOGGING_SWITCH);
    return cards;
  }

  /// Get point value for a card rank
  int _getPointValue(String rank) {
    switch (rank) {
      case 'ace': return 1;
      case 'joker': return 0;
      case 'jack':
      case 'queen':
      case 'king': return 10;
      default:
        final value = int.tryParse(rank);
        return value ?? 0;
    }
  }

  /// Get special power for a card rank
  String? _getSpecialPower(String rank) {
    switch (rank) {
      case 'queen': return 'peek_at_card';
      case 'jack': return 'switch_cards';
      default: return null;
    }
  }

  // ========================================
  // CARD DEALING AND PILE SETUP
  // ========================================

  /// Deal 4 cards to each player (replicating backend _deal_cards logic)
  List<Map<String, dynamic>> _dealCardsToPlayers(List<Map<String, dynamic>> players, List<Map<String, dynamic>> deck) {
    Logger().info('Practice: Dealing cards to ${players.length} players', isOn: LOGGING_SWITCH);
    
    // Create a copy of the deck to work with
    final workingDeck = List<Map<String, dynamic>>.from(deck);
    
    // Deal 4 cards to each player
    for (final player in players) {
      final playerHand = <Map<String, dynamic>>[];
      
      // Deal 4 cards to this player
      for (int i = 0; i < 4; i++) {
        if (workingDeck.isNotEmpty) {
          final card = workingDeck.removeAt(0); // Draw from top of deck
          // Add owner information to the card
          final ownedCard = Map<String, dynamic>.from(card);
          ownedCard['ownerId'] = player['id'];
          playerHand.add(ownedCard);
        }
      }
      
      // Update player's hand
      player['hand'] = playerHand;
      
      // Note: Instructions will be shown after main state update
      
      Logger().info('Practice: Dealt ${playerHand.length} cards to player ${player['name']}', isOn: LOGGING_SWITCH);
    }
    
    Logger().info('Practice: Card dealing complete. ${workingDeck.length} cards remaining in deck', isOn: LOGGING_SWITCH);
    return players;
  }

  /// Set up draw and discard piles (replicating backend _setup_piles logic)
  Map<String, dynamic> _setupPiles(List<Map<String, dynamic>> remainingDeck) {
    Logger().info('Practice: Setting up piles with ${remainingDeck.length} remaining cards', isOn: LOGGING_SWITCH);
    
    // Move remaining cards to draw pile
    final drawPile = List<Map<String, dynamic>>.from(remainingDeck);
    
    // Start discard pile with first card from draw pile
    final discardPile = <Map<String, dynamic>>[];
    if (drawPile.isNotEmpty) {
      final firstCard = drawPile.removeAt(0);
      discardPile.add(firstCard);
    }
    
    Logger().info('Practice: Pile setup complete - Draw pile: ${drawPile.length} cards, Discard pile: ${discardPile.length} cards', isOn: LOGGING_SWITCH);
    
    return {
      'drawPile': drawPile,
      'discardPile': discardPile,
    };
  }


  // ========================================
  // GAME AND AI PLAYER GENERATION
  // ========================================

  /// Create a new practice game with the specified parameters
  /// Replicates the backend game creation logic without WebSocket/room logic
  Future<String> createPracticeGame({
    int maxPlayers = 4,
    int minPlayers = 2,
    String permission = 'public',
    String gameType = 'classic',
    int turnTimeLimit = 30,
    bool autoStart = true,
    int? numberOfOpponents,
    String? difficultyLevel,
    bool? instructionsEnabled,
  }) async {
    try {
      Logger().info('Practice: Creating new practice game', isOn: LOGGING_SWITCH);
      
      // Generate unique game ID (practice_game_*randomnumber*)
      final random = Random();
      final gameId = 'practice_game_${random.nextInt(999999).toString().padLeft(6, '0')}';
      
      Logger().info('Practice: Generated game ID: $gameId', isOn: LOGGING_SWITCH);
      
      // Create computer players based on user parameters
      final computerPlayers = _createComputerPlayers(
        numberOfOpponents: numberOfOpponents ?? _numberOfOpponents,
        difficultyLevel: difficultyLevel ?? _difficultyLevel,
        gameId: gameId,
      );
      
      // Create human player (practice user)
      final humanPlayer = {
        'id': 'practice_user',
        'name': 'You',
        'type': 'human',
        'hand': <Map<String, dynamic>>[], // Will be filled when cards are dealt
        'visibleCards': <Map<String, dynamic>>[],
        'cardsToPeek': <Map<String, dynamic>>[],
        'score': 0,
        'status': 'waiting',
        'isCurrentPlayer': false,
        'hasCalledRecall': false,
        'drawnCard': null,
        'isActive': true,
      };
      
      // Combine all players
      final allPlayers = [humanPlayer, ...computerPlayers];
      
      // Create deck for the game
      final deck = await _createDeck(gameId);
      
      // Note: Card dealing and pile setup will be done in startMatch()
      
      // Initialize game state properties (replicating backend GameState.__init__)
      final gameState = {
        // Core Game Properties
        'gameId': gameId,
        'gameName': 'Practice Recall Game $gameId',
        'maxPlayers': maxPlayers,
        'minPlayers': minPlayers,
        'permission': permission,
        
        // Player Management
        'players': allPlayers, // Players without dealt cards yet
        'currentPlayer': null, // No current player until game starts
        'playerCount': allPlayers.length,
        'activePlayerCount': allPlayers.length,
        
        // Game State
        'phase': 'waiting_for_players', // GamePhase.WAITING_FOR_PLAYERS (waiting to start)
        'status': 'waiting', // Game status - waiting for start
        'deck': deck, // Full deck, not dealt yet
        'discardPile': <Map<String, dynamic>>[], // Empty until game starts
        'drawPile': <Map<String, dynamic>>[], // Empty until game starts
        
        // Game Flow Control
        'outOfTurnDeadline': null,
        'outOfTurnTimeoutSeconds': 5,
        'lastPlayedCard': null,
        'recallCalledBy': null,
        
        // Timing and History
        'gameStartTime': null, // Will be set when game starts
        'lastActivityTime': DateTime.now().toIso8601String(),
        'gameEnded': false,
        'winner': null,
        
        // Practice-Specific Settings
        'numberOfOpponents': numberOfOpponents ?? _numberOfOpponents,
        'difficultyLevel': difficultyLevel ?? _difficultyLevel,
        'instructionsEnabled': instructionsEnabled ?? _instructionsEnabled,
        'practiceSettings': {
          'numberOfOpponents': numberOfOpponents ?? _numberOfOpponents,
          'difficultyLevel': difficultyLevel ?? _difficultyLevel,
          'instructionsEnabled': instructionsEnabled ?? _instructionsEnabled,
          'turnTimer': turnTimeLimit,
          'autoStart': autoStart,
        },
      };
      
      // Add the game to the games map
      final currentGames = _getCurrentGamesMap();
      currentGames[gameId] = {
        'gameData': {
          'game_id': gameId,
          'game_state': gameState,
          'owner_id': 'practice_user', // Practice mode user
        },
        'gameStatus': 'waiting_for_players', // Waiting for game to start
        'isRoomOwner': true, // Practice user is always owner
        'isInGame': true,
        'joinedAt': DateTime.now().toIso8601String(),
        // No hand data yet - cards will be dealt when game starts
        'myHandCards': <Map<String, dynamic>>[], // Empty until cards are dealt
        'selectedCardIndex': -1, // No card selected initially
        'isMyTurn': false, // Not player's turn until game starts
        'myDrawnCard': null, // No drawn card initially
        'canPlayCard': false, // Can't play cards until game starts
      };
      
  // Set login state for practice mode (needed for opponent filtering)
  _stateManager.updateModuleState('login', {
    'userId': 'practice_user',
    'username': 'Practice User',
    'isLoggedIn': true,
  });

  // Update the main game state
  updatePracticeGameState({
    'currentGameId': gameId,
    'gamePhase': _mapBackendPhaseToFrontend('waiting_for_players'),
    'isGameActive': false, // Game is created but not started yet
    'games': currentGames,
    'isMyTurn': false, // Not player's turn until game starts
    'playerStatus': 'waiting', // Players are waiting for game to start
    'turnTimeout': null, // No timeout until game starts
    'permission': permission,
    'maxSize': maxPlayers,
    'minSize': minPlayers,
    'currentSize': allPlayers.length, // Current number of players
    // Add human player's data to main state (myHandCards is handled in games map)
    'myScore': 0, // Initial score
    'myDrawnCard': null, // No drawn card initially
    'myCardsToPeek': <Map<String, dynamic>>[], // No cards to peek initially
  });
      
      // Add session message about game creation
      _addSessionMessage(
        level: 'info',
        title: 'Practice Game Created',
        message: 'Practice game $gameId created with ${allPlayers.length} players. Ready to start!',
        data: {
          'game_id': gameId,
          'max_players': maxPlayers,
          'min_players': minPlayers,
          'game_type': gameType,
          'cards_dealt': false,
          'ready_to_start': true,
        },
      );
      
      Logger().info('Practice: Game created successfully with ID: $gameId', isOn: LOGGING_SWITCH);
      
      return gameId;
      
    } catch (e) {
      Logger().error('Practice: Failed to create game: $e', isOn: LOGGING_SWITCH);
      rethrow;
    }
  }

  /// Add a session message to the message board (helper method)
  void _addSessionMessage({
    required String? level,
    required String? title,
    required String? message,
    Map<String, dynamic>? data,
  }) {
    try {
      final entry = {
        'level': (level ?? 'info'),
        'title': title ?? '',
        'message': message ?? '',
        'data': data ?? {},
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Get current session messages
      final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentMessages = currentState['messages'] as Map<String, dynamic>? ?? {};
      final sessionMessages = List<Map<String, dynamic>>.from(currentMessages['session'] as List<dynamic>? ?? []);
      
      // Add new message
      sessionMessages.add(entry);
      if (sessionMessages.length > 200) sessionMessages.removeAt(0);
      
      // Update state
      updatePracticeGameState({
        'messages': {
          'session': sessionMessages,
          'rooms': currentMessages['rooms'] ?? {},
        },
      });
      
    } catch (e) {
      Logger().error('Practice: Failed to add session message: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Get current games map from state manager (helper method)
  Map<String, dynamic> _getCurrentGamesMap() {
    final currentState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    return Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
  }

  /// Map backend phase values to frontend display phases
  String _mapBackendPhaseToFrontend(String backendPhase) {
    switch (backendPhase) {
      case 'waiting_for_players':
        return 'waiting';
      case 'dealing_cards':
        return 'setup';
      case 'player_turn':
        return 'playing';
      case 'same_rank_window':
        return 'playing';
      case 'special_play_window':
        return 'playing';
      case 'queen_peek_window':
        return 'playing';
      case 'turn_pending_events':
        return 'playing';
      case 'ending_round':
        return 'playing';
      case 'ending_turn':
        return 'playing';
      case 'recall_called':
        return 'playing';
      default:
        return 'waiting';
    }
  }

  /// Create computer players based on user-selected parameters
  List<Map<String, dynamic>> _createComputerPlayers({
    required int numberOfOpponents,
    required String difficultyLevel,
    required String gameId,
  }) {
    final computerPlayers = <Map<String, dynamic>>[];
    
    for (int i = 0; i < numberOfOpponents; i++) {
      final computerId = 'computer_${gameId}_$i';
      final computerName = 'Computer_${i + 1}';
      
      // Create computer player data matching backend _to_flutter_player_data structure
      final computerPlayer = {
        'id': computerId,
        'name': computerName,
        'type': 'computer',
        'hand': <Map<String, dynamic>>[], // Will be filled when cards are dealt
        'visibleCards': <Map<String, dynamic>>[],
        'cardsToPeek': <Map<String, dynamic>>[],
        'score': 0,
        'status': 'waiting',
        'isCurrentPlayer': false,
        'hasCalledRecall': false,
        'drawnCard': null,
        // Practice-specific properties
        'difficulty': difficultyLevel,
        'isActive': true,
      };
      
      computerPlayers.add(computerPlayer);
    }
    
    Logger().info('Practice: Created $numberOfOpponents computer players with difficulty: $difficultyLevel', isOn: LOGGING_SWITCH);
    return computerPlayers;
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

  // ========================================
  // GETTERS FOR PRACTICE ROOM ACCESS
  // ========================================

  /// Get the current practice game ID
  String? get currentPracticeGameId => _currentPracticeGameId;

  /// Check if a practice game is currently active
  bool get isPracticeGameActive => _isPracticeGameActive;

  /// Get the number of registered events
  int getEventCount() => registeredEvents.length;

  /// Get the list of registered events
  List<String> getRegisteredEvents() => List.from(registeredEvents);

  // ========================================
  // GAME START LOGIC
  // ========================================

  /// Start the practice match (deal cards, setup piles, begin gameplay)
  /// This should be called after createPracticeGame() to begin the actual game
  Future<bool> startMatch(String gameId) async {
    try {
      Logger().info('Practice: Starting match for game: $gameId', isOn: LOGGING_SWITCH);
      
      // Get the current game from the games map
      final currentGames = _getCurrentGamesMap();
      final gameData = currentGames[gameId];
      
      if (gameData == null) {
        Logger().error('Practice: Game not found: $gameId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final innerGameData = gameData['gameData'] as Map<String, dynamic>;
      final gameState = innerGameData['game_state'] as Map<String, dynamic>;
      final players = gameState['players'] as List<Map<String, dynamic>>;
      final deck = gameState['deck'] as List<Map<String, dynamic>>;
      
      Logger().info('Practice: Starting match with ${players.length} players and ${deck.length} cards in deck', isOn: LOGGING_SWITCH);
      
      // Deal cards to players (replicating backend _deal_cards logic)
      final dealtPlayers = _dealCardsToPlayers(players, deck);
      
      // Set up draw and discard piles (replicating backend _setup_piles logic)
      final pileSetup = _setupPiles(deck);
      
      // Update game state with dealt cards and piles
      gameState['players'] = dealtPlayers;
      gameState['currentPlayer'] = dealtPlayers.isNotEmpty ? dealtPlayers.first : null; // First player is current
      gameState['phase'] = 'dealing_cards'; // GamePhase.DEALING_CARDS (cards have been dealt)
      gameState['status'] = 'active'; // Game status
      gameState['deck'] = <Map<String, dynamic>>[]; // Deck is now empty after dealing
      gameState['discardPile'] = pileSetup['discardPile'];
      gameState['drawPile'] = pileSetup['drawPile'];
      gameState['gameStartTime'] = DateTime.now().toIso8601String();
      gameState['lastActivityTime'] = DateTime.now().toIso8601String();
      
      // Update the inner game data with new game state (using explicit type conversion)
      final updatedGameData = Map<String, dynamic>.from(innerGameData);
      updatedGameData['game_state'] = gameState;
      
      // Get existing game data to preserve other fields (using explicit type conversion)
      final existingGame = Map<String, dynamic>.from(gameData);
      
      // Update the games map with new game data (explicit map construction to avoid type issues)
      currentGames[gameId] = {
        'gameData': updatedGameData,
        'gameStatus': 'dealing_cards', // Updated to reflect cards have been dealt
        'isRoomOwner': existingGame['isRoomOwner'] ?? true,
        'isInGame': existingGame['isInGame'] ?? true,
        'joinedAt': existingGame['joinedAt'] ?? DateTime.now().toIso8601String(),
        // Add human player's hand data for myHand widget
        'myHandCards': dealtPlayers.firstWhere((p) => p['id'] == 'practice_user')['hand'], // Human player's dealt cards
        'selectedCardIndex': -1, // No card selected initially
        'isMyTurn': true, // Human player is current player
        'myDrawnCard': null, // No drawn card initially
        'canPlayCard': false, // Can't play cards during initial peek
      };
      
      // Update the main game state
      updatePracticeGameState({
        'currentGameId': gameId,
        'gamePhase': _mapBackendPhaseToFrontend('dealing_cards'),
        'isGameActive': true,
        'games': currentGames,
        'isMyTurn': true, // First player (human) is current player
        'playerStatus': 'initial_peek', // Players are in initial peek phase
        'turnTimeout': _turnTimerSeconds > 0 ? DateTime.now().add(Duration(seconds: _turnTimerSeconds)).toIso8601String() : null,
        'currentSize': dealtPlayers.length, // Current number of players
        // Add human player's data to main state (myHandCards is handled in games map)
        'myScore': 0, // Initial score
        'myDrawnCard': null, // No drawn card initially
        'myCardsToPeek': <Map<String, dynamic>>[], // No cards to peek initially
      });

      // Show initial peek instructions if enabled (after state is updated)
      if (_instructionsEnabled) {
        showContextualInstructions();
      }
      
      // Add session message about game start
      _addSessionMessage(
        level: 'info',
        title: 'Practice Game Started',
        message: 'Practice game started with ${_numberOfOpponents} AI opponents (${_difficultyLevel.toUpperCase()} difficulty). Cards dealt: 4 per player.',
        data: {
          'game_id': gameId,
          'number_of_opponents': _numberOfOpponents,
          'difficulty_level': _difficultyLevel,
          'turn_timer': _turnTimer,
          'instructions_enabled': _instructionsEnabled,
          'total_players': dealtPlayers.length,
          'cards_dealt': true,
          'draw_pile_size': pileSetup['drawPile'].length,
          'discard_pile_size': pileSetup['discardPile'].length,
        },
      );
      
      Logger().info('Practice: Match started successfully for game: $gameId', isOn: LOGGING_SWITCH);
      return true;
      
    } catch (e) {
      Logger().error('Practice: Failed to start match for game $gameId: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  // ========================================
  // HELPER METHODS
  // ========================================

  /// Check if a game exists in the games map
  bool _gameExists(String gameId) {
    final currentGames = _getCurrentGamesMap();
    return currentGames.containsKey(gameId);
  }

  // ========================================
  // EVENT HANDLING
  // ========================================

  /// Handle practice events from the practice room
  Future<bool> handlePracticeEvent(String sessionId, String eventName, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Handling event: $eventName with data: $data', isOn: LOGGING_SWITCH);
      
      // Smart routing: If event is start_match, check if game already exists
      if (eventName == 'start_match') {
        final gameId = data['game_id'] as String?;
        if (gameId != null && _gameExists(gameId)) {
          // Game exists, this is actually a begin_game request
          Logger().info('Practice: Game $gameId exists, routing to begin_game', isOn: LOGGING_SWITCH);
          return await _handleBeginGame(sessionId, data);
        }
        // Game doesn't exist, create it
        Logger().info('Practice: Game $gameId does not exist, creating new game', isOn: LOGGING_SWITCH);
        return await _handleStartMatch(sessionId, data);
      }
      
      switch (eventName) {
        case 'begin_game':
          return await _handleBeginGame(sessionId, data);
        default:
          Logger().warning('Practice: Unknown event type: $eventName', isOn: LOGGING_SWITCH);
          return false;
      }
    } catch (e) {
      Logger().error('Practice: Error handling event $eventName: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle the start_match event from practice room
  Future<bool> _handleStartMatch(String sessionId, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Starting match with data: $data', isOn: LOGGING_SWITCH);
      
      // Extract settings from practice room data
      _numberOfOpponents = data['numberOfOpponents'] ?? 3;
      _difficultyLevel = data['difficultyLevel'] ?? 'easy';
      _turnTimer = data['turnTimer']; // Can be null for "Off"
      _instructionsEnabled = data['instructionsEnabled'] ?? true;
      
      Logger().info('Practice: Game settings - Opponents: $_numberOfOpponents, Difficulty: $_difficultyLevel, Timer: $_turnTimer, Instructions: $_instructionsEnabled', isOn: LOGGING_SWITCH);
      
      // Calculate total players (user + opponents)
      final totalPlayers = _numberOfOpponents + 1;
      
      // Step 1: Create the practice game (empty game, waiting for start)
      final gameId = await createPracticeGame(
        maxPlayers: totalPlayers,
        minPlayers: 2, // Minimum for any game
        permission: 'public',
        gameType: 'practice',
        turnTimeLimit: _turnTimer ?? 0, // 0 means no timer
        autoStart: false, // Don't auto-start, we'll start manually
        numberOfOpponents: _numberOfOpponents,
        difficultyLevel: _difficultyLevel,
        instructionsEnabled: _instructionsEnabled,
      );
      
      // Store the current game ID and mark as active
      _currentPracticeGameId = gameId;
      _isPracticeGameActive = true;
      
      // Update turn timer seconds for the coordinator
      _turnTimerSeconds = _turnTimer ?? 0;
      
      Logger().info('Practice: Game created successfully with game ID: $gameId. Ready to start!', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Failed to start match: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle the begin_game event (called when start button is clicked)
  Future<bool> _handleBeginGame(String sessionId, Map<String, dynamic> data) async {
    try {
      final gameId = data['game_id'] as String?;
      
      if (gameId == null || gameId.isEmpty) {
        Logger().error('Practice: No game_id provided for begin_game', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Beginning game $gameId (dealing cards and starting gameplay)', isOn: LOGGING_SWITCH);
      
      // Start the match (deal cards, setup piles, begin gameplay)
      final startSuccess = await startMatch(gameId);
      
      if (!startSuccess) {
        Logger().error('Practice: Failed to begin game $gameId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Game $gameId started successfully', isOn: LOGGING_SWITCH);
      return true;
      
    } catch (e) {
      Logger().error('Practice: Failed to begin game: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }


}
