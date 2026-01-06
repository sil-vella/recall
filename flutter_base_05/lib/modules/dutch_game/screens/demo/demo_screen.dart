import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../game_play/widgets/game_info_widget.dart';
import '../game_play/widgets/unified_game_board_widget.dart';
import '../game_play/widgets/instructions_widget.dart';
import '../game_play/widgets/messages_widget.dart';
import '../game_play/widgets/card_animation_layer.dart';
import 'demo_instructions_widget.dart';
import 'select_cards_prompt_widget.dart';
import '../../managers/dutch_game_state_updater.dart';
import '../../managers/validated_event_emitter.dart';

class DemoScreen extends BaseScreen {
  const DemoScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Dutch Game Demo';

  @override
  Decoration? getBackground(BuildContext context) {
    return BoxDecoration(
      color: AppColors.pokerTableGreen,
    );
  }

  @override
  DemoScreenState createState() => DemoScreenState();
}

class DemoScreenState extends BaseScreenState<DemoScreen> {
  // GlobalKey for the main Stack to get exact position for animations
  final GlobalKey _mainStackKey = GlobalKey();
  // Store demo mode - will be used for future functionality
  bool _isClearAndCollect = false;
  // Track if a demo mode has been selected
  bool _modeSelected = false;
  // Logger for demo operations
  final Logger _logger = Logger();
  static const bool LOGGING_SWITCH = true; // Enabled for demo debugging
  
  // Local demo state (all state managed locally, not via StateManager)
  String? _demoGameId;
  List<Map<String, dynamic>> _players = [];
  List<Map<String, dynamic>> _drawPile = [];
  List<Map<String, dynamic>> _discardPile = [];
  List<Map<String, dynamic>> _originalDeck = [];
  Map<String, dynamic>? _currentPlayer;
  String _gamePhase = 'waiting';
  int _roundNumber = 1;
  int _turnNumber = 1;

  @override
  void initState() {
    super.initState();
    // No WebSocket, state management, or feature registration needed for demo
    // Default to regular mode
    _isClearAndCollect = false;
    _modeSelected = false;
  }

  @override
  void dispose() {
    // Clean up demo state when leaving
    _cleanupDemoState();
    super.dispose();
  }
  
  /// Get predefined cards for demo (manually created, no deck factory)
  List<Map<String, dynamic>> _getPredefinedCards() {
    // Create a simple set of predefined cards for demo
    // Using a mix of ranks and suits for variety
    final cards = <Map<String, dynamic>>[];
    final suits = ['hearts', 'diamonds', 'clubs', 'spades'];
    final ranks = [
      {'rank': 'ace', 'points': 1},
      {'rank': '2', 'points': 2},
      {'rank': '3', 'points': 3},
      {'rank': '4', 'points': 4},
      {'rank': '5', 'points': 5},
      {'rank': '6', 'points': 6},
      {'rank': '7', 'points': 7},
      {'rank': '8', 'points': 8},
      {'rank': '9', 'points': 9},
      {'rank': '10', 'points': 10},
      {'rank': 'jack', 'points': 10, 'specialPower': 'switch_cards'},
      {'rank': 'queen', 'points': 10, 'specialPower': 'peek_at_card'},
      {'rank': 'king', 'points': 10},
    ];
    
    int cardIndex = 0;
    for (final suit in suits) {
      for (final rankData in ranks) {
        // Use card_ prefix to match validation pattern: ^card_[a-zA-Z0-9_]+$
        // Format: card_demo_{rank}_{suit}_{index} (consistent with practice mode pattern)
        final rankStr = rankData['rank'].toString().replaceAll(' ', '_');
        final cardId = 'card_demo_${rankStr}_${suit}_$cardIndex';
        cardIndex++;
        cards.add({
          'cardId': cardId,
          'rank': rankData['rank'],
          'suit': suit,
          'points': rankData['points'],
          if (rankData.containsKey('specialPower')) 'specialPower': rankData['specialPower'],
        });
      }
    }
    
    // Add extra Kings instead of jokers (for same rank play testing)
    // Add 2 additional Kings (spades and clubs) - these will be used for same rank play
    cards.add({
      'cardId': 'card_demo_king_spades_extra_$cardIndex',
      'rank': 'king',
      'suit': 'spades',
      'points': 10,
    });
    cardIndex++;
    cards.add({
      'cardId': 'card_demo_king_clubs_extra_$cardIndex',
      'rank': 'king',
      'suit': 'clubs',
      'points': 10,
    });
    
    return cards;
  }

  @override
  Widget buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          key: _mainStackKey,
          clipBehavior: Clip.none,
          children: [
            // Main content - shows either buttons or game widgets
            if (!_modeSelected)
              // Show demo mode selection buttons
              _buildDemoModeButtons(constraints.maxHeight)
            else
              // Show game widgets after mode selection
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Game Information Widget - takes natural height
                  const GameInfoWidget(),
                  
                  SizedBox(height: AppPadding.smallPadding.top),
                  
                  // Unified Game Board Widget - takes all remaining available space
                  // It will be scrollable internally with my hand aligned to bottom
                  Expanded(
                    child: const UnifiedGameBoardWidget(),
                  ),
                ],
              ),
        
            // Demo Instructions Widget - overlay at top (only when mode selected)
            if (_modeSelected)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: const DemoInstructionsWidget(),
              ),
        
            // Select Cards Prompt Widget - overlay above myhand section (only when mode selected)
            if (_modeSelected)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: const SelectCardsPromptWidget(),
              ),
        
            // Card Animation Layer - full-screen overlay for animated cards (only when mode selected)
            if (_modeSelected)
              CardAnimationLayer(stackKey: _mainStackKey),
        
            // Instructions Modal Widget - handles its own state subscription (only when mode selected)
            if (_modeSelected)
              const InstructionsWidget(),
        
            // Messages Modal Widget - handles its own state subscription (only when mode selected)
            if (_modeSelected)
              const MessagesWidget(),
          ],
        );
      },
    );
  }

  Widget _buildDemoModeButtons(double availableContentHeight) {
    // Calculate button height accounting for margins
    // Each button has vertical margin of 8px (top + bottom = 16px per button)
    // Total margin space: 16px (button 1) + 16px (button 2) = 32px
    // Available height for buttons: total height - margins
    // Each button gets 50% of the remaining space
    const verticalMargin = 8.0; // top + bottom margin per button
    const totalMargins = verticalMargin * 4; // 4 margins total (2 buttons * 2 margins each)
    final availableForButtons = availableContentHeight - totalMargins;
    final buttonHeight = availableForButtons * 0.5; // 50% of available space after margins
        
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            // Start Dutch demo button (regular mode)
            Container(
              width: double.infinity,
              height: buttonHeight,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _logger.info('🎮 DemoScreen: "Start Dutch demo" button tapped', isOn: LOGGING_SWITCH);
                    setState(() {
                      _isClearAndCollect = false;
                      _modeSelected = true;
                    });
                    // Initialize demo state (after setState to ensure UI updates)
                    _initializeDemoState();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Center(
                      child: Text(
                        'Start Dutch demo',
                        style: AppTextStyles.headingMedium().copyWith(
                          color: AppColors.textOnPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Start Dutch Clear and collect demo button
            Container(
              width: double.infinity,
              height: buttonHeight,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accentColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _logger.info('🎮 DemoScreen: "Start Dutch Clear and collect demo" button tapped', isOn: LOGGING_SWITCH);
                    setState(() {
                      _isClearAndCollect = true;
                      _modeSelected = true;
                    });
                    // Initialize demo state (after setState to ensure UI updates)
                    _initializeDemoState();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Center(
                      child: Text(
                        'Start Dutch Clear and collect demo',
                        style: AppTextStyles.headingMedium().copyWith(
                          color: AppColors.textOnPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
  }

  /// Initialize demo game state with predefined cards (all local state)
  void _initializeDemoState() {
    try {
      _logger.info('🎮 DemoScreen: Initializing demo state (isClearAndCollect: $_isClearAndCollect)', isOn: LOGGING_SWITCH);
      
      // 1. Generate demo game ID
      _demoGameId = 'demo_game_${DateTime.now().millisecondsSinceEpoch}';
      
      // 2. Get predefined cards (manually created, no deck factory)
      final fullDeck = _getPredefinedCards();
      _logger.info('🎮 DemoScreen: Created ${fullDeck.length} predefined cards', isOn: LOGGING_SWITCH);
      
      // 3. Store original deck for lookups
      _originalDeck = List<Map<String, dynamic>>.from(fullDeck);
      
      // 4. Helper to create ID-only card (for opponents' hands - face-down)
      Map<String, dynamic> _cardToIdOnly(Map<String, dynamic> card) => {
        'cardId': card['cardId'],
        'suit': '?',
        'rank': '?',
        'points': 0,
      };
      
      // 5. Create players (current user + 3 opponents)
      final demoUserId = 'demo_user_${DateTime.now().millisecondsSinceEpoch}';
      final practiceSessionId = 'practice_session_$demoUserId';
      
      _players = [
        // Current user (ID-only cards for demo)
        {
          'id': practiceSessionId,
          'name': 'You',
          'isHuman': true,
          'status': 'initial_peek',
          'hand': <Map<String, dynamic>>[],
          'drawnCard': null,
          'cardsToPeek': <Map<String, dynamic>>[],
          'points': 0,
          'score': 0,
          'isCurrentPlayer': true,
          'isActive': true,
        },
        // Opponent 1 (ID-only cards)
        {
          'id': 'demo_opponent_1',
          'name': 'Opponent 1',
          'isHuman': false,
          'status': 'initial_peek',
          'hand': <Map<String, dynamic>>[],
          'drawnCard': null,
          'cardsToPeek': <Map<String, dynamic>>[],
          'points': 0,
          'score': 0,
          'isCurrentPlayer': false,
          'isActive': true,
        },
        // Opponent 2 (ID-only cards)
        {
          'id': 'demo_opponent_2',
          'name': 'Opponent 2',
          'isHuman': false,
          'status': 'initial_peek',
          'hand': <Map<String, dynamic>>[],
          'drawnCard': null,
          'cardsToPeek': <Map<String, dynamic>>[],
          'points': 0,
          'score': 0,
          'isCurrentPlayer': false,
          'isActive': true,
        },
        // Opponent 3 (ID-only cards)
        {
          'id': 'demo_opponent_3',
          'name': 'Opponent 3',
          'isHuman': false,
          'status': 'initial_peek',
          'hand': <Map<String, dynamic>>[],
          'drawnCard': null,
          'cardsToPeek': <Map<String, dynamic>>[],
          'points': 0,
          'score': 0,
          'isCurrentPlayer': false,
          'isActive': true,
        },
      ];
      
      // 6. Deal cards to players, ensuring each rank in user's hand is also in at least one opponent's hand
      final drawStack = List<Map<String, dynamic>>.from(fullDeck);
      
      // First, deal 4 cards to the user (human player)
      final userHand = <Map<String, dynamic>>[];
      final userHandRanks = <String>{}; // Track ranks in user's hand
      
      for (int i = 0; i < 4 && drawStack.isNotEmpty; i++) {
        final card = drawStack.removeAt(0);
        userHand.add(_cardToIdOnly(card));
        userHandRanks.add(card['rank']?.toString() ?? '');
      }
      _players[0]['hand'] = userHand;
      _logger.info('🎮 DemoScreen: Dealt ${userHand.length} cards to user. Ranks: ${userHandRanks.toList()}', isOn: LOGGING_SWITCH);
      
      // Now deal to opponents, ensuring each opponent gets at least one card matching a rank from user's hand
      final opponentRanksAssigned = <String>{}; // Track which ranks we've assigned to opponents
      
      for (int playerIndex = 1; playerIndex < _players.length; playerIndex++) {
        final player = _players[playerIndex];
        final hand = <Map<String, dynamic>>[];
        
        // First, try to give this opponent a card matching a rank from user's hand that hasn't been assigned yet
        for (final userRank in userHandRanks) {
          if (!opponentRanksAssigned.contains(userRank)) {
            // Find a card with this rank in the draw stack
            int matchingCardIndex = -1;
            for (int i = 0; i < drawStack.length; i++) {
              if (drawStack[i]['rank']?.toString() == userRank) {
                matchingCardIndex = i;
                break;
              }
            }
            
            if (matchingCardIndex != -1) {
              final matchingCard = drawStack.removeAt(matchingCardIndex);
              hand.add(_cardToIdOnly(matchingCard));
              opponentRanksAssigned.add(userRank);
              _logger.info('🎮 DemoScreen: Assigned ${player['name']} a ${userRank} to match user\'s hand', isOn: LOGGING_SWITCH);
              break;
            }
          }
        }
        
        // Fill remaining slots (3 more cards to make 4 total)
        for (int i = hand.length; i < 4 && drawStack.isNotEmpty; i++) {
          final card = drawStack.removeAt(0);
          hand.add(_cardToIdOnly(card));
        }
        
        player['hand'] = hand;
        _logger.info('🎮 DemoScreen: Dealt ${hand.length} cards to ${player['name']} (ID-only)', isOn: LOGGING_SWITCH);
      }
      
      // Ensure all user ranks are covered (if any weren't assigned, assign them now)
      for (final userRank in userHandRanks) {
        if (!opponentRanksAssigned.contains(userRank)) {
          // Find a card with this rank and assign it to the first opponent that doesn't have 4 cards yet
          for (int playerIndex = 1; playerIndex < _players.length; playerIndex++) {
            final player = _players[playerIndex];
            final hand = player['hand'] as List<dynamic>;
            if (hand.length < 4) {
              // Find a card with this rank in the draw stack
              int matchingCardIndex = -1;
              for (int i = 0; i < drawStack.length; i++) {
                if (drawStack[i]['rank']?.toString() == userRank) {
                  matchingCardIndex = i;
                  break;
                }
              }
              
              if (matchingCardIndex != -1) {
                final matchingCard = drawStack.removeAt(matchingCardIndex);
                hand.add(_cardToIdOnly(matchingCard));
                opponentRanksAssigned.add(userRank);
                _logger.info('🎮 DemoScreen: Assigned ${player['name']} a ${userRank} to ensure all user ranks are covered', isOn: LOGGING_SWITCH);
                break;
              }
            }
          }
        }
      }
      
      // 7. Set up discard pile with first card (full data - face-up)
      _discardPile = [];
      if (drawStack.isNotEmpty) {
        final firstCard = drawStack.removeAt(0);
        _discardPile.add(Map<String, dynamic>.from(firstCard));
        _logger.info('🎮 DemoScreen: Set up discard pile with first card', isOn: LOGGING_SWITCH);
      }
      
      // 8. Set up draw pile - find a King and put it at the top
      _drawPile = [];
      Map<String, dynamic>? topKingCard;
      
      // Find a King card for the top of draw pile
      int kingIndex = -1;
      for (int i = 0; i < drawStack.length; i++) {
        if (drawStack[i]['rank']?.toString() == 'king') {
          kingIndex = i;
          break;
        }
      }
      
      if (kingIndex != -1) {
        topKingCard = drawStack.removeAt(kingIndex);
        _drawPile.add(Map<String, dynamic>.from(topKingCard)); // Full data at top
        _logger.info('🎮 DemoScreen: Added King ${topKingCard['suit']} to top of draw pile', isOn: LOGGING_SWITCH);
      } else {
        _logger.warning('⚠️ DemoScreen: No King found for top of draw pile', isOn: LOGGING_SWITCH);
      }
      
      // Add remaining cards as ID-only
      _drawPile.addAll(drawStack.map((c) => _cardToIdOnly(c)).toList());
      _logger.info('🎮 DemoScreen: Draw pile has ${_drawPile.length} cards (King at top: ${topKingCard != null})', isOn: LOGGING_SWITCH);
      
      // 9. Set current player
      _currentPlayer = {
        'id': practiceSessionId,
        'name': 'You',
        'status': 'initial_peek',
      };
      
      // 10. Set game phase to initial_peek (for actual game state)
      _gamePhase = 'initial_peek';
      _roundNumber = 1;
      _turnNumber = 1;
      
      // Set demo instructions phase to 'initial' (separate from game phase)
      final stateManager = StateManager();
      stateManager.updateModuleState('dutch_game', {
        'demoInstructionsPhase': 'initial',
      });
      
      // 11. Switch event emitter to demo mode (intercepts all actions)
      final eventEmitter = DutchGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.demo);
      _logger.info('🎮 DemoScreen: Switched to demo mode (actions will be intercepted)', isOn: LOGGING_SWITCH);

      // 12. Update StateManager with demo state (widgets read from here)
      _updateStateManagerWithDemoState();
      
      _logger.info('✅ DemoScreen: Demo state initialized successfully', isOn: LOGGING_SWITCH);
    } catch (e, stackTrace) {
      _logger.error('❌ DemoScreen: Error initializing demo state: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
    }
  }
  
  /// Update StateManager with demo state (widgets read from StateManager)
  void _updateStateManagerWithDemoState() {
    if (_demoGameId == null) return;
    
    try {
      // Build game state structure (matching STATE_MANAGEMENT.md format)
      final gameState = {
        'phase': _gamePhase,
        'status': 'active',
        'gameType': 'demo',
        'roundNumber': _roundNumber,
        'turnNumber': _turnNumber,
        'isClearAndCollect': _isClearAndCollect,
        'players': _players,
        'currentPlayer': _currentPlayer,
        'drawPile': _drawPile,
        'discardPile': _discardPile,
        'originalDeck': _originalDeck,
        'playerCount': _players.length,
        'maxPlayers': 4,
        'minPlayers': 2,
        'showInstructions': false,
        'dutchCalledBy': null,
        'winners': null,
      };
      
      // Build games map structure
      final games = {
        _demoGameId!: {
          'gameData': {
            'game_id': _demoGameId,
            'owner_id': _players[0]['id'],
            'game_state': gameState,
          },
          'gamePhase': _gamePhase,
          'gameStatus': 'active',
          'isRoomOwner': true,
          'isInGame': true,
          'joinedAt': DateTime.now().toIso8601String(),
          // Widget-specific data
          'myHandCards': _players[0]['hand'], // Current user's hand (full data)
          'myDrawnCard': null,
          'isMyTurn': true,
          'selectedCardIndex': -1,
          'turn_events': <Map<String, dynamic>>[],
          'drawPileCount': _drawPile.length,
          'discardPileCount': _discardPile.length,
          'discardPile': _discardPile,
        },
      };
      
      // Ensure dutch_game state is registered
      final stateManager = StateManager();
      if (!stateManager.isModuleStateRegistered('dutch_game')) {
        stateManager.registerModuleState('dutch_game', {
          'isLoading': false,
          'isConnected': false,
          'currentRoomId': '',
          'currentRoom': null,
          'isInRoom': false,
          'myCreatedRooms': <Map<String, dynamic>>[],
          'players': <Map<String, dynamic>>[],
          'joinedGames': <Map<String, dynamic>>[],
          'totalJoinedGames': 0,
          'joinedGamesTimestamp': '',
          'currentGameId': '',
          'games': <String, dynamic>{},
          'userStats': null,
          'userStatsLastUpdated': null,
          'showCreateRoom': true,
          'showRoomList': true,
          'actionBar': <String, dynamic>{},
          'statusBar': <String, dynamic>{},
          'myHand': <String, dynamic>{},
          'centerBoard': <String, dynamic>{},
          'opponentsPanel': <String, dynamic>{},
          'myDrawnCard': null,
          'cards_to_peek': <Map<String, dynamic>>[],
          'turn_events': <Map<String, dynamic>>[],
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }
      
      // Extract demo user ID from first player
      final firstPlayerId = _players[0]['id']?.toString() ?? '';
      final demoUserId = firstPlayerId.replaceFirst('practice_session_', '');
      
      // Update state with demo game (using sync update for immediate effect)
      final stateUpdater = DutchGameStateUpdater.instance;
      
      // Log before update
      _logger.info('🎮 DemoScreen: Updating StateManager - currentGameId: $_demoGameId, gamePhase: $_gamePhase', isOn: LOGGING_SWITCH);
      _logger.info('🎮 DemoScreen: Games map keys: ${games.keys.toList()}', isOn: LOGGING_SWITCH);
      _logger.info('🎮 DemoScreen: Game entry exists: ${games.containsKey(_demoGameId)}', isOn: LOGGING_SWITCH);
      
      // Use updateStateSync for immediate synchronous update (demo needs instant state)
      // Only using allowed fields from state schema (see state_queue_validator.dart)
      stateUpdater.updateStateSync({
        // Game Context (allowed fields)
        'currentGameId': _demoGameId,
        'currentRoomId': _demoGameId,
        'isInRoom': true,
        'isRoomOwner': true,
        'isGameActive': true,
        'gamePhase': _gamePhase, // Set to 'initial_peek'
        'games': games,
        
        // Player Context (allowed fields)
        'playerStatus': _players[0]['status'] ?? 'initial_peek',
        'currentPlayer': _currentPlayer,
        'currentPlayerStatus': _currentPlayer?['status'] ?? 'initial_peek',
        
        // Game State Fields (allowed fields)
        'roundNumber': _roundNumber,
        'discardPile': _discardPile,
        'drawPileCount': _drawPile.length,
        'turn_events': <Map<String, dynamic>>[],
        
        // Practice Mode (allowed fields)
        'practiceUser': {
          'isPracticeUser': true,
          'userId': demoUserId,
        },
        
        // Metadata (allowed fields)
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      // Manually compute and update widget slices (updateStateSync doesn't compute slices)
      final currentState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      final currentGames = currentState['games'] as Map<String, dynamic>? ?? {};
      final currentGamePhase = currentState['gamePhase']?.toString() ?? 'waiting';
      
      if (currentGameId.isNotEmpty && currentGames.containsKey(currentGameId)) {
        final currentGame = currentGames[currentGameId] as Map<String, dynamic>? ?? {};
        final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
        final gameStatus = currentGame['gameStatus']?.toString() ?? 'active';
        final isRoomOwner = currentGame['isRoomOwner'] ?? true;
        final isInGame = currentGame['isInGame'] ?? true;
        final currentSize = gameState['playerCount'] ?? _players.length;
        final maxSize = gameState['maxPlayers'] ?? 4;
        final isMyTurn = currentGame['isMyTurn'] ?? true;
        final canPlayCard = currentGame['canPlayCard'] ?? false;
        final myHandCards = currentGame['myHandCards'] ?? _players[0]['hand'] ?? [];
        final selectedCardIndex = currentGame['selectedCardIndex'] ?? -1;
        final allPlayers = gameState['players'] ?? _players;
        final turnEvents = currentState['turn_events'] ?? <Map<String, dynamic>>[];
        
        // Get current user ID for opponents filtering
        final firstPlayerId = _players[0]['id']?.toString() ?? '';
        final currentUserId = firstPlayerId.replaceFirst('practice_session_', '');
        final practiceSessionId = 'practice_session_$currentUserId';
        
        // Filter opponents (all players except current user)
        final opponents = allPlayers.where((player) {
          final playerId = player['id']?.toString() ?? '';
          return playerId != practiceSessionId;
        }).toList();
        
        // Find current turn index in opponents
        int currentTurnIndex = -1;
        if (_currentPlayer != null) {
          final currentPlayerId = _currentPlayer!['id']?.toString() ?? '';
          currentTurnIndex = opponents.indexWhere((player) => 
            player['id']?.toString() == currentPlayerId
          );
        }
        
        // Compute widget slices
        final gameInfoSlice = {
          'currentGameId': currentGameId,
          'currentSize': currentSize,
          'maxSize': maxSize,
          'gamePhase': currentGamePhase,
          'gameStatus': gameStatus,
          'isRoomOwner': isRoomOwner,
          'isInGame': isInGame,
        };
        
        final myHandSlice = {
          'cards': myHandCards,
          'selectedIndex': selectedCardIndex,
          'canSelectCards': isMyTurn && canPlayCard,
          'turn_events': turnEvents,
          'playerStatus': _players[0]['status'] ?? 'initial_peek',
        };
        
        final opponentsPanelSlice = {
          'opponents': opponents,
          'currentTurnIndex': currentTurnIndex,
          'turn_events': turnEvents,
          'currentPlayerStatus': _currentPlayer?['status'] ?? 'waiting',
        };
        
        // Update all widget slices
        stateManager.updateModuleState('dutch_game', {
          ...currentState,
          'gameInfo': gameInfoSlice,
          'myHand': myHandSlice,
          'opponentsPanel': opponentsPanelSlice,
        });
        
        _logger.info('✅ DemoScreen: All widget slices manually computed and updated', isOn: LOGGING_SWITCH);
        _logger.info('  myHand cards count: ${myHandCards.length}', isOn: LOGGING_SWITCH);
        _logger.info('  opponents count: ${opponents.length}', isOn: LOGGING_SWITCH);
      }
      
      // Verify state after update
      final updatedState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final updatedGameId = updatedState['currentGameId']?.toString() ?? '';
      final updatedGames = updatedState['games'] as Map<String, dynamic>? ?? {};
      final updatedGameInfo = updatedState['gameInfo'] as Map<String, dynamic>? ?? {};
      
      _logger.info('✅ DemoScreen: StateManager updated - verifying state', isOn: LOGGING_SWITCH);
      _logger.info('  currentGameId in state: $updatedGameId', isOn: LOGGING_SWITCH);
      _logger.info('  games map keys: ${updatedGames.keys.toList()}', isOn: LOGGING_SWITCH);
      _logger.info('  gameInfo slice: $updatedGameInfo', isOn: LOGGING_SWITCH);
    } catch (e, stackTrace) {
      _logger.error('❌ DemoScreen: Error updating StateManager: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
    }
  }

  /// Clean up demo state when leaving
  void _cleanupDemoState() {
    try {
      // Switch event emitter back to WebSocket mode
      final eventEmitter = DutchGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.websocket);
      _logger.info('🎮 DemoScreen: Switched back to WebSocket mode', isOn: LOGGING_SWITCH);

      // Clear local state
      _demoGameId = null;
      _players = [];
      _drawPile = [];
      _discardPile = [];
      _originalDeck = [];
      _currentPlayer = null;
      _gamePhase = 'waiting';
      _roundNumber = 1;
      _turnNumber = 1;
      
      // Clear StateManager state
      final stateUpdater = DutchGameStateUpdater.instance;
      stateUpdater.updateState({
        'currentGameId': '',
        'currentRoomId': '',
        'isInRoom': false,
        'isRoomOwner': false,
        'isGameActive': false,
        'gamePhase': 'waiting',
        'games': <String, dynamic>{},
        'playerStatus': 'waiting',
        'currentPlayer': null,
        'currentPlayerStatus': 'waiting',
        'roundNumber': 0,
        'turnNumber': 0,
        'discardPile': <Map<String, dynamic>>[],
        'drawPileCount': 0,
        'discardPileCount': 0,
        'turn_events': <Map<String, dynamic>>[],
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      // Clear demo instructions phase
      final stateManager = StateManager();
      stateManager.updateModuleState('dutch_game', {
        'demoInstructionsPhase': '',
      });
      
      _logger.info('🧹 DemoScreen: Demo state cleaned up', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ DemoScreen: Error cleaning up demo state: $e', isOn: LOGGING_SWITCH);
    }
  }
}

