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

const bool LOGGING_SWITCH = false;

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
      player['status'] = 'waiting'; // Set to initial peek status
      
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
      
      // Deal cards to players (replicating backend _deal_cards logic)
      final dealtPlayers = _dealCardsToPlayers(allPlayers, deck);
      
      // Set up draw and discard piles (replicating backend _setup_piles logic)
      final pileSetup = _setupPiles(deck);
      
      // Initialize game state properties (replicating backend GameState.__init__)
      final gameState = {
        // Core Game Properties
        'gameId': gameId,
        'gameName': 'Practice Recall Game $gameId',
        'maxPlayers': maxPlayers,
        'minPlayers': minPlayers,
        'permission': permission,
        
        // Player Management
        'players': dealtPlayers,
        'currentPlayer': dealtPlayers.isNotEmpty ? dealtPlayers.first : null, // First player is current
        'playerCount': dealtPlayers.length,
        'activePlayerCount': dealtPlayers.length,
        
        // Game State
        'phase': 'dealing_cards', // GamePhase.DEALING_CARDS (cards have been dealt)
        'status': 'active', // Game status
        'deck': <Map<String, dynamic>>[], // Deck is now empty after dealing
        'discardPile': pileSetup['discardPile'],
        'drawPile': pileSetup['drawPile'],
        
        // Game Flow Control
        'outOfTurnDeadline': null,
        'outOfTurnTimeoutSeconds': 5,
        'lastPlayedCard': null,
        'recallCalledBy': null,
        
        // Timing and History
        'gameStartTime': DateTime.now().toIso8601String(),
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
        'gameStatus': 'dealing_cards', // Updated to reflect cards have been dealt
        'isRoomOwner': true, // Practice user is always owner
        'isInGame': true,
        'joinedAt': DateTime.now().toIso8601String(),
        // Add human player's hand data for myHand widget
        'myHandCards': humanPlayer['hand'], // Human player's dealt cards
        'selectedCardIndex': -1, // No card selected initially
        'isMyTurn': true, // Human player is current player
        'myDrawnCard': null, // No drawn card initially
        'canPlayCard': false, // Can't play cards during initial peek
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
    'gamePhase': _mapBackendPhaseToFrontend('dealing_cards'),
    'isGameActive': true,
    'games': currentGames,
    'isMyTurn': true, // First player (human) is current player
    'playerStatus': 'waiting', // Players are in initial peek phase
    'turnTimeout': turnTimeLimit,
    'permission': permission,
    'maxSize': maxPlayers,
    'minSize': minPlayers,
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
      
      // Add session message about game creation
      _addSessionMessage(
        level: 'info',
        title: 'Practice Game Created',
        message: 'Practice game $gameId created with ${dealtPlayers.length} players. Cards dealt: 4 per player. Draw pile: ${pileSetup['drawPile'].length} cards, Discard pile: ${pileSetup['discardPile'].length} cards.',
        data: {
          'game_id': gameId,
          'max_players': maxPlayers,
          'min_players': minPlayers,
          'game_type': gameType,
          'cards_dealt': true,
          'draw_pile_size': pileSetup['drawPile'].length,
          'discard_pile_size': pileSetup['discardPile'].length,
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

  /// Update player status for a specific player or all players
  /// 
  /// [status] The new status to set
  /// [playerId] Optional player ID. If null, updates all players
  /// [updateMainState] Whether to also update the main game state playerStatus
  /// 
  /// Returns true if successful, false otherwise
  bool updatePlayerStatus(String status, {String? playerId, bool updateMainState = true}) {
    try {
      final currentGames = _getCurrentGamesMap();
      final currentGameId = _currentPracticeGameId;
      
      if (currentGameId == null || currentGameId.isEmpty || !currentGames.containsKey(currentGameId)) {
        Logger().error('Practice: No active practice game found for updatePlayerStatus', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Navigate to game state
      final gameData = currentGames[currentGameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for updatePlayerStatus', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final players = gameState['players'] as List<Map<String, dynamic>>?;
      
      if (players == null) {
        Logger().error('Practice: Players list is null for updatePlayerStatus', isOn: LOGGING_SWITCH);
        return false;
      }
      
      if (playerId != null) {
        // Update specific player
        final player = players.firstWhere(
          (p) => p['id'] == playerId,
          orElse: () => <String, dynamic>{},
        );
        
        if (player.isEmpty) {
          Logger().error('Practice: Player $playerId not found', isOn: LOGGING_SWITCH);
          return false;
        }
        
        player['status'] = status;
        Logger().info('Practice: Updated player ${player['name']} to $status status', isOn: LOGGING_SWITCH);
        
      } else {
        // Update all players
        for (final player in players) {
          player['status'] = status;
        }
        Logger().info('Practice: Updated ${players.length} players to $status status', isOn: LOGGING_SWITCH);
      }
      
      // Update main state if requested
      if (updateMainState) {
        updatePracticeGameState({
          'playerStatus': status,
          'games': currentGames,
        });
      }
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Failed to update player status: $e', isOn: LOGGING_SWITCH);
      return false;
    }
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
  // EVENT HANDLING
  // ========================================

  /// Handle practice events from the practice room
  Future<bool> handlePracticeEvent(String sessionId, String eventName, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Handling event: $eventName with data: $data', isOn: LOGGING_SWITCH);
      
      switch (eventName) {
        case 'start_match':
          return await _handleStartMatch(sessionId, data);
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
      
      // Create the practice game with the specified settings
      final gameId = await createPracticeGame(
        maxPlayers: totalPlayers,
        minPlayers: 2, // Minimum for any game
        permission: 'public',
        gameType: 'practice',
        turnTimeLimit: _turnTimer ?? 0, // 0 means no timer
        autoStart: true,
        numberOfOpponents: _numberOfOpponents,
        difficultyLevel: _difficultyLevel,
        instructionsEnabled: _instructionsEnabled,
      );
      
      // Store the current game ID and mark as active
      _currentPracticeGameId = gameId;
      _isPracticeGameActive = true;
      
      // Update turn timer seconds for the coordinator
      _turnTimerSeconds = _turnTimer ?? 0;
      
      // Add session message about game start
      _addSessionMessage(
        level: 'info',
        title: 'Practice Game Started',
        message: 'Practice game started with $_numberOfOpponents AI opponents (${_difficultyLevel.toUpperCase()} difficulty)',
        data: {
          'game_id': gameId,
          'number_of_opponents': _numberOfOpponents,
          'difficulty_level': _difficultyLevel,
          'turn_timer': _turnTimer,
          'instructions_enabled': _instructionsEnabled,
          'total_players': totalPlayers,
        },
      );
      
      Logger().info('Practice: Match started successfully with game ID: $gameId', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Failed to start match: $e', isOn: LOGGING_SWITCH);
    return false;
    }
  }

  /// Handle start match directly from widget (bypasses PlayerAction)
  Future<bool> matchStart() async {
    try {
      Logger().info('Practice: Direct matchStart() called from widget', isOn: LOGGING_SWITCH);
      
      // Get current games map
      final currentGames = _getCurrentGamesMap();
      final currentGameId = _currentPracticeGameId;
      
      if (currentGameId == null || currentGameId.isEmpty || !currentGames.containsKey(currentGameId)) {
        Logger().error('Practice: No active practice game found for matchStart', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Update all players to initial_peek status using unified method
      final statusUpdated = updatePlayerStatus('initial_peek', updateMainState: false);
      if (!statusUpdated) {
        return false;
      }
      
      // Update the main game state with game phase
      updatePracticeGameState({
        'playerStatus': 'initial_peek',
        'gamePhase': _mapBackendPhaseToFrontend('dealing_cards'), // Maps to 'setup'
        'games': _getCurrentGamesMap(), // Update the games map with modified players
      });
      
      Logger().info('Practice: Match started - all players set to initial_peek', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Failed to start match via matchStart: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }
}
