/// Practice Game Coordinator for Recall Game
///
/// This class provides a simplified game coordinator for practice sessions,
/// allowing players to learn the game mechanics without full WebSocket integration.

import 'dart:async';
import 'dart:math';
import 'package:recall/tools/logging/logger.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../core/managers/services_manager.dart';
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
  bool _initialPeekCompleted = false; // Flag to prevent double completion
  
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

  /// Start a non-disruptive 10-second timer for the initial peek phase
  /// After timer completes, updates player status to 'waiting' and initializes the game round
  void _startInitialPeekTimer() {
    try {
      Logger().info('Practice: Starting ${_initialPeekDurationSeconds}-second initial peek timer (non-disruptive)', isOn: LOGGING_SWITCH);
      
      // Cancel any existing timer
      _initialPeekTimer?.cancel();
      
      // Start new timer
      _initialPeekTimer = Timer(Duration(seconds: _initialPeekDurationSeconds), () {
        Logger().info('Practice: Initial peek timer completed, updating player status to waiting and initializing round', isOn: LOGGING_SWITCH);
        
        // Check if initial peek has already been completed manually
        if (_initialPeekCompleted) {
          Logger().info('Practice: Initial peek already completed manually, skipping timer completion', isOn: LOGGING_SWITCH);
          return;
        }
        
        // Set flag to prevent duplicate calls
        _initialPeekCompleted = true;
        
        // Check if human player completed initial peek
        final currentGames = _getCurrentGamesMap();
        final gameId = _currentPracticeGameId;
        final gameData = currentGames[gameId];
        final gameState = gameData?['gameData']?['game_state'] as Map<String, dynamic>?;
        final players = gameState?['players'] as List<Map<String, dynamic>>? ?? [];
        final humanPlayer = players.firstWhere((p) => p['isHuman'] == true, orElse: () => <String, dynamic>{});
        
        if (humanPlayer.isNotEmpty) {
          final knownCards = humanPlayer['known_cards'] as Map<String, dynamic>? ?? {};
          final hasPlayerKnownCards = knownCards.containsKey(humanPlayer['id']);
          
          if (!hasPlayerKnownCards) {
            // Player never peeked - randomly select 1 card from hand
            final hand = humanPlayer['hand'] as List<Map<String, dynamic>>? ?? [];
            if (hand.isNotEmpty) {
              final random = Random();
              final randomIndex = random.nextInt(hand.length);
              final randomCardId = hand[randomIndex]['cardId'] as String;
              
              final fullCardData = getCardById(gameState!, randomCardId);
              if (fullCardData != null) {
                final collectionRankCards = humanPlayer['collection_rank_cards'] as List<Map<String, dynamic>>? ?? [];
                collectionRankCards.add(fullCardData);
                humanPlayer['collection_rank_cards'] = collectionRankCards;
                
                // Update player's collection_rank to match the selected card's rank
                humanPlayer['collection_rank'] = fullCardData['rank']?.toString() ?? 'unknown';
                
                Logger().info('Practice: Human player never peeked - randomly selected card for collection', isOn: LOGGING_SWITCH);
              }
            }
          }
        }
        
        // Update all players to 'waiting' status and transition to player_turn phase
        final statusUpdated = updatePlayerStatus('waiting', updateMainState: false, triggerInstructions: false);
        
        if (statusUpdated) {
          Logger().info('Practice: Successfully updated players to waiting status after initial peek timer', isOn: LOGGING_SWITCH);
          
          // Update game phase to player_turn
          updatePracticeGameState({
            'playerStatus': 'waiting',
            'gamePhase': 'player_turn', // Transition to player_turn phase
            'games': _getCurrentGamesMap(),
          });
          
          // Initialize the game round for actual gameplay
          _initializeGameRound();
        } else {
          Logger().error('Practice: Failed to update players to waiting status after initial peek timer', isOn: LOGGING_SWITCH);
        }
      });
      
    } catch (e) {
      Logger().error('Practice: Failed to start initial peek timer: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Initialize the game round for actual gameplay
  void _initializeGameRound() {
    try {
      final currentGameId = _currentPracticeGameId;
      if (currentGameId == null || currentGameId.isEmpty) {
        Logger().error('Practice: No active practice game found for round initialization', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Dispose of existing round if any
      _gameRound?.dispose();
      
      // Create new game round
      _gameRound = PracticeGameRound(this, currentGameId);
      
      // Initialize the round
      _gameRound!.initializeRound();
      
      Logger().info('Practice: Game round initialized for game $currentGameId', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to initialize game round: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Handle when user manually completes initial peek phase (when instructions are enabled)
  /// This should be called when the user dismisses the instructions or completes their peek
  void completeInitialPeek() {
    try {
      // Check if initial peek has already been completed
      if (_initialPeekCompleted) {
        Logger().info('Practice: Initial peek already completed, skipping duplicate call', isOn: LOGGING_SWITCH);
        return;
      }
      
      Logger().info('Practice: User completed initial peek phase manually', isOn: LOGGING_SWITCH);
      
      // Set flag to prevent duplicate calls
      _initialPeekCompleted = true;
      
      // 1. Clear the cardsToPeek states that were updated during initial peek
      _clearCardsToPeekStates();
      
      // 2. Update all players to 'waiting' status and transition to player_turn phase
      final statusUpdated = updatePlayerStatus('waiting', updateMainState: false, triggerInstructions: false);
      
      if (statusUpdated) {
        Logger().info('Practice: Successfully updated players to waiting status after manual initial peek completion', isOn: LOGGING_SWITCH);
        
        // Update game phase to player_turn
        updatePracticeGameState({
          'playerStatus': 'waiting',
          'gamePhase': 'player_turn', // Transition to player_turn phase
          'games': _getCurrentGamesMap(),
        });
        
        // 3. Initialize the game round for actual gameplay
        _initializeGameRound();
      } else {
        Logger().error('Practice: Failed to update players to waiting status after manual initial peek completion', isOn: LOGGING_SWITCH);
      }
      
    } catch (e) {
      Logger().error('Practice: Failed to complete initial peek manually: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Clear cardsToPeek states from both player data and main state
  void _clearCardsToPeekStates() {
    try {
      Logger().info('Practice: Clearing cardsToPeek states', isOn: LOGGING_SWITCH);
      
      // 1. Clear cardsToPeek from all players in the game state
      final currentGames = _getCurrentGamesMap();
      final currentGameId = _currentPracticeGameId;
      final gameData = currentGames[currentGameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState != null) {
        final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
        for (final player in players) {
          player['cardsToPeek'] = <Map<String, dynamic>>[];
        }
        Logger().info('Practice: Cleared cardsToPeek from all players in game state', isOn: LOGGING_SWITCH);
      }
      
      // 2. Clear myCardsToPeek from main state
      final stateManager = StateManager();
      final currentState = stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final updatedState = Map<String, dynamic>.from(currentState);
      updatedState['myCardsToPeek'] = <Map<String, dynamic>>[];
      stateManager.updateModuleState('recall_game', updatedState);
      
      Logger().info('Practice: Cleared myCardsToPeek from main state', isOn: LOGGING_SWITCH);
      
    } catch (e) {
      Logger().error('Practice: Failed to clear cardsToPeek states: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Clean up practice game state when navigating away
  /// Restores actual user login from SharedPreferences
  Future<void> cleanupPracticeState() async {
    try {
      Logger().info('Practice: Cleaning up practice game state', isOn: LOGGING_SWITCH);
      
      // Check if current user is the practice user
      final loginState = _stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId']?.toString() ?? '';
      
      if (currentUserId == 'practice_user') {
        Logger().info('Practice: Restoring actual login from SharedPreferences', isOn: LOGGING_SWITCH);
        
        // Get SharedPreferences service
        final sharedPref = ServicesManager().getService<SharedPrefManager>('shared_pref');
        
        if (sharedPref != null) {
          // Restore actual user from SharedPreferences
          final isLoggedIn = sharedPref.getBool('is_logged_in') ?? false;
          final userId = sharedPref.getString('user_id');
          final username = sharedPref.getString('username');
          final email = sharedPref.getString('email');
          
          Logger().info('Practice: Restored - userId: $userId, username: $username', isOn: LOGGING_SWITCH);
          
          _stateManager.updateModuleState('login', {
            'isLoggedIn': isLoggedIn,
            'userId': userId,
            'username': username,
            'email': email,
            'error': null,
          });
        } else {
          // Fallback: clear login state
          Logger().warning('Practice: SharedPreferences not available - clearing login state', isOn: LOGGING_SWITCH);
          _stateManager.updateModuleState('login', {
            'isLoggedIn': false,
            'userId': null,
            'username': null,
            'email': null,
            'error': null,
          });
        }
      }
      
      // Clear practice game state
      _currentPracticeGameId = null;
      _isPracticeGameActive = false;
      
      // Remove practice games from state
      final recallGameState = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final games = Map<String, dynamic>.from(recallGameState['games'] as Map<String, dynamic>? ?? {});
      games.removeWhere((key, value) => key.startsWith('practice_game_'));
      
      // Clear currentGameId if it's a practice game
      final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
      if (currentGameId.startsWith('practice_game_')) {
        Logger().info('Practice: Clearing practice game as currentGameId', isOn: LOGGING_SWITCH);
        _stateManager.updateModuleState('recall_game', {
          'currentGameId': null,
          'games': games,
        });
      } else if (games.isNotEmpty) {
        _stateManager.updateModuleState('recall_game', {'games': games});
      }
      
      // Dispose game round
      _gameRound?.dispose();
      _gameRound = null;
      
      Logger().info('Practice: Cleanup completed', isOn: LOGGING_SWITCH);
    } catch (e) {
      Logger().error('Practice: Cleanup failed: $e', isOn: LOGGING_SWITCH);
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
  /// Returns a map with 'players' (dealt players) and 'remainingDeck' (cards not dealt)
  /// JOKERS ARE EXCLUDED from initial dealing but remain in the draw pile
  Map<String, dynamic> _dealCardsToPlayers(List<Map<String, dynamic>> players, List<Map<String, dynamic>> deck) {
    Logger().info('Practice: Dealing cards to ${players.length} players', isOn: LOGGING_SWITCH);
    
    // Create a DEEP copy of the deck to work with (each card is a separate object)
    final workingDeck = deck.map((card) => Map<String, dynamic>.from(card)).toList();
    
    // Step 1: Separate jokers from non-joker cards
    final jokerCards = workingDeck.where((card) => card['rank'] == 'joker').toList();
    final nonJokerCards = workingDeck.where((card) => card['rank'] != 'joker').toList();
    
    Logger().info('Practice: Separated ${jokerCards.length} jokers from ${nonJokerCards.length} non-joker cards', isOn: LOGGING_SWITCH);
    
    // Step 2: Deal 4 cards to each player from non-joker cards only
    for (final player in players) {
      final playerHand = <Map<String, dynamic>>[];
      
      // Deal 4 cards to this player from non-joker cards only
      for (int i = 0; i < 4; i++) {
        if (nonJokerCards.isNotEmpty) {
          final fullCard = nonJokerCards.removeAt(0); // Draw from non-joker cards
          
          // Convert to ID-only format for hand (matches backend _to_flutter_card with full_data=False)
          final idOnlyCard = {
            'cardId': fullCard['cardId'],
            'suit': '?',           // Face-down: hide suit
            'rank': '?',           // Face-down: hide rank  
            'points': 0,           // Face-down: hide points
            'displayName': '?',    // Face-down: hide display name
            'color': 'black',      // Default color for face-down
            'ownerId': player['id'], // Keep owner info
          };
          
          playerHand.add(idOnlyCard);
        }
      }
      
      // Update player's hand
      player['hand'] = playerHand;
      player['status'] = 'waiting'; // Set to initial peek status
      
      // Note: Instructions will be shown after main state update
      
      Logger().info('Practice: Dealt ${playerHand.length} non-joker cards to player ${player['name']}', isOn: LOGGING_SWITCH);
    }
    
    // Step 3: Combine remaining non-joker cards with jokers
    final remainingDeck = [...nonJokerCards, ...jokerCards];
    
    // Step 4: Shuffle the combined deck
    remainingDeck.shuffle();
    
    Logger().info('Practice: Card dealing complete. ${remainingDeck.length} cards remaining (including ${jokerCards.length} jokers)', isOn: LOGGING_SWITCH);
    
    // Return both the dealt players and the remaining deck (matches backend pattern)
    return {
      'players': players,
      'remainingDeck': remainingDeck,
    };
  }

  /// Set up draw and discard piles (replicating backend _setup_piles logic)
  /// Draw pile: ID-only format (face-down), Discard pile: Full data format (face-up)
  Map<String, dynamic> _setupPiles(List<Map<String, dynamic>> remainingDeck) {
    Logger().info('Practice: Setting up piles with ${remainingDeck.length} remaining cards', isOn: LOGGING_SWITCH);
    
    // Start discard pile with first card from remaining deck (full data format)
    // IMPORTANT: Remove card BEFORE creating draw pile to avoid duplicate
    final discardPile = <Map<String, dynamic>>[];
    if (remainingDeck.isNotEmpty) {
      final firstCard = remainingDeck.removeAt(0); // Remove from original deck
      discardPile.add(firstCard); // Add full card data to discard pile
      Logger().info('Practice: Moved first card ${firstCard['cardId']} to discard pile', isOn: LOGGING_SWITCH);
    }
    
    // Convert remaining deck to ID-only format for draw pile (matches backend _to_flutter_card with full_data=False)
    // Now remainingDeck no longer contains the card that went to discard pile
    final drawPile = remainingDeck.map((fullCard) => {
      'cardId': fullCard['cardId'],
      'suit': '?',           // Face-down: hide suit
      'rank': '?',           // Face-down: hide rank  
      'points': 0,           // Face-down: hide points
      'displayName': '?',    // Face-down: hide display name
      'color': 'black',      // Default color for face-down
    }).toList();
    
    Logger().info('Practice: Pile setup complete - Draw pile: ${drawPile.length} ID-only cards, Discard pile: ${discardPile.length} full-data cards', isOn: LOGGING_SWITCH);
    
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
        'isHuman': true, // Add isHuman field for practice game detection
        'hand': <Map<String, dynamic>>[], // Will be filled when cards are dealt
        'visibleCards': <Map<String, dynamic>>[],
        'cardsToPeek': <Map<String, dynamic>>[],
        'score': 0,
        'status': 'waiting',
        'isCurrentPlayer': false,
        'hasCalledRecall': false,
        'drawnCard': null,
        'isActive': true,
        // AI knowledge tracking - key: playerId, value: card data
        'known_cards': <String, dynamic>{},
        // Collection rank for AI strategy
        'collection_rank': 'human',
        // Collection rank cards - list of full card data this player considers collection rank
        'collection_rank_cards': <Map<String, dynamic>>[],
      };
      
      // Combine all players
      final allPlayers = [humanPlayer, ...computerPlayers];
      
      // Create deck for the game
      final deck = await _createDeck(gameId);
      
      // Deal cards to players (replicating backend _deal_cards logic)
      // Returns both players and remaining deck after dealing
      final dealResult = _dealCardsToPlayers(allPlayers, deck);
      final dealtPlayers = dealResult['players'] as List<Map<String, dynamic>>;
      final remainingDeck = dealResult['remainingDeck'] as List<Map<String, dynamic>>;
      
      // Set up draw and discard piles using REMAINING deck after dealing (replicating backend _setup_piles logic)
      final pileSetup = _setupPiles(remainingDeck);
      
      // Initialize game state properties (replicating backend GameState.__init__)
      final gameState = {
        // Core Game Properties
        'gameId': gameId,
        'gameName': 'Practice Recall Game $gameId',
        'maxPlayers': maxPlayers,
        'minPlayers': minPlayers,
        'permission': permission,
        'gameType': gameType, // Store game type for RecallGameStateAccessor
        
        // Store original deck for card reconstruction (needed for _getCardById)
        'originalDeck': deck, // Full card data for reconstruction
        
        // Player Management
        'players': dealtPlayers,
        'currentPlayer': null, // Will be set by _startNextTurn() during round initialization
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
        'turnTimeLimit': turnTimeLimit, // Store turn time limit in game state for PracticeGameRound access
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

  /// Public getter for current games map (used by PracticeGameRound)
  Map<String, dynamic> get currentGamesMap => _getCurrentGamesMap();

  /// Update player status for a specific player or all players
  /// 
  /// [status] The new status to set
  /// [playerId] Optional player ID. If null, updates all players
  /// [updateMainState] Whether to also update the main game state playerStatus
  /// [triggerInstructions] Whether to trigger contextual instructions after status update (respects _instructionsEnabled)
  /// 
  /// Returns true if successful, false otherwise
  bool updatePlayerStatus(String status, {String? playerId, bool updateMainState = true, bool triggerInstructions = false}) {
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
        // Get the current player from game state
        final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
        final isCurrentPlayerHuman = currentPlayer?['id'] == 'practice_user';
        
        if (playerId == 'practice_user') {
          // Updating human player status - also update myDrawnCard if it exists
          final humanPlayer = players.firstWhere(
            (p) => p['id'] == 'practice_user',
            orElse: () => <String, dynamic>{},
          );
          final drawnCard = humanPlayer['drawnCard'] as Map<String, dynamic>?;
          
          // Also update the games map with the drawn card (same as backend)
          final currentGame = currentGames[currentGameId] as Map<String, dynamic>? ?? {};
          currentGame['myDrawnCard'] = drawnCard;
          
          updatePracticeGameState({
            'playerStatus': status,
            'games': currentGames,
            'isMyTurn': isCurrentPlayerHuman, // Update isMyTurn based on current player
            'myDrawnCard': drawnCard, // Update myDrawnCard so frontend can show the drawn card
          });
        } else if (playerId != null) {
          // For non-human players, update the games map and currentPlayer/currentPlayerStatus
          Logger().info('Practice: Updating games state for non-human player $playerId with status: $status', isOn: LOGGING_SWITCH);
          
          updatePracticeGameState({
            'games': currentGames,
            'currentPlayer': currentPlayer,
            'currentPlayerStatus': status,
            'isMyTurn': isCurrentPlayerHuman, // Update isMyTurn based on current player
          });
          Logger().info('Practice: Games state updated for non-human player - opponentsPanel should be recomputed', isOn: LOGGING_SWITCH);
        } else {
          // Update ALL players (playerId == null)
          // This is used for cases like same_rank_window where all players get the same status
          // We need to update both human player status AND current player status for widgets
          Logger().info('Practice: Updating main state for ALL players with status: $status', isOn: LOGGING_SWITCH);
          
          updatePracticeGameState({
            'playerStatus': status, // Human player status for MyHandWidget
            'games': currentGames, // Updated games map with all players' statuses
            'currentPlayer': currentPlayer, // For OpponentsPanel
            'currentPlayerStatus': status, // Current player's status for OpponentsPanel
            'isMyTurn': isCurrentPlayerHuman, // Keep isMyTurn consistent
          });
          Logger().info('Practice: Main state updated for all players - all widgets should reflect new status', isOn: LOGGING_SWITCH);
        }
      }
      
      // Trigger contextual instructions if requested (respects _instructionsEnabled setting)
      if (triggerInstructions && _instructionsEnabled) {
        showContextualInstructions();
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
        'isHuman': false, // Add isHuman field for practice game detection
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
        // AI knowledge tracking - key: playerId, value: card data
        'known_cards': <String, dynamic>{},
        // Collection rank for AI strategy
        'collection_rank': 'medium',
        // Collection rank cards - list of full card data this player considers collection rank
        'collection_rank_cards': <Map<String, dynamic>>[],
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
        case 'completed_initial_peek':
          return await _handleCompletedInitialPeek(sessionId, data);
        case 'draw_card':
          return await _handleDrawCard(sessionId, data);
        case 'play_card':
          return await _handlePlayCard(sessionId, data);
      case 'same_rank_play':
        return await _handleSameRankPlay(sessionId, data);
      case 'jack_swap':
        return await _handleJackSwap(sessionId, data);
      case 'queen_peek':
        return await _handleQueenPeek(sessionId, data);
      case 'collect_from_discard':
        return await _handleCollectFromDiscard(sessionId, data);
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
      
      // Reset initial peek completion flag for new game
      _initialPeekCompleted = false;
      
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

  /// Process AI initial peeks - select 2 random cards and store in known_cards
  void _processAIInitialPeeks() {
    try {
      final currentGames = _getCurrentGamesMap();
      final gameId = _currentPracticeGameId;
      if (gameId == null || !currentGames.containsKey(gameId)) return;
      
      final gameData = currentGames[gameId];
      final gameState = gameData?['gameData']?['game_state'] as Map<String, dynamic>?;
      if (gameState == null) return;
      
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      
      // Process each computer player
      for (final player in players) {
        if (player['isHuman'] != true) {
          _selectAndStoreAIPeekCards(player);
        }
      }
      
      // Update state with modified players
      updatePracticeGameState({'games': currentGames});
      
    } catch (e) {
      Logger().error('Practice: Failed to process AI initial peeks: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Select and store AI peek cards for a computer player
  void _selectAndStoreAIPeekCards(Map<String, dynamic> computerPlayer) {
    final hand = computerPlayer['hand'] as List<Map<String, dynamic>>? ?? [];
    if (hand.length < 2) return;
    
    // Select 2 random cards
    final random = Random();
    final indices = <int>[];
    while (indices.length < 2) {
      final idx = random.nextInt(hand.length);
      if (!indices.contains(idx)) indices.add(idx);
    }
    
    // Get the computer player's ID
    final playerId = computerPlayer['id'] as String;
    
    // Store selected cards in known_cards (key: own playerId, value: card IDs only)
    final knownCards = computerPlayer['known_cards'] as Map<String, dynamic>? ?? {};
    knownCards[playerId] = {
      'card1': hand[indices[0]]['cardId'],
      'card2': hand[indices[1]]['cardId'],
    };
    computerPlayer['known_cards'] = knownCards;
    
    // AI Decision Logic: Determine which card should be marked as collection rank
    final card1 = hand[indices[0]];
    final card2 = hand[indices[1]];
    final selectedCardForCollection = _selectCardForCollection(card1, card2, random);
    
    // Get full card data using getCardById (same pattern as queen peek)
    final currentGames = _getCurrentGamesMap();
    final gameId = _currentPracticeGameId;
    final gameData = currentGames[gameId];
    final gameState = gameData?['gameData']?['game_state'] as Map<String, dynamic>?;
    final fullCardData = getCardById(gameState!, selectedCardForCollection['cardId'] as String);
    if (fullCardData == null) {
      Logger().error('Practice: Failed to get full card data for collection rank card ${selectedCardForCollection['cardId']}', isOn: LOGGING_SWITCH);
      return;
    }
    
    // Add the selected card full data to the player's collection_rank_cards list
    final collectionRankCards = computerPlayer['collection_rank_cards'] as List<Map<String, dynamic>>? ?? [];
    collectionRankCards.add(fullCardData); // Use full card data, not just the selected card
    computerPlayer['collection_rank_cards'] = collectionRankCards;
    
    Logger().info('Practice: AI ${computerPlayer['name']} peeked at cards at positions $indices', isOn: LOGGING_SWITCH);
    Logger().info('Practice: AI ${computerPlayer['name']} selected ${selectedCardForCollection['rank']} of ${selectedCardForCollection['suit']} for collection (${selectedCardForCollection['points']} points)', isOn: LOGGING_SWITCH);
    
    // CRITICAL: Trigger immediate state update for this player (like backend's player_state_updated)
    // This ensures OpponentsPanel rebuilds and shows collection rank cards with purple borders
    
    updatePracticeGameState({
      'games': currentGames, // Updated games map with this player's known_cards and collection_rank_cards
    });
    Logger().info('Practice: Triggered state update for AI ${computerPlayer['name']} known_cards and collection rank cards', isOn: LOGGING_SWITCH);
  }

  /// AI Decision Logic: Select which card should be marked as collection rank
  /// Priority: Least points first, then by rank order (ace, number, king, queen, jack)
  Map<String, dynamic> _selectCardForCollection(Map<String, dynamic> card1, Map<String, dynamic> card2, Random random) {
    final points1 = card1['points'] as int? ?? 0;
    final points2 = card2['points'] as int? ?? 0;
    final rank1 = card1['rank'] as String? ?? '';
    final rank2 = card2['rank'] as String? ?? '';
    
    // If points are different, select the one with least points
    if (points1 != points2) {
      return points1 < points2 ? card1 : card2;
    }
    
    // If points are the same, use priority order: ace, number, king, queen, jack
    final priority1 = _getCardPriority(rank1);
    final priority2 = _getCardPriority(rank2);
    
    if (priority1 != priority2) {
      return priority1 < priority2 ? card1 : card2;
    }
    
    // If both cards have same rank, random pick
    return random.nextBool() ? card1 : card2;
  }

  /// Get priority value for card rank (lower = higher priority)
  int _getCardPriority(String rank) {
    switch (rank) {
      case 'ace':
        return 1; // Highest priority
      case '2': case '3': case '4': case '5': case '6': case '7': case '8': case '9': case '10':
        return 2; // Numbers
      case 'king':
        return 3; // Kings
      case 'queen':
        return 4; // Queens
      case 'jack':
        return 5; // Jacks (lowest priority)
      default:
        return 6; // Unknown ranks (lowest)
    }
  }

  /// Handle the completed_initial_peek event from practice room
  /// Replicates backend on_completed_initial_peek logic exactly
  Future<bool> _handleCompletedInitialPeek(String sessionId, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Handling completed initial peek with data: $data', isOn: LOGGING_SWITCH);
      
      // 1. Extract game_id and card_ids from payload (same as backend)
      final gameId = data['game_id'] as String?;
      final cardIds = (data['card_ids'] as List<dynamic>?)?.cast<String>() ?? [];
      
      if (gameId == null || gameId.isEmpty) {
        Logger().error('Practice: Missing game_id in completed_initial_peek data', isOn: LOGGING_SWITCH);
        return false;
      }
      
      if (cardIds.length != 2) {
        Logger().error('Practice: Invalid card_ids: $cardIds. Expected exactly 2 card IDs.', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // 2. Get current game state
      final currentGames = _getCurrentGamesMap();
      if (!currentGames.containsKey(gameId)) {
        Logger().error('Practice: Game $gameId not found for completed_initial_peek', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final gameData = currentGames[gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for completed_initial_peek', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // 3. Get the human player (practice user)
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      Logger().info('Practice: Available players for completed_initial_peek: ${players.map((p) => '${p['name']} (isHuman: ${p['isHuman']})').join(', ')}', isOn: LOGGING_SWITCH);
      
      final humanPlayer = players.firstWhere(
        (p) => p['isHuman'] == true,
        orElse: () => <String, dynamic>{},
      );
      
      if (humanPlayer.isEmpty) {
        Logger().error('Practice: Human player not found for completed_initial_peek', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Human player ${humanPlayer['name']} peeked at cards: $cardIds', isOn: LOGGING_SWITCH);
      
      // 4. Clear any existing cards from previous peeks (same as backend)
      humanPlayer['cardsToPeek'] = <Map<String, dynamic>>[];
      Logger().info('Practice: Cleared existing cards_to_peek for human player', isOn: LOGGING_SWITCH);
      
      // 5. For each card ID, find the full card data and add to cards_to_peek (same as backend)
      int cardsUpdated = 0;
      final cardsToPeek = <Map<String, dynamic>>[];
      
      for (final cardId in cardIds) {
        // Find the full card data using get_card_by_id equivalent
        final cardData = getCardById(gameState, cardId);
        if (cardData == null) {
          Logger().error('Practice: Card $cardId not found in game', isOn: LOGGING_SWITCH);
          continue;
        }
        
        // Add the card to the cards_to_peek list (same as backend add_card_to_peek)
        cardsToPeek.add(cardData);
        cardsUpdated++;
        Logger().info('Practice: Added card $cardId to human player\'s cards_to_peek list', isOn: LOGGING_SWITCH);
      }
      
      if (cardsUpdated != 2) {
        Logger().warning('Practice: Only added $cardsUpdated out of 2 cards to cards_to_peek', isOn: LOGGING_SWITCH);
      }
      
      // 6. Update the player's cards_to_peek with full card data
      humanPlayer['cardsToPeek'] = cardsToPeek;
      
      // 6.5. Store peeked cards in known_cards (same structure as AI players - ID-only format)
      final humanKnownCards = humanPlayer['known_cards'] as Map<String, dynamic>? ?? {};
      humanKnownCards[humanPlayer['id'] as String] = {
        'card1': cardsToPeek[0]['cardId'],
        'card2': cardsToPeek.length > 1 ? cardsToPeek[1]['cardId'] : cardsToPeek[0]['cardId'],
      };
      humanPlayer['known_cards'] = humanKnownCards;
      
      Logger().info('Practice: Human player peeked at $cardsUpdated cards: $cardIds', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Human player stored ${cardsToPeek.length} cards in known_cards', isOn: LOGGING_SWITCH);
      
      // 6.7. Auto-select collection rank card for human player (same logic as AI)
      final selectedCardForCollection = _selectCardForCollection(cardsToPeek[0], cardsToPeek[1], Random());
      
      // Get full card data using getCardById
      final fullCardData = getCardById(gameState, selectedCardForCollection['cardId'] as String);
      if (fullCardData != null) {
        final collectionRankCards = humanPlayer['collection_rank_cards'] as List<Map<String, dynamic>>? ?? [];
        collectionRankCards.add(fullCardData);
        humanPlayer['collection_rank_cards'] = collectionRankCards;
        
        // Update player's collection_rank to match the selected card's rank
        humanPlayer['collection_rank'] = selectedCardForCollection['rank']?.toString() ?? 'unknown';
        
        Logger().info('Practice: Human player selected ${selectedCardForCollection['rank']} of ${selectedCardForCollection['suit']} for collection (${selectedCardForCollection['points']} points)', isOn: LOGGING_SWITCH);
      } else {
        Logger().error('Practice: Failed to get full card data for human collection rank card', isOn: LOGGING_SWITCH);
      }
      
      // 7. Update the main state's myCardsToPeek field (same as backend does via event handler)
      final stateManager = StateManager();
      final currentState = stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final updatedState = Map<String, dynamic>.from(currentState);
      updatedState['myCardsToPeek'] = cardsToPeek;
      stateManager.updateModuleState('recall_game', updatedState);
      
      Logger().info('Practice: Updated main state myCardsToPeek with ${cardsToPeek.length} cards', isOn: LOGGING_SWITCH);
      
      // 8. Set player status to WAITING (same as backend)
      final statusUpdated = updatePlayerStatus('waiting', playerId: humanPlayer['id'], updateMainState: true);
      if (!statusUpdated) {
        Logger().error('Practice: Failed to update human player status to waiting', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Completed initial peek - human player set to WAITING status', isOn: LOGGING_SWITCH);
      
      // 9. Wait 5 seconds then trigger completeInitialPeek to clear states and initialize round
      Timer(Duration(seconds: 5), () {
        Logger().info('Practice: 5-second delay completed, triggering completeInitialPeek', isOn: LOGGING_SWITCH);
        completeInitialPeek();
      });
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Failed to handle completed initial peek: $e', isOn: LOGGING_SWITCH);
    return false;
    }
  }

  /// Handle the draw_card event from practice room
  Future<bool> _handleDrawCard(String sessionId, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Handling draw_card event with data: $data', isOn: LOGGING_SWITCH);
      
      // Extract data from the event
      final gameId = data['game_id']?.toString() ?? '';
      final source = data['source']?.toString() ?? 'deck'; // 'deck' or 'discard'
      
      if (gameId.isEmpty) {
        Logger().error('Practice: No game_id provided for draw_card event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Validate source
      if (source != 'deck' && source != 'discard') {
        Logger().error('Practice: Invalid source for draw_card: $source', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get current games map
      final currentGames = _getCurrentGamesMap();
      if (!currentGames.containsKey(gameId)) {
        Logger().error('Practice: Game $gameId not found for draw_card event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the game state
      final gameData = currentGames[gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for draw_card event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get the current player (should be the human player for practice games)
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        Logger().error('Practice: No current player found for draw_card event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? '';
      if (playerId != 'practice_user') {
        Logger().error('Practice: Current player is not the human player for draw_card event: $playerId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Check if player status is 'drawing_card'
      final playerStatus = currentPlayer['status']?.toString() ?? '';
      if (playerStatus != 'drawing_card') {
        Logger().error('Practice: Player status is not drawing_card for draw_card event: $playerStatus', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Validating draw_card for player $playerId from $source pile', isOn: LOGGING_SWITCH);
      
      // Route to PracticeGameRound for actual draw logic
      if (_gameRound != null) {
        final success = await _gameRound!.handleDrawCard(source);
        if (success) {
          Logger().info('Practice: Successfully handled draw_card from $source pile', isOn: LOGGING_SWITCH);
          return true;
        } else {
          Logger().error('Practice: Failed to handle draw_card in PracticeGameRound', isOn: LOGGING_SWITCH);
          return false;
        }
      } else {
        Logger().error('Practice: No game round available for draw_card event', isOn: LOGGING_SWITCH);
        return false;
      }
      
    } catch (e) {
      Logger().error('Practice: Failed to handle draw_card event: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle the play_card event from practice room
  Future<bool> _handlePlayCard(String sessionId, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Handling play_card event with data: $data', isOn: LOGGING_SWITCH);
      
      // Validate required data
      final cardId = data['card_id']?.toString();
      if (cardId == null || cardId.isEmpty) {
        Logger().error('Practice: Missing card_id in play_card event data', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Validate current player and status
      final currentGames = _getCurrentGamesMap();
      final currentGameId = _currentPracticeGameId;
      
      if (currentGameId == null || currentGameId.isEmpty || !currentGames.containsKey(currentGameId)) {
        Logger().error('Practice: No active practice game found for play_card event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final gameData = currentGames[currentGameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for play_card event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      if (currentPlayer == null) {
        Logger().error('Practice: No current player found for play_card event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final playerId = currentPlayer['id']?.toString() ?? '';
      if (playerId != 'practice_user') {
        Logger().error('Practice: Current player is not the human player for play_card event: $playerId', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Check if player status is 'playing_card'
      final playerStatus = currentPlayer['status']?.toString() ?? '';
      if (playerStatus != 'playing_card') {
        Logger().error('Practice: Player status is not playing_card for play_card event: $playerStatus', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Validating play_card for player $playerId with card $cardId', isOn: LOGGING_SWITCH);
      
      // Route to PracticeGameRound for actual play card logic
      if (_gameRound != null) {
        final success = await _gameRound!.handlePlayCard(cardId);
        if (success) {
          Logger().info('Practice: Successfully handled play_card for card $cardId', isOn: LOGGING_SWITCH);
          return true;
        } else {
          Logger().error('Practice: Failed to handle play_card in PracticeGameRound', isOn: LOGGING_SWITCH);
          return false;
        }
      } else {
        Logger().error('Practice: No game round available for play_card event', isOn: LOGGING_SWITCH);
        return false;
      }
      
    } catch (e) {
      Logger().error('Practice: Failed to handle play_card event: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle same rank play event - player plays a matching rank card during same_rank_window
  Future<bool> _handleSameRankPlay(String sessionId, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Handling same_rank_play event with data: $data', isOn: LOGGING_SWITCH);
      
      // Validate required data
      final cardId = data['card_id']?.toString();
      if (cardId == null || cardId.isEmpty) {
        Logger().error('Practice: Missing card_id in same_rank_play event data', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get current game state
      final currentGames = _getCurrentGamesMap();
      final currentGameId = _currentPracticeGameId;
      
      if (currentGameId == null || currentGameId.isEmpty || !currentGames.containsKey(currentGameId)) {
        Logger().error('Practice: No active practice game found for same_rank_play event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final gameData = currentGames[currentGameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null for same_rank_play event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Check if player status is 'same_rank_window'
      // For same rank play, any player can play if they are in same_rank_window status
      final players = gameState['players'] as List<Map<String, dynamic>>? ?? [];
      final humanPlayer = players.firstWhere(
        (p) => p['id'] == 'practice_user',
        orElse: () => <String, dynamic>{},
      );
      
      if (humanPlayer.isEmpty) {
        Logger().error('Practice: Human player not found for same_rank_play event', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final playerStatus = humanPlayer['status']?.toString() ?? '';
      if (playerStatus != 'same_rank_window') {
        Logger().error('Practice: Player status is not same_rank_window for same_rank_play event: $playerStatus', isOn: LOGGING_SWITCH);
        return false;
      }
      
      Logger().info('Practice: Validating same_rank_play for player practice_user with card $cardId', isOn: LOGGING_SWITCH);
      
      // Route to PracticeGameRound for actual same rank play logic
      if (_gameRound != null) {
        final success = await _gameRound!.handleSameRankPlay('practice_user', cardId);
        if (success) {
          Logger().info('Practice: Successfully handled same_rank_play for card $cardId', isOn: LOGGING_SWITCH);
          return true;
        } else {
          Logger().error('Practice: Failed to handle same_rank_play in PracticeGameRound', isOn: LOGGING_SWITCH);
          return false;
        }
      } else {
        Logger().error('Practice: No game round available for same_rank_play event', isOn: LOGGING_SWITCH);
        return false;
      }
      
    } catch (e) {
      Logger().error('Practice: Failed to handle same_rank_play event: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle collect_from_discard event - player collecting card from discard if it matches collection rank
  Future<bool> _handleCollectFromDiscard(String sessionId, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Handling collect_from_discard event', isOn: LOGGING_SWITCH);
      
      // Get current game ID
      final gameId = data['game_id']?.toString() ?? '';
      if (gameId.isEmpty) {
        Logger().error('Practice: No game_id provided for collect_from_discard', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Get game state
      final currentGames = _getCurrentGamesMap();
      if (!currentGames.containsKey(gameId)) {
        Logger().error('Practice: Game $gameId not found', isOn: LOGGING_SWITCH);
        return false;
      }
      
      final gameData = currentGames[gameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        Logger().error('Practice: Game state is null', isOn: LOGGING_SWITCH);
        return false;
      }
      
      // Route to practice game round handler
      if (_gameRound != null) {
        return await _gameRound!.handleCollectFromDiscard('practice_user');
      } else {
        Logger().error('Practice: No game round available', isOn: LOGGING_SWITCH);
        return false;
      }
      
    } catch (e) {
      Logger().error('Practice: Failed to handle collect_from_discard: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle Jack swap event - swap two cards between players
  Future<bool> _handleJackSwap(String sessionId, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Handling jack_swap event with data: $data', isOn: LOGGING_SWITCH);

      // Validate required data
      final firstCardId = data['first_card_id']?.toString();
      final firstPlayerId = data['first_player_id']?.toString();
      final secondCardId = data['second_card_id']?.toString();
      final secondPlayerId = data['second_player_id']?.toString();

      if (firstCardId == null || firstCardId.isEmpty ||
          firstPlayerId == null || firstPlayerId.isEmpty ||
          secondCardId == null || secondCardId.isEmpty ||
          secondPlayerId == null || secondPlayerId.isEmpty) {
        Logger().error('Practice: Invalid Jack swap data - missing required fields', isOn: LOGGING_SWITCH);
        return false;
      }

      // Get current game state
      final currentGames = _getCurrentGamesMap();
      final currentGameId = _currentPracticeGameId;

      if (currentGameId == null || currentGameId.isEmpty || !currentGames.containsKey(currentGameId)) {
        Logger().error('Practice: No active practice game found for jack_swap event', isOn: LOGGING_SWITCH);
        return false;
      }

      final gameData = currentGames[currentGameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;

      if (gameState == null) {
        Logger().error('Practice: Game state is null for jack_swap event', isOn: LOGGING_SWITCH);
        return false;
      }

      Logger().info('Practice: Validating jack_swap for cards: $firstCardId (player $firstPlayerId) <-> $secondCardId (player $secondPlayerId)', isOn: LOGGING_SWITCH);

      // Route to PracticeGameRound for actual jack swap logic
      if (_gameRound != null) {
        final success = await _gameRound!.handleJackSwap(
          firstCardId: firstCardId,
          firstPlayerId: firstPlayerId,
          secondCardId: secondCardId,
          secondPlayerId: secondPlayerId,
        );
        if (success) {
          Logger().info('Practice: Successfully handled jack_swap', isOn: LOGGING_SWITCH);
          return true;
        } else {
          Logger().error('Practice: Failed to handle jack_swap in PracticeGameRound', isOn: LOGGING_SWITCH);
          return false;
        }
      } else {
        Logger().error('Practice: No game round available for jack_swap event', isOn: LOGGING_SWITCH);
        return false;
      }

    } catch (e) {
      Logger().error('Practice: Failed to handle jack_swap event: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Handle Queen peek event - peek at any one card from any player
  /// Replicates backend's _handle_queen_peek method in game_round.py lines 1267-1318
  Future<bool> _handleQueenPeek(String sessionId, Map<String, dynamic> data) async {
    try {
      Logger().info('Practice: Handling queen_peek event with data: $data', isOn: LOGGING_SWITCH);

      // Extract data from action (matches backend field names)
      final cardId = data['card_id']?.toString();
      final ownerId = data['ownerId']?.toString(); // Note: using ownerId as per frontend

      if (cardId == null || cardId.isEmpty || ownerId == null || ownerId.isEmpty) {
        Logger().error('Practice: Invalid Queen peek data - missing required fields: card_id=$cardId, ownerId=$ownerId', isOn: LOGGING_SWITCH);
        return false;
      }

      // Get current game state
      final currentGames = _getCurrentGamesMap();
      final currentGameId = _currentPracticeGameId;

      if (currentGameId == null || currentGameId.isEmpty || !currentGames.containsKey(currentGameId)) {
        Logger().error('Practice: No active practice game found for queen_peek event', isOn: LOGGING_SWITCH);
        return false;
      }

      final gameData = currentGames[currentGameId];
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;

      if (gameState == null) {
        Logger().error('Practice: Game state is null for queen_peek event', isOn: LOGGING_SWITCH);
        return false;
      }

      Logger().info('Practice: Validating queen_peek for card $cardId from player $ownerId', isOn: LOGGING_SWITCH);

      // Route to PracticeGameRound for actual queen peek logic
      if (_gameRound != null) {
        // Find the current player (the one doing the peek)
        final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
        final currentPlayerId = currentPlayer?['id']?.toString() ?? 'practice_user';
        
        final success = await _gameRound!.handleQueenPeek(
          peekingPlayerId: currentPlayerId,
          targetCardId: cardId,
          targetPlayerId: ownerId,
        );
        if (success) {
          Logger().info('Practice: Successfully handled queen_peek', isOn: LOGGING_SWITCH);
          return true;
        } else {
          Logger().error('Practice: Failed to handle queen_peek in PracticeGameRound', isOn: LOGGING_SWITCH);
          return false;
        }
      } else {
        Logger().error('Practice: No game round available for queen_peek event', isOn: LOGGING_SWITCH);
        return false;
      }

    } catch (e) {
      Logger().error('Practice: Failed to handle queen_peek event: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }

  /// Find a card by its ID anywhere in the game (replicates backend get_card_by_id)
  /// Searches through all game locations: player hands, draw pile, discard pile
  /// Reconstructs full card data from original deck when needed
  Map<String, dynamic>? getCardById(Map<String, dynamic> gameState, String cardId) {
    try {
      // Search in discard pile first (has full data)
      final discardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      for (final card in discardPile) {
        if (card['cardId'] == cardId) {
          return card; // Return full card data
        }
      }
      
      // Search in original deck to reconstruct full card data
      final originalDeck = gameState['originalDeck'] as List<Map<String, dynamic>>? ?? [];
      for (final card in originalDeck) {
        if (card['cardId'] == cardId) {
          return card; // Return full card data from original deck
        }
      }
      
      // Card not found anywhere
      Logger().warning('Practice: Card $cardId not found in any game location', isOn: LOGGING_SWITCH);
      return null;
      
    } catch (e) {
      Logger().error('Practice: Error searching for card $cardId: $e', isOn: LOGGING_SWITCH);
      return null;
    }
  }

  /// Add card to discard pile with full data (reusable method)
  /// This ensures the card is added with complete card information for display
  bool addToDiscardPile(Map<String, dynamic> card) {
    try {
      final currentGames = _getCurrentGamesMap();
      final currentGameId = _currentPracticeGameId;

      if (currentGameId == null || currentGameId.isEmpty || !currentGames.containsKey(currentGameId)) {
        Logger().error('Practice: No active practice game found for addToDiscardPile', isOn: LOGGING_SWITCH);
        return false;
      }

      final gameData = currentGames[currentGameId]['gameData'] as Map<String, dynamic>?;
      final gameState = gameData?['game_state'] as Map<String, dynamic>?;

      if (gameState == null) {
        Logger().error('Practice: Game state is null for addToDiscardPile', isOn: LOGGING_SWITCH);
        return false;
      }

      // Get current discard pile WITHOUT modifying it (to ensure change detection works)
      final currentDiscardPile = gameState['discardPile'] as List<Map<String, dynamic>>? ?? [];
      
      // Create NEW discard pile with the added card (don't modify the original!)
      final newDiscardPile = List<Map<String, dynamic>>.from(currentDiscardPile)..add(card);

      Logger().info('Practice: Added card ${card['cardId']} to discard pile with full data', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Discard pile now has ${newDiscardPile.length} cards', isOn: LOGGING_SWITCH);

      // Create a DEEP copy of the games map to ensure change detection works properly
      // This is critical because the state manager needs to detect that the 'games' field has changed
      // A shallow copy would keep references to nested objects, preventing change detection
      final updatedGames = Map<String, dynamic>.from(currentGames);
      final updatedCurrentGame = Map<String, dynamic>.from(updatedGames[currentGameId] as Map<String, dynamic>);
      final updatedGameData = Map<String, dynamic>.from(updatedCurrentGame['gameData'] as Map<String, dynamic>);
      final updatedGameState = Map<String, dynamic>.from(updatedGameData['game_state'] as Map<String, dynamic>);

      // Update the discard pile in the deep-copied game state with the NEW list
      updatedGameState['discardPile'] = newDiscardPile;

      // Reassemble the structure with new references
      updatedGameData['game_state'] = updatedGameState;
      updatedCurrentGame['gameData'] = updatedGameData;
      updatedGames[currentGameId] = updatedCurrentGame;
      
      // Debug: Log the discard pile contents before state update
      Logger().info('Practice: Discard pile contents before state update: ${newDiscardPile.map((c) => c['cardId']).toList()}', isOn: LOGGING_SWITCH);
      
      // Simulate what the backend's _send_game_state_partial_update does for discard_pile changes
      // This replicates the frontend's handleGameStatePartialUpdate logic for discard_pile (lines 571-574)
      // The backend sends BOTH:
      // 1. The updated discardPile in the games map (for centerBoard slice computation)
      // 2. The discardPile in the main state (for direct access)
      
      Logger().info('Practice: === DISCARD PILE STATE UPDATE DEBUG ===', isOn: LOGGING_SWITCH);
      Logger().info('Practice: New discard pile length: ${newDiscardPile.length}', isOn: LOGGING_SWITCH);
      Logger().info('Practice: New discard pile cards: ${newDiscardPile.map((c) => '${c['cardId']}: ${c['rank']} of ${c['suit']}').toList()}', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Updating games map with new structure', isOn: LOGGING_SWITCH);
      Logger().info('Practice: Updating main state discardPile field', isOn: LOGGING_SWITCH);
      
      updatePracticeGameState({
        'games': updatedGames,
        'discardPile': newDiscardPile,  // CRITICAL: Also update main state discardPile like the backend does
      });
      
      Logger().info('Practice: State update triggered for discard pile change (simulating backend partial update)', isOn: LOGGING_SWITCH);
      Logger().info('Practice: ========================================', isOn: LOGGING_SWITCH);

      return true;

    } catch (e) {
      Logger().error('Practice: Failed to add card to discard pile: $e', isOn: LOGGING_SWITCH);
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
      // Note: We update main state separately to include game phase
      final statusUpdated = updatePlayerStatus('initial_peek', updateMainState: false, triggerInstructions: false);
      if (!statusUpdated) {
        return false;
      }
      
      // Update the main game state with game phase
      // Set phase to initial_peek during initial peek phase
      updatePracticeGameState({
        'playerStatus': 'initial_peek',
        'gamePhase': 'initial_peek', // Use the new initial_peek phase
        'games': _getCurrentGamesMap(), // Update the games map with modified players
      });
      
      // CRITICAL: Process AI initial peeks BEFORE instructions/timer
      // AI players must select their collection rank cards regardless of instruction mode
      _processAIInitialPeeks();
      
      // Trigger contextual instructions or start timer after state is fully updated
      // (respects _instructionsEnabled setting from practice room)
      if (_instructionsEnabled) {
        showContextualInstructions();
        // Note: Round will be initialized when user manually completes initial peek
      } else {
        // Start non-disruptive 10-second timer for initial peek phase
        _startInitialPeekTimer();
      }
      
      Logger().info('Practice: Match started - all players set to initial_peek', isOn: LOGGING_SWITCH);
      
      return true;
      
    } catch (e) {
      Logger().error('Practice: Failed to start match via matchStart: $e', isOn: LOGGING_SWITCH);
      return false;
    }
  }
}
