import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import 'player_status_chip_widget.dart';
import 'circular_timer_widget.dart';
import '../../../managers/player_action.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../dutch_game/managers/dutch_event_handler_callbacks.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../utils/card_position_scanner.dart';
import '../../../utils/card_animation_detector.dart';
import '../../demo/demo_functionality.dart';

const bool LOGGING_SWITCH = false; // Enabled for testing and debugging

/// Unified widget that combines OpponentsPanelWidget, DrawPileWidget, 
/// DiscardPileWidget, MatchPotWidget, and MyHandWidget into a single widget.
/// 
/// This widget maintains all existing logic and layout structure while
/// providing a unified coordinate system for future animation implementation.
class UnifiedGameBoardWidget extends StatefulWidget {
  const UnifiedGameBoardWidget({Key? key}) : super(key: key);

  @override
  State<UnifiedGameBoardWidget> createState() => _UnifiedGameBoardWidgetState();
}

class _UnifiedGameBoardWidgetState extends State<UnifiedGameBoardWidget> with TickerProviderStateMixin {
  final Logger _logger = Logger();
  
  // ========== Opponents Panel State ==========
  String? _clickedCardId;
  bool _isCardsToPeekProtected = false;
  List<dynamic>? _protectedCardsToPeek;
  Timer? _cardsToPeekProtectionTimer;
  
  // ========== Draw Pile State ==========
  String? _clickedPileType;
  AnimationController? _glowAnimationController;
  Animation<double>? _glowAnimation;
  
  // ========== Discard Pile State ==========
  // (No state needed - using _cardKeys for all cards)
  
  // ========== My Hand State ==========
  int _initialPeekSelectionCount = 0;
  List<String> _initialPeekSelectedCardIds = [];
  bool _isProcessingAction = false;
  bool _isMyHandCardsToPeekProtected = false;
  List<dynamic>? _protectedMyHandCardsToPeek;
  Timer? _myHandCardsToPeekProtectionTimer;
  
  // ========== Animation System State ==========
  /// Map of cardId -> GlobalKey for all cards (reused across rebuilds)
  final Map<String, GlobalKey> _cardKeys = {};
  
  /// GlobalKey for myhand section (used for measuring height in overlays)
  final GlobalKey _myHandKey = GlobalKey(debugLabel: 'my_hand_section');
  
  /// GlobalKey for game board section (used for measuring height in overlays)
  final GlobalKey _gameBoardKey = GlobalKey(debugLabel: 'game_board_section');
  
  /// CardPositionScanner instance
  final CardPositionScanner _positionScanner = CardPositionScanner();
  
  /// CardAnimationDetector instance
  final CardAnimationDetector _animationDetector = CardAnimationDetector();
  
  // ========== Position Scanning Optimization State ==========
  /// Previous card-related state snapshot for change detection
  Map<String, dynamic>? _previousCardState;
  
  /// Flag to prevent multiple scans in the same frame
  bool _isScanScheduled = false;
  
  /// Timer for throttling scans (max once per 100ms)
  Timer? _scanThrottleTimer;
  
  /// Last scan timestamp for throttling
  DateTime _lastScanTime = DateTime(0);
  
  /// Minimum time between scans (100ms)
  static const Duration _minScanInterval = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    // Initialize glow animation controller
    _glowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowAnimationController!,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _cardsToPeekProtectionTimer?.cancel();
    _myHandCardsToPeekProtectionTimer?.cancel();
    _scanThrottleTimer?.cancel();
    _positionScanner.clearPositions();
    _glowAnimationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Check if card-related state changed and schedule scan if needed
        _checkAndScheduleScan();
        
        return LayoutBuilder(
          builder: (context, constraints) {
            // New layout: Opponents spread evenly, Game Board above My Hand
            return Column(
              children: [
                // Opponents Panel Section - spread evenly vertically
                Expanded(
                  child: _buildOpponentsPanel(),
                ),
                
                // Spacer above game board (doubled)
                const SizedBox(height: 32),
                
                // Game Board Section - Draw Pile, Match Pot, Discard Pile (just above My Hand)
                _buildGameBoard(),
                
                // Small spacer below game board
                const SizedBox(height: 16),
                
                // My Hand Section - at the bottom
                _buildMyHand(),
              ],
            );
          },
        );
      },
    );
  }
  
  // ========== Animation System Methods ==========
  
  /// Get or create GlobalKey for a card
  GlobalKey _getOrCreateCardKey(String cardId, String keyType) {
    final key = '${keyType}_$cardId';
    if (!_cardKeys.containsKey(key)) {
      _cardKeys[key] = GlobalKey(debugLabel: key);
    }
    return _cardKeys[key]!;
  }
  
  /// Check if card-related state changed and schedule scan if needed
  /// Optimization 1: Only scan when card-related state changes
  void _checkAndScheduleScan() {
    if (!mounted) return;
    
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    
    // Extract card-related state for comparison
    final currentCardState = _extractCardRelatedState(dutchGameState);
    
    // Check if game changed (new game started/ended)
    if (_previousCardState != null && 
        _previousCardState!['currentGameId'] != currentCardState['currentGameId']) {
      // Game changed - clear previous state and positions
      _logger.info('🎬 UnifiedGameBoardWidget: Game changed, clearing previous state', isOn: LOGGING_SWITCH);
      _previousCardState = null;
      _positionScanner.clearPositions();
    }
    
    // Check if card-related state actually changed
    if (_previousCardState != null && _statesAreEqual(_previousCardState!, currentCardState)) {
      // No card-related changes, skip scan
      return;
    }
    
    // State changed, update previous and schedule scan
    _previousCardState = currentCardState;
    
    // Optimization 2 & 3: Throttle scans and use dirty flag
    _scheduleThrottledScan();
  }
  
  /// Extract only card-related state for change detection
  Map<String, dynamic> _extractCardRelatedState(Map<String, dynamic> fullState) {
    final currentGameId = fullState['currentGameId']?.toString() ?? '';
    final games = fullState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Extract card-related fields
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    
    // Extract my hand
    final myHand = fullState['myHand'] as Map<String, dynamic>? ?? {};
    final myHandCards = myHand['cards'] as List<dynamic>? ?? [];
    
    // Extract opponents hands
    final opponentsPanel = fullState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    final opponentsHands = opponents.map((opponent) {
      if (opponent is Map<String, dynamic>) {
        final hand = opponent['hand'] as List<dynamic>? ?? [];
        return {
          'id': opponent['id']?.toString(),
          'hand': hand.map((card) {
            if (card is Map<String, dynamic>) {
              return card['cardId']?.toString();
            }
            return null;
          }).where((id) => id != null).toList(),
        };
      }
      return null;
    }).where((o) => o != null).toList();
    
    return {
      'currentGameId': currentGameId,
      'drawPile': drawPile.map((card) {
        if (card is Map<String, dynamic>) {
          return card['cardId']?.toString();
        }
        return null;
      }).where((id) => id != null).toList(),
      'discardPile': discardPile.map((card) {
        if (card is Map<String, dynamic>) {
          return card['cardId']?.toString();
        }
        return null;
      }).where((id) => id != null).toList(),
      'myHand': myHandCards.map((card) {
        if (card is Map<String, dynamic>) {
          return card['cardId']?.toString();
        }
        return null;
      }).where((id) => id != null).toList(),
      'opponentsHands': opponentsHands,
    };
  }
  
  /// Compare two state maps for equality
  bool _statesAreEqual(Map<String, dynamic> state1, Map<String, dynamic> state2) {
    // Compare currentGameId
    if (state1['currentGameId'] != state2['currentGameId']) {
      return false;
    }
    
    // Compare drawPile
    final drawPile1 = state1['drawPile'] as List? ?? [];
    final drawPile2 = state2['drawPile'] as List? ?? [];
    if (!_listsEqual(drawPile1, drawPile2)) {
      return false;
    }
    
    // Compare discardPile
    final discardPile1 = state1['discardPile'] as List? ?? [];
    final discardPile2 = state2['discardPile'] as List? ?? [];
    if (!_listsEqual(discardPile1, discardPile2)) {
      return false;
    }
    
    // Compare myHand
    final myHand1 = state1['myHand'] as List? ?? [];
    final myHand2 = state2['myHand'] as List? ?? [];
    if (!_listsEqual(myHand1, myHand2)) {
      return false;
    }
    
    // Compare opponentsHands
    final opponents1 = state1['opponentsHands'] as List? ?? [];
    final opponents2 = state2['opponentsHands'] as List? ?? [];
    if (opponents1.length != opponents2.length) {
      return false;
    }
    
    for (int i = 0; i < opponents1.length; i++) {
      final opp1 = opponents1[i] as Map<String, dynamic>?;
      final opp2 = opponents2[i] as Map<String, dynamic>?;
      if (opp1 == null || opp2 == null) {
        if (opp1 != opp2) return false;
        continue;
      }
      if (opp1['id'] != opp2['id']) {
        return false;
      }
      final hand1 = opp1['hand'] as List? ?? [];
      final hand2 = opp2['hand'] as List? ?? [];
      if (!_listsEqual(hand1, hand2)) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Compare two lists for equality (order-sensitive)
  bool _listsEqual(List list1, List list2) {
    if (list1.length != list2.length) {
      return false;
    }
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) {
        return false;
      }
    }
    return true;
  }
  
  /// Schedule a throttled scan (Optimization 2: Throttle scans)
  void _scheduleThrottledScan() {
    // Cancel any pending throttle timer
    _scanThrottleTimer?.cancel();
    
    final now = DateTime.now();
    final timeSinceLastScan = now.difference(_lastScanTime);
    
    // If enough time has passed, scan immediately
    if (timeSinceLastScan >= _minScanInterval) {
      _lastScanTime = now;
      _scheduleScan();
      return;
    }
    
    // Otherwise, schedule scan after remaining time
    final remainingTime = _minScanInterval - timeSinceLastScan;
    _scanThrottleTimer = Timer(remainingTime, () {
      _lastScanTime = DateTime.now();
      _scheduleScan();
    });
  }
  
  /// Schedule scan using PostFrameCallback (Optimization 3: Dirty flag)
  void _scheduleScan() {
    // Prevent multiple scans in the same frame
    if (_isScanScheduled) {
      _logger.debug('🎬 UnifiedGameBoardWidget: Scan already scheduled for this frame', isOn: LOGGING_SWITCH);
      return;
    }
    
    _isScanScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isScanScheduled = false;
      _scanCardPositions();
    });
  }
  
  /// Scan all card positions after build
  void _scanCardPositions() {
    if (!mounted) return;
    
    _logger.info('🎬 UnifiedGameBoardWidget: Starting position scan', isOn: LOGGING_SWITCH);
    
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final Map<String, CardKeyData> cardKeys = {};
    
    // Collect all card keys with metadata
    
    // 1. Draw Pile - Track all cards in draw pile
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    
    if (drawPile.isEmpty) {
      // Empty draw pile - track placeholder
      final emptyKey = _getOrCreateCardKey('draw_pile_empty', 'draw_pile');
      cardKeys['draw_pile_empty'] = CardKeyData(
        key: emptyKey,
        location: 'draw_pile',
        isFaceUp: false,
      );
    } else {
      for (final cardData in drawPile) {
        if (cardData is Map<String, dynamic>) {
          final cardId = cardData['cardId']?.toString();
          if (cardId != null && cardId.isNotEmpty) {
            final cardKey = _getOrCreateCardKey(cardId, 'draw_pile');
            cardKeys[cardId] = CardKeyData(
              key: cardKey,
              location: 'draw_pile',
              isFaceUp: false,
            );
          }
        }
      }
    }
    
    // 2. Discard Pile - Track all cards in discard pile
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    
    if (discardPile.isEmpty) {
      // Empty discard pile
      final emptyKey = _getOrCreateCardKey('discard_pile_empty', 'discard_pile');
      cardKeys['discard_pile_empty'] = CardKeyData(
        key: emptyKey,
        location: 'discard_pile',
        isFaceUp: true,
      );
    } else {
      for (final cardData in discardPile) {
        if (cardData is Map<String, dynamic>) {
          final cardId = cardData['cardId']?.toString();
          if (cardId != null && cardId.isNotEmpty) {
            final cardKey = _getOrCreateCardKey(cardId, 'discard_pile');
            cardKeys[cardId] = CardKeyData(
              key: cardKey,
              location: 'discard_pile',
              isFaceUp: true,
            );
          }
        }
      }
    }
    
    // 3. Opponent Cards
    final opponentsPanel = dutchGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    final cardsToPeekFromState = dutchGameState['myCardsToPeek'] as List<dynamic>? ?? [];
    final cardsToPeek = _isCardsToPeekProtected && _protectedCardsToPeek != null
        ? _protectedCardsToPeek!
        : cardsToPeekFromState;
    
    for (final opponent in opponents) {
      if (opponent is Map<String, dynamic>) {
        final playerId = opponent['id']?.toString() ?? '';
        final hand = opponent['hand'] as List<dynamic>? ?? [];
        final drawnCard = opponent['drawnCard'] as Map<String, dynamic>?;
        final playerCollectionRankCards = opponent['collection_rank_cards'] as List<dynamic>? ?? [];
        
        for (int i = 0; i < hand.length; i++) {
          final card = hand[i];
          if (card == null) continue;
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          if (cardId == null) continue;
          
          // Check if card is peeked (face up)
          bool isFaceUp = false;
          for (var peekedCard in cardsToPeek) {
            if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
              isFaceUp = true;
              break;
            }
          }
          
          // Check if card is in collection rank cards (has full data)
          bool hasFullData = false;
          for (var collectionCard in playerCollectionRankCards) {
            if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
              hasFullData = true;
              break;
            }
          }
          
          // If drawn card, it has full data
          if (drawnCard != null && drawnCard['cardId']?.toString() == cardId) {
            hasFullData = true;
          }
          
          // Face up if peeked or has full data
          isFaceUp = isFaceUp || hasFullData;
          
          final key = _getOrCreateCardKey(cardId, 'opponent_$playerId');
          cardKeys[cardId] = CardKeyData(
            key: key,
            location: 'opponent_hand_$playerId',
            isFaceUp: isFaceUp,
            playerId: playerId,
            index: i,
          );
        }
      }
    }
    
    // 4. My Hand Cards
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    final myHandCards = myHand['cards'] as List<dynamic>? ?? [];
    
    for (int i = 0; i < myHandCards.length; i++) {
      final card = myHandCards[i];
      if (card == null) continue;
      final cardMap = card as Map<String, dynamic>;
      final cardId = cardMap['cardId']?.toString();
      if (cardId == null) continue;
      
      // My hand cards are always face up
      bool isFaceUp = true;
      
      final key = _getOrCreateCardKey(cardId, 'my_hand');
      cardKeys[cardId] = CardKeyData(
        key: key,
        location: 'my_hand',
        isFaceUp: isFaceUp,
        index: i,
      );
    }
    
    // Scan positions
    final currentPositions = _positionScanner.scanAllCards(context, cardKeys);
    
    // Detect animations
    _detectAndTriggerAnimations(currentPositions);
  }
  
  /// Detect animations and trigger them
  void _detectAndTriggerAnimations(Map<String, CardPosition> currentPositions) {
    final previousPositions = _positionScanner.getAllPreviousPositions();
    
    // Detect animations
    final animations = _animationDetector.detectAnimations(currentPositions, previousPositions);
    
    if (animations.isNotEmpty) {
      _logger.info('🎬 UnifiedGameBoardWidget: Detected ${animations.length} animations', isOn: LOGGING_SWITCH);
      // Animations are automatically triggered via CardAnimationDetector.animationTriggers ValueNotifier
    }
    
    // Save current positions as previous for next comparison
    _positionScanner.saveCurrentAsPrevious();
  }

  // ========== Opponents Panel Methods ==========

  /// Protect cardsToPeek data for 5 seconds
  void _protectCardsToPeek(List<dynamic> cardsToPeek) {
    _cardsToPeekProtectionTimer?.cancel();
    _isCardsToPeekProtected = true;
    _protectedCardsToPeek = List<dynamic>.from(cardsToPeek);
    _cardsToPeekProtectionTimer = Timer(Duration(seconds: 5), () {
      _clearCardsToPeekProtection();
    });
  }

  /// Clear cardsToPeek protection
  void _clearCardsToPeekProtection() {
    _isCardsToPeekProtected = false;
    _protectedCardsToPeek = null;
    _cardsToPeekProtectionTimer?.cancel();
    _cardsToPeekProtectionTimer = null;
    if (mounted) {
      setState(() {});
    }
  }

  /// Build the opponents panel widget
  Widget _buildOpponentsPanel() {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final opponentsPanel = dutchGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    final currentTurnIndex = opponentsPanel['currentTurnIndex'] ?? -1;
    final cardsToPeekFromState = dutchGameState['myCardsToPeek'] as List<dynamic>? ?? [];
    
    // Check if we need to protect cardsToPeek
    if (cardsToPeekFromState.isNotEmpty && !_isCardsToPeekProtected) {
      final hasFullCardData = cardsToPeekFromState.any((card) {
        if (card is Map<String, dynamic>) {
          return card.containsKey('suit') || card.containsKey('rank');
        }
        return false;
      });
      if (hasFullCardData) {
        _protectCardsToPeek(cardsToPeekFromState);
      }
    }
    
    final cardsToPeek = _isCardsToPeekProtected && _protectedCardsToPeek != null
        ? _protectedCardsToPeek!
        : cardsToPeekFromState;
    
    final otherPlayers = opponents;
    final isGameActive = dutchGameState['isGameActive'] ?? false;
    final playerStatus = dutchGameState['playerStatus']?.toString() ?? 'unknown';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opponents.isEmpty)
          _buildEmptyOpponents()
        else
          // Spread opponents evenly vertically using Expanded and Spacers
          Expanded(
            child: _buildOpponentsGrid(otherPlayers, cardsToPeek, currentTurnIndex, isGameActive, playerStatus),
          ),
      ],
    );
  }

  Widget _buildEmptyOpponents() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people,
              size: 24,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              'No other players',
              style: AppTextStyles.bodySmall().copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpponentsGrid(List<dynamic> opponents, List<dynamic> cardsToPeek, int currentTurnIndex, bool isGameActive, String playerStatus) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final currentPlayerRaw = dutchGameState['currentPlayer'];
        Map<String, dynamic>? currentPlayerData;
        if (currentPlayerRaw == null || currentPlayerRaw == 'null' || currentPlayerRaw == '') {
          currentPlayerData = null;
        } else if (currentPlayerRaw is Map<String, dynamic>) {
          currentPlayerData = currentPlayerRaw;
        } else {
          currentPlayerData = null;
        }
        final currentPlayerId = currentPlayerData?['id']?.toString() ?? '';
        // Use current user's status for card glow (same source as status chip)
        final currentPlayerStatus = _getCurrentUserStatus();
        final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'waiting';
        final isInitialPeekPhase = gamePhase == 'initial_peek';
        
        // Get game state for timer configuration
        final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
        final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
        final gameData = games[currentGameId] as Map<String, dynamic>?;
        final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
        final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
        final phase = gameState?['phase'] as String?;
        // Safely convert Map<String, dynamic> to Map<String, int>
        final timerConfigRaw = gameState?['timerConfig'] as Map<String, dynamic>?;
        final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    
        // Order opponents: opp1 to column 1 (left), opp2 to middle column
        List<dynamic> reorderedOpponents = [];
        if (opponents.length >= 2) {
          reorderedOpponents = [
            opponents[0], // opp1 goes to column 1 (left)
            opponents[1], // opp2 goes to middle column
            if (opponents.length > 2) ...opponents.sublist(2), // opp3+ goes to right column
          ];
        } else {
          reorderedOpponents = opponents; // If less than 2 opponents, keep original order
        }
        
        // Create a map to find original index from player ID for currentTurnIndex calculation
        final originalIndexMap = <String, int>{};
        for (int i = 0; i < opponents.length; i++) {
          final player = opponents[i] as Map<String, dynamic>;
          final playerId = player['id']?.toString() ?? '';
          if (playerId.isNotEmpty) {
            originalIndexMap[playerId] = i;
          }
        }
    
        // Build list of opponent widgets with equal width columns
        final opponentWidgets = <Widget>[];
        final entries = reorderedOpponents.asMap().entries.toList();
        
        for (int i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final displayIndex = entry.key; // Position in UI (0=left, 1=middle, 2=right)
          final player = entry.value as Map<String, dynamic>;
          final playerId = player['id']?.toString() ?? '';
          // Use original index from opponents list for turn calculation
          final originalIndex = originalIndexMap[playerId] ?? displayIndex;
          final isCurrentTurn = originalIndex == currentTurnIndex;
          final isCurrentPlayer = playerId == currentPlayerId;
          final knownCards = player['known_cards'] as Map<String, dynamic>?;
          
          // Add opponent widget wrapped in Expanded for equal width
          opponentWidgets.add(
            Expanded(
              child: _buildOpponentCard(
                player, 
                cardsToPeek, 
                player['collection_rank_cards'] as List<dynamic>? ?? [],
                isCurrentTurn, 
                isGameActive, 
                isCurrentPlayer, 
                currentPlayerStatus,
                knownCards,
                isInitialPeekPhase,
                phase, // Pass phase for timer calculation
                timerConfig, // Pass timerConfig from game_state
                opponentIndex: displayIndex, // Pass display index for alignment (0=left, 1=middle, 2=right)
              ),
            ),
          );
        }
        
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Expand columns to fill available height
          children: opponentWidgets,
        );
      },
    );
  }

  Widget _buildOpponentCard(Map<String, dynamic> player, List<dynamic> cardsToPeek, List<dynamic> playerCollectionRankCards, bool isCurrentTurn, bool isGameActive, bool isCurrentPlayer, String currentPlayerStatus, Map<String, dynamic>? knownCards, bool isInitialPeekPhase, String? phase, Map<String, int>? timerConfig, {required int opponentIndex}) {
    // Get player name - prefer full_name, fallback to name, then username, then default
    final fullName = player['full_name']?.toString();
    final playerNameRaw = player['name']?.toString();
    final username = player['username']?.toString();
    final playerName = (fullName != null && fullName.isNotEmpty) 
        ? fullName 
        : (playerNameRaw != null && playerNameRaw.isNotEmpty) 
            ? playerNameRaw 
            : (username != null && username.isNotEmpty) 
                ? username 
                : 'Unknown Player';
    final hand = player['hand'] as List<dynamic>? ?? [];
    final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
    final hasCalledDutch = player['hasCalledDutch'] ?? false;
    final playerStatus = player['status']?.toString() ?? 'unknown';
    
    // For timer calculation, always use playerStatus (opponent's actual status)
    // currentPlayerStatus is the user's status (used for card glow), not the opponent's status
    // For timer, we need the opponent's actual status to get the correct duration
    final statusForTimer = playerStatus;
    
    // Calculate timer from game_state timerConfig (status is more specific than phase)
    int? effectiveTimer;
    
    // Check status first (more specific than phase for player actions)
    if (statusForTimer != null && statusForTimer.isNotEmpty) {
      switch (statusForTimer) {
        case 'initial_peek':
          effectiveTimer = timerConfig?['initial_peek'] ?? 15;
          break;
        case 'drawing_card':
          effectiveTimer = timerConfig?['drawing_card'] ?? 20;
          break;
        case 'playing_card':
          effectiveTimer = timerConfig?['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          effectiveTimer = timerConfig?['same_rank_window'] ?? 10;
          break;
        case 'queen_peek':
          effectiveTimer = timerConfig?['queen_peek'] ?? 15;
          break;
        case 'jack_swap':
          effectiveTimer = timerConfig?['jack_swap'] ?? 20;
          break;
        case 'peeking':
          effectiveTimer = timerConfig?['peeking'] ?? 10;
          break;
        case 'waiting':
          effectiveTimer = timerConfig?['waiting'] ?? 0;
          break;
        default:
          // If status doesn't match, fall through to phase check
          break;
      }
    }
    
    // If status didn't provide a timer (or status was null), check phase
    if (effectiveTimer == null && phase != null && phase.isNotEmpty) {
      switch (phase) {
        case 'initial_peek':
          effectiveTimer = timerConfig?['initial_peek'] ?? 15;
          break;
        case 'player_turn':
        case 'playing':
          // For generic player_turn/playing phase, status should have been checked above
          // But if status wasn't available, use playing_card as default
          effectiveTimer = timerConfig?['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          effectiveTimer = timerConfig?['same_rank_window'] ?? 10;
          break;
        case 'queen_peek_window':
          effectiveTimer = timerConfig?['queen_peek'] ?? 15;
          break;
        case 'special_play_window':
          effectiveTimer = timerConfig?['jack_swap'] ?? 20;
          break;
        default:
          effectiveTimer = timerConfig?['default'] ?? 30;
      }
    }
    
    // Final fallback if neither status nor phase provided a timer
    effectiveTimer ??= 30;
    
    // Ensure effectiveTimer is valid (not 0, not negative, not NaN) to prevent division by zero in timer widget
    if (effectiveTimer <= 0 || !effectiveTimer.isFinite) {
      effectiveTimer = 30; // Safe default
    }
    
    // Show timer when: player has any active status (drawing_card, playing_card, initial_peek, jack_swap, queen_peek, peeking)
    // Note: 'peeking' status occurs after a queen_peek decision is executed, but timer should continue showing
    // Use playerStatus (opponent's actual status) to determine if timer should show
    final shouldShowTimer = playerStatus == 'drawing_card' || 
         playerStatus == 'playing_card' || 
         playerStatus == 'initial_peek' ||
         playerStatus == 'jack_swap' || 
         playerStatus == 'queen_peek' || 
         playerStatus == 'peeking';
    
    // Use status chip color logic for glow (excludes 'waiting' and 'same_rank_window')
    final shouldShowGlow = _shouldHighlightCurrentPlayer(playerStatus);
    final statusChipColor = shouldShowGlow ? _getStatusChipColor(playerStatus) : null;
    
    // For timer color, always get the status chip color (including same_rank_window)
    final timerColor = _getStatusChipColor(playerStatus);
    
    // Background highlight logic (includes same_rank_window for current player)
    final shouldHighlightBackground = _shouldHighlightCurrentPlayer(playerStatus) 
        || (isCurrentPlayer && playerStatus == 'same_rank_window');
    
    // All opponents align left and wrap
    final Alignment cardAlignment = Alignment.centerLeft;
    final MainAxisAlignment nameAlignment = MainAxisAlignment.start;
    final CrossAxisAlignment columnAlignment = CrossAxisAlignment.start;
    
    // Vertical alignment: col 1 (index 0) center, col 2 (index 1) top, col 3+ (index 2+) center
    final MainAxisAlignment columnMainAlignment = (opponentIndex == 0 || opponentIndex >= 2)
        ? MainAxisAlignment.center
        : MainAxisAlignment.start; // col 2 (index 1) aligns to top
    
    if (drawnCard != null) {
    }
    
    return Column(
      crossAxisAlignment: columnAlignment,
      mainAxisAlignment: columnMainAlignment, // Center vertically for col 1 and 2
      mainAxisSize: MainAxisSize.max, // Expand to fill available height
      children: [
        // Top row: Profile pic and timer, aligned left
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile picture (circular, 1.5x status chip height)
            _buildPlayerProfilePicture(
              player['id']?.toString() ?? '',
              profilePictureUrl: player['profile_picture']?.toString(),
            ),
            const SizedBox(width: 8),
            if (hasCalledDutch) ...[
              Icon(
                Icons.flag,
                size: 16,
                color: AppColors.errorColor,
              ),
              const SizedBox(width: 4),
            ],
            if (isCurrentTurn && !isCurrentPlayer) ...[
              Icon(
                Icons.play_arrow,
                size: 16,
                color: AppColors.accentColor2,
              ),
              const SizedBox(width: 4),
            ],
            // Show circular timer when shouldShowTimer is true
            if (shouldShowTimer) ...[
              const SizedBox(width: 6),
              CircularTimerWidget(
                key: ValueKey('timer_${player['id']}_${playerStatus}'), // Reset timer when player or status changes
                durationSeconds: effectiveTimer,
                size: 28.0, // Match profile picture size
                color: timerColor,
                backgroundColor: AppColors.surfaceVariant,
              ),
            ],
          ],
        ),
        
        // Second row: Username
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            // Use username if available, otherwise fallback to name
            // For comp players, name IS the username
            // For human players, name might be "Player_<sessionId>" if username not stored
            (username != null && username.isNotEmpty) 
                ? username 
                : (playerNameRaw != null && playerNameRaw.isNotEmpty) 
                    ? playerNameRaw 
                    : 'Unknown',
            style: AppTextStyles.label().copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.white,
              // Add very prominent glow effect using status chip color logic (excludes 'waiting' and 'same_rank_window')
              shadows: statusChipColor != null
                  ? [
                      Shadow(
                        color: statusChipColor,
                        blurRadius: 16,
                      ),
                      Shadow(
                        color: statusChipColor.withOpacity(0.9),
                        blurRadius: 24,
                      ),
                      Shadow(
                        color: statusChipColor.withOpacity(0.7),
                        blurRadius: 32,
                      ),
                      Shadow(
                        color: statusChipColor.withOpacity(0.5),
                        blurRadius: 40,
                      ),
                      Shadow(
                        color: statusChipColor.withOpacity(0.3),
                        blurRadius: 48,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
        
        // Bottom: Cards aligned left and wrap
        const SizedBox(height: 8),
        Align(
          alignment: cardAlignment,
          child: hand.isNotEmpty
              ? _buildOpponentsCardsRow(hand, cardsToPeek, playerCollectionRankCards, drawnCard, player['id']?.toString() ?? '', knownCards, isInitialPeekPhase, player, nameAlignment: nameAlignment, currentPlayerStatus: currentPlayerStatus)
              : _buildEmptyHand(),
        ),
      ],
    );
  }

  Widget _buildOpponentsCardsRow(List<dynamic> cards, List<dynamic> cardsToPeek, List<dynamic> playerCollectionRankCards, Map<String, dynamic>? drawnCard, String playerId, Map<String, dynamic>? knownCards, bool isInitialPeekPhase, Map<String, dynamic> player, {MainAxisAlignment? nameAlignment, String? currentPlayerStatus}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : (MediaQuery.of(context).size.width > 0 ? MediaQuery.of(context).size.width * 0.5 : 500.0);
        // Ensure containerWidth is valid before calculations
        if (containerWidth <= 0 || !containerWidth.isFinite) {
          return const SizedBox.shrink();
        }
        final cardWidth = CardDimensions.clampCardWidth(containerWidth * 0.15); // 15% of container width, clamped to max
        final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
        final cardDimensions = Size(cardWidth, cardHeight);
        final stackOffset = cardHeight * CardDimensions.STACK_OFFSET_PERCENTAGE;
        final cardPadding = containerWidth * 0.02;
        
        final collectionRankCardIds = playerCollectionRankCards
            .where((c) => c is Map<String, dynamic>)
            .map((c) => (c as Map<String, dynamic>)['cardId']?.toString())
            .where((id) => id != null)
            .toSet();
        
        Map<String, Widget> collectionRankWidgets = {};
        
        for (int i = 0; i < cards.length; i++) {
          final card = cards[i];
          if (card == null) continue;
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          if (cardId == null) continue;
          final drawnCardId = drawnCard?['cardId']?.toString();
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          Map<String, dynamic>? peekedCardData;
          if (cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          Map<String, dynamic>? collectionRankCardData;
          if (playerCollectionRankCards.isNotEmpty) {
            for (var collectionCard in playerCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                break;
              }
            }
          }
          if (collectionRankCardData != null) {
            final cardDataToUse = isDrawnCard && drawnCard != null
                ? drawnCard 
                : (peekedCardData ?? collectionRankCardData);
            final cardKey = _getOrCreateCardKey(cardId, 'opponent_$playerId');
            final cardWidget = _buildOpponentCardWidget(cardDataToUse, isDrawnCard, playerId, false, cardDimensions, cardKey: cardKey);
            collectionRankWidgets[cardId] = cardWidget;
          }
        }
        
        // Build list of card widgets
        List<Widget> cardWidgets = [];
        
        for (int index = 0; index < cards.length; index++) {
          final card = cards[index];
          if (card == null) {
            cardWidgets.add(
              Padding(
                padding: EdgeInsets.only(right: cardPadding),
                child: _buildBlankCardSlot(cardDimensions),
              ),
            );
            continue;
          }
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          final drawnCardId = drawnCard?['cardId']?.toString();
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          Map<String, dynamic>? peekedCardData;
          if (cardId != null && cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          Map<String, dynamic>? collectionRankCardData;
          bool isCollectionRankCard = false;
          if (cardId != null && playerCollectionRankCards.isNotEmpty) {
            for (var collectionCard in playerCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                isCollectionRankCard = true;
                break;
              }
            }
          }
          final cardDataToUse = isDrawnCard && drawnCard != null 
              ? drawnCard 
              : (peekedCardData ?? collectionRankCardData ?? cardMap);
          
          if (isCollectionRankCard && collectionRankWidgets.containsKey(cardId)) {
            bool isFirstCollectionCard = true;
            for (int i = 0; i < index; i++) {
              final prevCard = cards[i];
              if (prevCard != null && prevCard is Map<String, dynamic>) {
                final prevCardId = prevCard['cardId']?.toString();
                if (prevCardId != null && collectionRankCardIds.contains(prevCardId)) {
                  isFirstCollectionCard = false;
                  break;
                }
              }
            }
            if (isFirstCollectionCard) {
              List<Widget> orderedCollectionWidgets = [];
              for (var collectionCard in playerCollectionRankCards) {
                if (collectionCard is Map<String, dynamic>) {
                  final collectionCardId = collectionCard['cardId']?.toString();
                  if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                    orderedCollectionWidgets.add(collectionRankWidgets[collectionCardId]!);
                  }
                }
              }
              final cardWidth = cardDimensions.width;
              final cardHeight = cardDimensions.height;
              final stackHeight = cardHeight + (orderedCollectionWidgets.length - 1) * stackOffset;
              final stackWidget = SizedBox(
                width: cardWidth,
                height: stackHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: orderedCollectionWidgets.asMap().entries.map((entry) {
                    return Positioned(
                      left: 0,
                      top: entry.key * stackOffset,
                      child: entry.value,
                    );
                  }).toList(),
                ),
              );
              cardWidgets.add(
                Padding(
                  padding: EdgeInsets.only(right: cardPadding),
                  child: stackWidget,
                ),
              );
            }
            // Skip non-first collection cards (they're already in the stack)
            continue;
          }
          if (cardId == null) {
            continue;
          }
          final cardKey = _getOrCreateCardKey(cardId, 'opponent_$playerId');
          final cardWidget = _buildOpponentCardWidget(cardDataToUse, isDrawnCard, playerId, false, cardDimensions, cardKey: cardKey, currentPlayerStatus: currentPlayerStatus);
          cardWidgets.add(
            Padding(
              padding: EdgeInsets.only(
                right: cardPadding,
                left: isDrawnCard ? cardPadding * 2 : 0,
              ),
              child: cardWidget,
            ),
          );
        }
        
        // Use Wrap widget to allow cards to wrap to next line
        return Wrap(
          spacing: 0, // Spacing is handled by card padding
          runSpacing: cardPadding, // Vertical spacing between wrapped rows
          children: cardWidgets,
        );
      },
    );
  }

  Widget _buildOpponentCardWidget(Map<String, dynamic> card, bool isDrawnCard, String playerId, bool isCollectionRankCard, Size cardDimensions, {GlobalKey? cardKey, String? currentPlayerStatus}) {
    final cardModel = CardModel.fromMap(card);
    final cardId = card['cardId']?.toString();
    final isSelected = cardId != null && _clickedCardId == cardId;
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    Widget cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions,
      config: CardDisplayConfig.forOpponent(),
      isSelected: isSelected,
      onTap: () => _handleOpponentCardClick(card, playerId),
    );
    
    // Apply glow effect based on current player status (for jack_swap and queen_peek)
    final glowColor = currentPlayerStatus != null 
        ? _getGlowColorForCards(currentPlayerStatus, false) 
        : null;
    
    if (glowColor != null && _glowAnimation != null) {
      return AnimatedBuilder(
        animation: _glowAnimation!,
        builder: (context, child) {
          final glowOpacity = _glowAnimation!.value;
          final glowDecoration = _buildGlowDecoration(glowColor, glowOpacity);
          return Container(
            decoration: glowDecoration,
            child: cardWidget,
          );
        },
      );
    }
    
    return cardWidget;
  }

  Widget _buildEmptyHand() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 20,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              'No cards',
              style: AppTextStyles.overline().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlankCardSlot([Size? cardDimensions]) {
    final dimensions = cardDimensions ?? CardDimensions.getUnifiedDimensions();
    final cardBackColor = HSLColor.fromColor(AppColors.primaryColor)
        .withSaturation(0.2)
        .toColor();
    // Use dynamic border radius from SSOT to match card widgets
    final borderRadius = CardDimensions.calculateBorderRadius(dimensions);
    return SizedBox(
      width: dimensions.width,
      height: dimensions.height,
      child: Container(
        decoration: BoxDecoration(
          color: cardBackColor,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: AppColors.borderDefault,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
      ),
    );
  }

  String? getClickedCardId() {
    return _clickedCardId;
  }

  void clearClickedCardId() {
    setState(() {
      _clickedCardId = null;
    });
  }

  void _handleOpponentCardClick(Map<String, dynamic> card, String cardOwnerId) async {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final currentPlayerStatus = _getCurrentUserStatus();
    
    if (currentPlayerStatus == 'jack_swap') {
      _logger.info('🃏 OpponentsPanelWidget: Status is jack_swap - opponent cards are interactive', isOn: LOGGING_SWITCH);
    }
    if (currentPlayerStatus == 'queen_peek' || currentPlayerStatus == 'jack_swap') {
      final cardId = card['cardId']?.toString();
      if (cardId != null) {
        setState(() {
          _clickedCardId = cardId;
        });
        
        if (currentPlayerStatus == 'queen_peek') {
          try {
            final queenPeekAction = PlayerAction.queenPeek(
              gameId: currentGameId,
              cardId: cardId,
              ownerId: cardOwnerId,
            );
            await queenPeekAction.execute();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Peeking at: ${card['rank']} of ${card['suit']}'
                ),
                  backgroundColor: AppColors.accentColor2,
                duration: Duration(seconds: 2),
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to peek at card: $e'),
                backgroundColor: AppColors.errorColor,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (currentPlayerStatus == 'jack_swap') {
          try {
            _logger.info('🃏 OpponentsPanelWidget: Card tapped during jack_swap - Card: $cardId, Player: $cardOwnerId, Game: $currentGameId', isOn: LOGGING_SWITCH);
            _logger.info('🃏 OpponentsPanelWidget: Current jack swap selection count: ${PlayerAction.getJackSwapSelectionCount()}', isOn: LOGGING_SWITCH);
            await PlayerAction.selectCardForJackSwap(
              cardId: cardId,
              playerId: cardOwnerId,
              gameId: currentGameId,
            );
            final selectionCount = PlayerAction.getJackSwapSelectionCount();
            _logger.info('🃏 OpponentsPanelWidget: After selection, jack swap count: $selectionCount', isOn: LOGGING_SWITCH);
            if (selectionCount == 1) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'First card selected: ${card['rank']} of ${card['suit']}. Select another card to swap.'
                  ),
                  backgroundColor: AppColors.warningColor,
                  duration: Duration(seconds: 2),
                ),
              );
            } else if (selectionCount == 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Second card selected: ${card['rank']} of ${card['suit']}. Swapping cards...'
                  ),
                  backgroundColor: AppColors.accentColor,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to select card for Jack swap: $e'),
                backgroundColor: AppColors.errorColor,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error: Card information incomplete'),
            backgroundColor: AppColors.errorColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with cards while status is "$currentPlayerStatus"'
          ),
          backgroundColor: AppColors.warningColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Color _getStatusChipColor(String status) {
    switch (status) {
      case 'waiting':
        return AppColors.statusWaiting;
      case 'ready':
        return AppColors.statusReady;
      case 'drawing_card':
        return AppColors.statusDrawing;
      case 'playing_card':
        return AppColors.statusPlaying;
      case 'same_rank_window':
        return AppColors.statusSameRank;
      case 'queen_peek':
        return AppColors.statusQueenPeek;
      case 'jack_swap':
        return AppColors.statusJackSwap;
      case 'peeking':
        return AppColors.statusPeeking;
      case 'initial_peek':
        return AppColors.statusInitialPeek;
      case 'winner':
        return AppColors.statusWinner;
      case 'finished':
        return AppColors.statusFinished;
      case 'disconnected':
        return AppColors.errorColor;
      default:
        return AppColors.textSecondary;
    }
  }

  /// Reusable glow effect decoration builder
  /// Returns a BoxDecoration with animated glow effect based on status color
  /// [statusColor] The color to use for the glow (from _getStatusChipColor)
  /// [glowOpacity] The current animation opacity value (from _glowAnimation)
  /// Returns null if glow should not be applied
  BoxDecoration? _buildGlowDecoration(Color statusColor, double glowOpacity) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(
          color: statusColor.withValues(alpha: 0.6 * glowOpacity),
          blurRadius: 6,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: statusColor.withValues(alpha: 0.4 * glowOpacity),
          blurRadius: 10,
          spreadRadius: 2,
        ),
        BoxShadow(
          color: statusColor.withValues(alpha: 0.2 * glowOpacity),
          blurRadius: 14,
          spreadRadius: 3,
        ),
      ],
    );
  }

  /// Determine if glow should be applied to cards based on current status
  /// [currentPlayerStatus] The current player's status
  /// [isMyHand] Whether this is for my hand (true) or opponent hand (false)
  /// Returns the status color if glow should be applied, null otherwise
  Color? _getGlowColorForCards(String currentPlayerStatus, bool isMyHand) {
    switch (currentPlayerStatus) {
      case 'playing_card':
        // During playing: apply to all cards in my hand
        return isMyHand ? _getStatusChipColor(currentPlayerStatus) : null;
      case 'jack_swap':
      case 'queen_peek':
        // During jack swap/queen peek: apply to all cards in all hands
        return _getStatusChipColor(currentPlayerStatus);
      case 'initial_peek':
      case 'same_rank_window':
        // During initial peek/same rank: apply to my hand only
        return isMyHand ? _getStatusChipColor(currentPlayerStatus) : null;
      default:
        return null;
    }
  }

  bool _shouldHighlightCurrentPlayer(String status) {
    if (status == 'waiting' || status == 'same_rank_window') {
      return false;
    }
    return true;
  }

  // ========== Game Board Methods ==========

  Widget _buildGameBoard() {
    // Update game board height in state after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateGameBoardHeight();
    });
    
    return Container(
      key: _gameBoardKey,
      padding: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Get the actual width of the gameboard row
          final gameboardRowWidth = constraints.maxWidth;
          
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDrawPile(),
              _buildMatchPot(gameboardRowWidth), // Match pot in the middle
              _buildDiscardPile(),
            ],
          );
        },
      ),
    );
  }
  
  /// Update game board height in StateManager (for overlay positioning)
  void _updateGameBoardHeight() {
    if (_gameBoardKey.currentContext != null) {
      final RenderBox renderBox = _gameBoardKey.currentContext!.findRenderObject() as RenderBox;
      final height = renderBox.size.height;
      final stateManager = StateManager();
      final currentGameBoardHeight = stateManager.getModuleState<Map<String, dynamic>>('dutch_game')?['gameBoardHeight'] as double?;
      
      if (currentGameBoardHeight == null || currentGameBoardHeight != height) {
        stateManager.updateModuleState('dutch_game', {
          'gameBoardHeight': height,
        });
      }
    }
  }

  // ========== Draw Pile Methods ==========

  Widget _buildDrawPile() {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get full draw pile list
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    
    // Check if player is in drawing status (similar to myHand logic)
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    final playerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
    final isDrawingStatus = playerStatus == 'drawing_card';
    final statusChipColor = isDrawingStatus ? _getStatusChipColor(playerStatus) : null;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (context) {
              final cardDimensions = CardDimensions.getUnifiedDimensions();
              
              Widget drawPileContent;
              
              if (drawPile.isEmpty) {
                // Empty draw pile - render placeholder
                final emptyKey = _getOrCreateCardKey('draw_pile_empty', 'draw_pile');
                drawPileContent = CardWidget(
                  key: emptyKey,
                  card: CardModel(
                    cardId: 'draw_pile_empty',
                    rank: '?',
                    suit: '?',
                    points: 0,
                  ),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forDrawPile(),
                  showBack: true,
                  onTap: _handleDrawPileClick,
                );
              } else {
                // Render all cards in draw pile with stacking effect
                // Only the top card is visible and clickable, but all are tracked for animation
                final topCardIndex = drawPile.length - 1;
                final topCardData = drawPile[topCardIndex] as Map<String, dynamic>? ?? {};
                
                // Create stacking effect with 2 additional cards behind
                final stackCards = <Widget>[];
                
                // Add 2 background cards with rotation and offset for stacking effect
                for (int i = 0; i < 2; i++) {
                  // Draw pile: 2° and 4° anticlockwise
                  final rotation = -(i + 1) * 2.0; // -2° and -4° (anticlockwise)
                  final offset = (i + 1) * 1.5; // 1.5px and 3px offset
                  // Add shadow to the last (bottom) card of the stack
                  final isBottomCard = i == 1; // Second card is the bottom one
                  stackCards.add(
                    Positioned.fill(
                      child: Transform.rotate(
                        angle: rotation * 3.14159 / 180, // Convert to radians
                        child: Transform.translate(
                          offset: Offset(offset, -offset),
                          child: isBottomCard
                              ? Container(
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Opacity(
                                    opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                    child: CardWidget(
                                      card: CardModel.fromMap(topCardData),
                                      dimensions: cardDimensions,
                                      config: CardDisplayConfig.forDrawPile(),
                                      showBack: true,
                                      onTap: null, // Background cards not clickable
                                    ),
                                  ),
                                )
                              : Opacity(
                                  opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                  child: CardWidget(
                                    card: CardModel.fromMap(topCardData),
                                    dimensions: cardDimensions,
                                    config: CardDisplayConfig.forDrawPile(),
                                    showBack: true,
                                    onTap: null, // Background cards not clickable
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                }
                
                // Add all actual cards in the pile (for animation tracking)
                for (final entry in drawPile.asMap().entries) {
                  final index = entry.key;
                  final cardData = entry.value as Map<String, dynamic>? ?? {};
                  final cardId = cardData['cardId']?.toString() ?? 'draw_pile_empty';
                  final cardKey = _getOrCreateCardKey(cardId, 'draw_pile');
                  final isTopCard = index == topCardIndex;
                  
                  stackCards.add(
                    Positioned.fill(
                      child: Opacity(
                        opacity: isTopCard ? 1.0 : 0.0, // Only top card visible
                        child: CardWidget(
                          key: cardKey,
                          card: CardModel.fromMap(cardData),
                          dimensions: cardDimensions,
                          config: CardDisplayConfig.forDrawPile(),
                          showBack: true,
                          onTap: isTopCard ? _handleDrawPileClick : null, // Only top card clickable
                        ),
                      ),
                    ),
                  );
                }
                
                drawPileContent = SizedBox(
                  width: cardDimensions.width,
                  height: cardDimensions.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: stackCards,
                  ),
                );
              }
              
              // Wrap with animated glow effect when in drawing status
              if (isDrawingStatus && statusChipColor != null && _glowAnimation != null) {
                return AnimatedBuilder(
                  animation: _glowAnimation!,
                  builder: (context, child) {
                    final glowOpacity = _glowAnimation!.value;
                    final glowDecoration = _buildGlowDecoration(statusChipColor, glowOpacity);
                    return Container(
                      decoration: glowDecoration,
                      child: drawPileContent,
                    );
                  },
                );
              }
              
              return drawPileContent;
            },
          ),
        ],
      ),
    );
  }

  String? getClickedPileType() {
    return _clickedPileType;
  }

  void clearClickedPileType() {
    setState(() {
      _clickedPileType = null;
    });
  }

  void _handleDrawPileClick() async {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = centerBoard['playerStatus']?.toString() ?? 'unknown';
    
    if (currentPlayerStatus == 'drawing_card') {
      try {
        final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
        if (currentGameId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Error: No active game found'),
              backgroundColor: AppColors.errorColor,
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }
        final drawAction = PlayerAction.playerDraw(
          pileType: 'draw_pile',
          gameId: currentGameId,
        );
        await drawAction.execute();
        setState(() {
          _clickedPileType = 'draw_pile';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Card drawn from draw pile'),
            backgroundColor: AppColors.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to draw card: $e'),
            backgroundColor: AppColors.errorColor,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with draw pile while status is "$currentPlayerStatus"'
          ),
          backgroundColor: AppColors.warningColor,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // ========== Discard Pile Methods ==========

  Widget _buildDiscardPile() {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get full discard pile list
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final hasCards = discardPile.isNotEmpty;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (context) {
              final cardDimensions = CardDimensions.getUnifiedDimensions();
              
              if (!hasCards) {
                // Empty discard pile
                final emptyKey = _getOrCreateCardKey('discard_pile_empty', 'discard_pile');
                return CardWidget(
                  key: emptyKey,
                  card: CardModel(
                    cardId: 'discard_pile_empty',
                    rank: '?',
                    suit: '?',
                    points: 0,
                  ),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forDiscardPile(),
                  showBack: true,
                  onTap: _handleDiscardPileClick,
                );
              }
              
              // Render all cards in discard pile with stacking effect
              // Only the top card is visible and clickable, but all are tracked for animation
              final topCardIndex = discardPile.length - 1;
              final topCardData = discardPile[topCardIndex] as Map<String, dynamic>? ?? {};
              
              // Create stacking effect with 2 additional cards behind
              final stackCards = <Widget>[];
              
              // Add 2 background cards with rotation and offset for stacking effect
              for (int i = 0; i < 2; i++) {
                // Discard pile: 2° and 4° clockwise
                final rotation = (i + 1) * 2.0; // 2° and 4° (clockwise)
                final offset = (i + 1) * 1.5; // 1.5px and 3px offset
                // Add shadow to the last (bottom) card of the stack
                final isBottomCard = i == 1; // Second card is the bottom one
                stackCards.add(
                  Positioned.fill(
                    child: Transform.rotate(
                      angle: rotation * 3.14159 / 180, // Convert to radians
                      child: Transform.translate(
                        offset: Offset(-offset, -offset), // Negative X for discard pile
                        child: isBottomCard
                            ? Container(
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Opacity(
                                  opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                  child: CardWidget(
                                    card: CardModel.fromMap(topCardData),
                                    dimensions: cardDimensions,
                                    config: CardDisplayConfig.forDiscardPile(),
                                    onTap: null, // Background cards not clickable
                                  ),
                                ),
                              )
                            : Opacity(
                                opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                child: CardWidget(
                                  card: CardModel.fromMap(topCardData),
                                  dimensions: cardDimensions,
                                  config: CardDisplayConfig.forDiscardPile(),
                                  onTap: null, // Background cards not clickable
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              }
              
              // Add all actual cards in the pile (for animation tracking)
              for (final entry in discardPile.asMap().entries) {
                final index = entry.key;
                final cardData = entry.value as Map<String, dynamic>? ?? {};
                final cardId = cardData['cardId']?.toString() ?? 'discard_pile_empty';
                final cardKey = _getOrCreateCardKey(cardId, 'discard_pile');
                final isTopCard = index == topCardIndex;
                
                stackCards.add(
                  Positioned.fill(
                    child: Opacity(
                      opacity: isTopCard ? 1.0 : 0.0, // Only top card visible
                      child: CardWidget(
                        key: cardKey,
                        card: CardModel.fromMap(cardData),
                        dimensions: cardDimensions,
                        config: CardDisplayConfig.forDiscardPile(),
                        onTap: isTopCard ? _handleDiscardPileClick : null, // Only top card clickable
                      ),
                    ),
                  ),
                );
              }
              
              return SizedBox(
                width: cardDimensions.width,
                height: cardDimensions.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: stackCards,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _handleDiscardPileClick() async {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'unknown';
    final gameState = dutchGameState['gameState'] as Map<String, dynamic>? ?? {};
    final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? true; // Default to true for backward compatibility
    
    // Block during same_rank_window and initial_peek phases - but only if collection mode is enabled
    if ((gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') && isClearAndCollect) {
      String reason = gamePhase == 'same_rank_window' 
        ? 'Cannot collect cards during same rank window'
        : 'Cannot collect cards during initial peek phase';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: AppColors.warningColor,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // If collection is disabled (isClearAndCollect: false), silently ignore clicks during same_rank_window
    if ((gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') && !isClearAndCollect) {
      return; // Silently ignore - collection is disabled in this game mode
    }
    
    try {
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      if (currentGameId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error: No active game found'),
            backgroundColor: AppColors.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      final collectAction = PlayerAction.collectFromDiscard(gameId: currentGameId);
      await collectAction.execute();
      setState(() {
        _clickedPileType = 'discard_pile';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to collect card: $e'),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ========== Match Pot Methods ==========

  Widget _buildMatchPot(double gameboardRowWidth) {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final matchPot = centerBoard['matchPot'] as int? ?? 0;
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'waiting';
    final isGameActive = dutchGameState['isGameActive'] ?? false;
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    
    // Check if this is a practice game (practice games start with 'practice_room_')
    final isPracticeGame = currentGameId.startsWith('practice_room_');
    
    // Only show match pot if not a practice game
    if (isPracticeGame) {
      return const SizedBox.shrink();
    }
    
    final shouldShowPot = isGameActive && gamePhase != 'waiting';
    
    // Calculate width: 20% of gameboard row width
    final calculatedWidth = gameboardRowWidth * 0.2;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Win',
            style: AppTextStyles.headingSmall().copyWith(
              color: shouldShowPot 
                  ? AppColors.primaryColor
                  : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/images/coins.png',
                width: calculatedWidth,
                fit: BoxFit.contain,
              ),
              Text(
                shouldShowPot ? matchPot.toString() : '—',
                style: AppTextStyles.headingLarge().copyWith(
                  color: AppColors.black,
                  shadows: [
                    Shadow(
                      offset: Offset.zero,
                      blurRadius: 4.0,
                      color: AppColors.white,
                    ),
                    Shadow(
                      offset: Offset.zero,
                      blurRadius: 8.0,
                      color: AppColors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========== My Hand Methods ==========

  /// Protect cardsToPeek data for 5 seconds (My Hand)
  void _protectMyHandCardsToPeek(List<dynamic> cardsToPeek) {
    _myHandCardsToPeekProtectionTimer?.cancel();
    _isMyHandCardsToPeekProtected = true;
    _protectedMyHandCardsToPeek = List<dynamic>.from(cardsToPeek);
    _myHandCardsToPeekProtectionTimer = Timer(Duration(seconds: 5), () {
      _clearMyHandCardsToPeekProtection();
    });
  }

  /// Clear cardsToPeek protection (My Hand)
  void _clearMyHandCardsToPeekProtection() {
    _isMyHandCardsToPeekProtected = false;
    _protectedMyHandCardsToPeek = null;
    _myHandCardsToPeekProtectionTimer?.cancel();
    _myHandCardsToPeekProtectionTimer = null;
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildMyHand() {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    final cards = myHand['cards'] as List<dynamic>? ?? [];
    final selectedIndex = myHand['selectedIndex'] ?? -1;
    final cardsToPeekFromState = dutchGameState['myCardsToPeek'] as List<dynamic>? ?? [];
    final protectedCardsToPeek = dutchGameState['protectedCardsToPeek'] as List<dynamic>?;
    final protectedTimestamp = dutchGameState['protectedCardsToPeekTimestamp'] as int?;
    final now = DateTime.now().millisecondsSinceEpoch;
    final isProtectedDataValid = protectedCardsToPeek != null && 
        protectedTimestamp != null && 
        (now - protectedTimestamp) < 5000;
    
    if (isProtectedDataValid && !_isMyHandCardsToPeekProtected) {
      _protectMyHandCardsToPeek(protectedCardsToPeek);
    }
    
    if (cardsToPeekFromState.isNotEmpty && !_isMyHandCardsToPeekProtected) {
      final hasFullCardData = cardsToPeekFromState.any((card) {
        if (card is Map<String, dynamic>) {
          final hasSuit = card.containsKey('suit') && card['suit'] != '?' && card['suit'] != null;
          final hasRank = card.containsKey('rank') && card['rank'] != '?' && card['rank'] != null;
          return hasSuit || hasRank;
        }
        return false;
      });
      if (hasFullCardData) {
        _protectMyHandCardsToPeek(cardsToPeekFromState);
      }
    }
    
    final cardsToPeek = _isMyHandCardsToPeekProtected && _protectedMyHandCardsToPeek != null
        ? _protectedMyHandCardsToPeek!
        : cardsToPeekFromState;
    
    final isGameActive = dutchGameState['isGameActive'] ?? false;
    final isMyTurn = dutchGameState['isMyTurn'] ?? false;
    final playerStatus = _getCurrentUserStatus(); // Use same source as status chip
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final finalRoundActive = gameState['finalRoundActive'] as bool? ?? false;
    final finalRoundCalledBy = gameState['finalRoundCalledBy']?.toString();
    // Get timer from game_state timerConfig (added during game initialization)
    // Safely convert Map<String, dynamic> to Map<String, int>
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final phase = gameState['phase'] as String?;
    // Calculate timer based on phase or status using timerConfig from game_state
    // Priority: Status is more specific than phase, so check status first
    int? turnTimeLimit;
    
    // Check status first (more specific than phase for player actions)
    if (playerStatus != null && playerStatus.isNotEmpty) {
      switch (playerStatus) {
        case 'initial_peek':
          turnTimeLimit = timerConfig['initial_peek'] ?? 15;
          break;
        case 'drawing_card':
          turnTimeLimit = timerConfig['drawing_card'] ?? 20;
          break;
        case 'playing_card':
          turnTimeLimit = timerConfig['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          turnTimeLimit = timerConfig['same_rank_window'] ?? 10;
          break;
        case 'queen_peek':
          turnTimeLimit = timerConfig['queen_peek'] ?? 15;
          break;
        case 'jack_swap':
          turnTimeLimit = timerConfig['jack_swap'] ?? 20;
          break;
        case 'peeking':
          turnTimeLimit = timerConfig['peeking'] ?? 10;
          break;
        case 'waiting':
          turnTimeLimit = timerConfig['waiting'] ?? 0;
          break;
        default:
          // If status doesn't match, fall through to phase check
          break;
      }
    }
    
    // If status didn't provide a timer (or status was null), check phase
    if (turnTimeLimit == null && phase != null && phase.isNotEmpty) {
      switch (phase) {
        case 'initial_peek':
          turnTimeLimit = timerConfig['initial_peek'] ?? 15;
          break;
        case 'player_turn':
        case 'playing':
          // For generic player_turn/playing phase, status should have been checked above
          // But if status wasn't available, use playing_card as default
          turnTimeLimit = timerConfig['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          turnTimeLimit = timerConfig['same_rank_window'] ?? 10;
          break;
        case 'queen_peek_window':
          turnTimeLimit = timerConfig['queen_peek'] ?? 15;
          break;
        case 'special_play_window':
          turnTimeLimit = timerConfig['jack_swap'] ?? 20;
          break;
        default:
          turnTimeLimit = timerConfig['default'] ?? 30;
      }
    }
    
    // Final fallback if neither status nor phase provided a timer
    turnTimeLimit ??= 30;
    
    // Ensure turnTimeLimit is valid (not 0, not negative, not NaN) to prevent division by zero in timer widget
    if (turnTimeLimit <= 0 || !turnTimeLimit.isFinite) {
      turnTimeLimit = 30; // Safe default
    }
    
    // Use DutchEventHandlerCallbacks.getCurrentUserId() to get sessionId (not userId)
    // This matches how players are identified in game_state (by sessionId)
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
    
    // Get current user's player data from game_state to retrieve profile picture
    // Profile picture is fetched when player joins and stored in player['profile_picture']
    final players = gameState['players'] as List<dynamic>? ?? [];
    Map<String, dynamic>? currentUserPlayer;
    try {
      currentUserPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (p) => p['id']?.toString() == currentUserId,
      );
    } catch (e) {
      // Player not found, will use fallback to StateManager
      currentUserPlayer = null;
    }
    final currentUserProfilePicture = currentUserPlayer?['profile_picture']?.toString();
    
    final hasPlayerCalledFinalRound = gameState['players'] != null
        ? (gameState['players'] as List<dynamic>?)
            ?.any((p) => p is Map<String, dynamic> && 
                p['id']?.toString() == currentUserId && 
                p['hasCalledFinalRound'] == true) ?? false
        : false;
    
    final actionError = dutchGameState['actionError'] as Map<String, dynamic>?;
    if (actionError != null) {
      final message = actionError['message']?.toString() ?? 'Action failed';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.warningColor,
            duration: const Duration(seconds: 3),
          ),
        );
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        StateManager().updateModuleState('dutch_game', {
          ...currentState,
          'actionError': null,
        });
      });
    }
    
    if (playerStatus != 'initial_peek' && _initialPeekSelectionCount > 0) {
      _initialPeekSelectionCount = 0;
      _initialPeekSelectedCardIds.clear();
    }
    
    // For timer color, always get the status chip color (including same_rank_window)
    final timerColor = _getStatusChipColor(playerStatus);
    
    // Update myhand height in state after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
_updateMyHandHeight();
    });
    
    return Container(
      key: _myHandKey,
      child: Padding(
        padding: const EdgeInsets.all(1.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Profile picture (circular, 1.5x status chip height)
                // Get profile picture from game_state player data first, then fallback to StateManager
                _buildPlayerProfilePicture(
                  _getCurrentUserId(),
                  profilePictureUrl: currentUserProfilePicture,
                ),
                const SizedBox(width: 8),
                Text(
                  'You',
                  style: AppTextStyles.headingSmall(),
                ),
                const Spacer(),
                if (isGameActive && isMyTurn && playerStatus == 'playing_card' && !finalRoundActive && !hasPlayerCalledFinalRound) ...[
                  GestureDetector(
                    onTap: () => _handleCallFinalRound(context, currentGameId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warningColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag,
                            size: 12,
                            color: AppColors.textOnAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Call Final Round',
                            style: AppTextStyles.bodySmall().copyWith(
                              color: AppColors.textOnAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (finalRoundActive) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warningColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          finalRoundCalledBy == _getCurrentUserId() 
                              ? Icons.flag 
                              : Icons.flag_outlined,
                          size: 12,
                          color: AppColors.textOnAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          finalRoundCalledBy == _getCurrentUserId()
                              ? 'You Called Final Round'
                              : 'Final Round Active',
                          style: AppTextStyles.bodySmall().copyWith(
                            color: AppColors.textOnAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (playerStatus != 'unknown')
                  PlayerStatusChip(
                    playerId: _getCurrentUserId(),
                    size: PlayerStatusChipSize.small,
                  ),
                // Show circular timer next to status chip (right side) when status is not 'waiting'
                // Note: 'jack_swap' and 'queen_peek' can occur out of turn and should show timer
                // Also show timer during 'same_rank_window' for my hand section
                if (playerStatus != 'waiting') ...[
                  const SizedBox(width: 6),
                  CircularTimerWidget(
                    key: ValueKey('timer_myhand_${playerStatus}'), // Reset timer when status changes
                    durationSeconds: turnTimeLimit,
                    size: 28.0, // Match profile picture size
                    color: timerColor,
                    backgroundColor: AppColors.surfaceVariant,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (cards.isEmpty)
              _buildMyHandEmptyHand()
            else
              _buildMyHandCardsGrid(cards, cardsToPeek, selectedIndex),
          ],
        ),
      ),
    );
  }

  Widget _buildMyHandEmptyHand() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              'No cards in hand',
              style: AppTextStyles.label().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyHandCardsGrid(List<dynamic> cards, List<dynamic> cardsToPeek, int selectedIndex) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final containerWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : (MediaQuery.of(context).size.width > 0 ? MediaQuery.of(context).size.width * 0.5 : 500.0);
            // Ensure containerWidth is valid before calculations
            if (containerWidth <= 0 || !containerWidth.isFinite) {
              return const SizedBox.shrink();
            }
            
            final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
            final currentPlayerStatus = _getCurrentUserStatus();
            final drawnCard = dutchGameState['myDrawnCard'] as Map<String, dynamic>?;
            final drawnCardId = drawnCard?['cardId']?.toString();
            final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
            final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
            final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
            final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
            final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
            final players = gameState['players'] as List<dynamic>? ?? [];
            final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
            
            List<dynamic> myCollectionRankCards = [];
            for (var player in players) {
              if (player is Map<String, dynamic> && player['id']?.toString() == currentUserId) {
                myCollectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
                break;
              }
            }
            
            final collectionRankCardIds = myCollectionRankCards
                .where((c) => c is Map<String, dynamic>)
                .map((c) => (c as Map<String, dynamic>)['cardId']?.toString())
                .where((id) => id != null)
                .toSet();
            
            Map<String, Widget> collectionRankWidgets = {};
            
            // Calculate card dimensions as 12% of container width, clamped to max
            final cardWidth = CardDimensions.clampCardWidth(containerWidth * 0.12); // 12% of container width, clamped to max
            final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
            final cardDimensions = Size(cardWidth, cardHeight);
            final stackOffset = cardHeight * CardDimensions.STACK_OFFSET_PERCENTAGE;
            final cardPadding = containerWidth * 0.02;
            const drawnCardExtraPadding = 16.0; // Extra left padding for drawn card
            
            for (int i = 0; i < cards.length; i++) {
              final card = cards[i];
              if (card == null) continue;
              final cardMap = card as Map<String, dynamic>;
              final cardId = cardMap['cardId']?.toString();
              if (cardId == null) continue;
              final isSelected = i == selectedIndex;
              final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
              Map<String, dynamic>? peekedCardData;
              if (cardsToPeek.isNotEmpty) {
                for (var peekedCard in cardsToPeek) {
                  if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                    peekedCardData = peekedCard;
                    break;
                  }
                }
              }
              Map<String, dynamic>? collectionRankCardData;
              if (myCollectionRankCards.isNotEmpty) {
                for (var collectionCard in myCollectionRankCards) {
                  if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                    collectionRankCardData = collectionCard;
                    break;
                  }
                }
              }
              if (collectionRankCardData != null) {
                final cardDataToUse = isDrawnCard && drawnCard != null
                    ? drawnCard 
                    : (peekedCardData ?? collectionRankCardData);
                // Use calculated dimensions from LayoutBuilder
                final cardKey = _getOrCreateCardKey(cardId, 'my_hand');
                final cardWidget = _buildMyHandCardWidget(cardDataToUse, isSelected, isDrawnCard, false, i, cardMap, cardKey, cardDimensions, currentPlayerStatus: currentPlayerStatus);
                collectionRankWidgets[cardId] = cardWidget;
              }
            }
        
        // Get current player status for glow effect (using same source as status chip)
        final currentPlayerStatusForGlow = _getCurrentUserStatus();
        
        // Build all card widgets with fixed dimensions
        List<Widget> cardWidgets = [];
        for (int index = 0; index < cards.length; index++) {
          final card = cards[index];
          
          // Handle null cards (blank slots from same-rank plays)
          if (card == null) {
            cardWidgets.add(
              Padding(
                padding: EdgeInsets.only(right: cardPadding),
                child: _buildMyHandBlankCardSlot(cardDimensions),
              ),
            );
            continue;
          }
          
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          final isSelected = index == selectedIndex;
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          
          // Check if this card is in cardsToPeek (peeked cards have full data)
          Map<String, dynamic>? peekedCardData;
          if (cardId != null && cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          
          // Check if this card is in player's collection_rank_cards
          Map<String, dynamic>? collectionRankCardData;
          bool isCollectionRankCard = false;
          if (cardId != null && myCollectionRankCards.isNotEmpty) {
            for (var collectionCard in myCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                isCollectionRankCard = true;
                break;
              }
            }
          }
          
          // Determine which data to use (priority: drawn card > peeked card > collection rank card > ID-only hand card)
          // For drawn cards, ensure we have full data (rank and suit not '?')
          Map<String, dynamic> cardDataToUse;
          if (isDrawnCard && drawnCard != null) {
            // Validate drawn card has full data
            final hasFullData = drawnCard.containsKey('rank') && 
                               drawnCard['rank'] != null && 
                               drawnCard['rank'] != '?' &&
                               drawnCard.containsKey('suit') && 
                               drawnCard['suit'] != null && 
                               drawnCard['suit'] != '?';
            if (hasFullData) {
              cardDataToUse = drawnCard;
            } else {
              // Drawn card data is incomplete, fall back to other sources
              cardDataToUse = peekedCardData ?? collectionRankCardData ?? cardMap;
            }
          } else {
            cardDataToUse = peekedCardData ?? collectionRankCardData ?? cardMap;
          }
          
          // If this is a collection rank card, render the stack (only once, at the first collection card)
          if (isCollectionRankCard && collectionRankWidgets.containsKey(cardId)) {
            // Check if this is the first collection card in the hand
            bool isFirstCollectionCard = true;
            for (int i = 0; i < index; i++) {
              final prevCard = cards[i];
              if (prevCard != null && prevCard is Map<String, dynamic>) {
                final prevCardId = prevCard['cardId']?.toString();
                if (prevCardId != null && collectionRankCardIds.contains(prevCardId)) {
                  isFirstCollectionCard = false;
                  break;
                }
              }
            }
            
            if (isFirstCollectionCard) {
              // This is the first collection card, render the entire stack
              // Get all collection rank widgets in order
              List<Widget> orderedCollectionWidgets = [];
              for (var collectionCard in myCollectionRankCards) {
                if (collectionCard is Map<String, dynamic>) {
                  final collectionCardId = collectionCard['cardId']?.toString();
                  if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                    // Rebuild collection widgets with fixed dimensions
                    final collectionCardKey = _getOrCreateCardKey(collectionCardId, 'my_hand');
                    final collectionCardWidget = _buildMyHandCardWidget(
                      collectionCard, 
                      false, 
                      false, 
                      false, 
                      index, 
                      collectionCard, 
                      collectionCardKey,
                      cardDimensions,
                      currentPlayerStatus: currentPlayerStatusForGlow,
                    );
                    orderedCollectionWidgets.add(collectionCardWidget);
                  }
                }
              }
              
              // Stack needs size constraint to render
              final cardWidth = cardDimensions.width;
              final stackHeight = cardHeight + (orderedCollectionWidgets.length - 1) * stackOffset;
              
              final stackWidget = SizedBox(
                width: cardWidth,
                height: stackHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: orderedCollectionWidgets.asMap().entries.map((entry) {
                    // Stack cards perfectly on top of each other with offset
                    return Positioned(
                      left: 0,
                      top: entry.key * stackOffset,
                      child: entry.value,
                    );
                  }).toList(),
                ),
              );
              
              cardWidgets.add(
                Padding(
                  padding: EdgeInsets.only(
                    right: cardPadding,
                    left: isDrawnCard ? drawnCardExtraPadding : 0,
                  ),
                  child: stackWidget,
                ),
              );
            }
            // Skip non-first collection cards (they're already in the stack)
          } else {
            // Normal card rendering (non-collection rank)
            if (cardId == null) {
              continue;
            }
            final cardKey = _getOrCreateCardKey(cardId, 'my_hand');
            final cardWidget = _buildMyHandCardWidget(
              cardDataToUse, 
              isSelected, 
              isDrawnCard, 
              false, 
              index, 
              cardMap, 
              cardKey,
              cardDimensions,
              currentPlayerStatus: currentPlayerStatusForGlow,
            );
            
              cardWidgets.add(
                Padding(
                  padding: EdgeInsets.only(
                    right: cardPadding,
                    left: isDrawnCard ? drawnCardExtraPadding : 0,
                  ),
                  child: cardWidget,
                ),
              );
            }
          }
          
          // Use Wrap widget to allow cards to wrap to next line
          return Wrap(
            spacing: 0, // Spacing is handled by card padding
            runSpacing: cardPadding, // Vertical spacing between wrapped rows
            alignment: WrapAlignment.start, // Align cards to the left
            children: cardWidgets,
          );
        },
      );
      },
    );
  }

  String _getCurrentUserId() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    return loginState['userId']?.toString() ?? '';
  }

  /// Get current user's status from the same source as PlayerStatusChip
  /// This ensures consistency between status chip and card lighting
  String _getCurrentUserStatus() {
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    return myHand['playerStatus']?.toString() ?? 'unknown';
  }

  /// Update myhand section height in state (for overlay positioning)
  void _updateMyHandHeight() {
    if (!mounted) return;
    
    final context = _myHandKey.currentContext;
    if (context != null) {
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final height = renderBox.size.height;
        StateManager().updateModuleState('dutch_game', {
          'myHandHeight': height,
        });
      }
    }
  }

  Future<void> _handleCallFinalRound(BuildContext context, String gameId) async {
    _logger.info('🎯 MyHandWidget - _handleCallFinalRound called with gameId: $gameId', isOn: LOGGING_SWITCH);
    if (_isProcessingAction) {
      _logger.info('🚫 MyHandWidget - Action already in progress, ignoring call final round', isOn: LOGGING_SWITCH);
      return;
    }
    if (gameId.isEmpty) {
      _logger.warning('⚠️ MyHandWidget - gameId is empty', isOn: LOGGING_SWITCH);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error: No active game found'),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    try {
      setState(() {
        _isProcessingAction = true;
      });
      _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true (call final round)', isOn: LOGGING_SWITCH);
      _logger.info('🎯 MyHandWidget - Creating PlayerAction.callFinalRound with gameId: $gameId', isOn: LOGGING_SWITCH);
      final callFinalRoundAction = PlayerAction.callFinalRound(gameId: gameId);
      _logger.info('🎯 MyHandWidget - Executing callFinalRoundAction...', isOn: LOGGING_SWITCH);
      await callFinalRoundAction.execute();
      _logger.info('✅ MyHandWidget - callFinalRoundAction.execute() completed', isOn: LOGGING_SWITCH);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isProcessingAction = false;
          });
          _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (call final round)', isOn: LOGGING_SWITCH);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Final Round Called! All players will get one last turn.'),
          backgroundColor: AppColors.warningColor,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingAction = false;
        });
        _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (call final round error)', isOn: LOGGING_SWITCH);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to call final round: $e'),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleMyHandCardSelection(BuildContext context, int index, Map<String, dynamic> card) async {
    if (_isProcessingAction) {
      _logger.info('🚫 MyHandWidget - Action already in progress, ignoring card selection', isOn: LOGGING_SWITCH);
      return;
    }
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentMyHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = _getCurrentUserStatus();
    _logger.info('🎯 MyHandWidget - Card tapped: ${card['cardId']}, Status: $currentPlayerStatus', isOn: LOGGING_SWITCH);
      
    if (currentPlayerStatus == 'jack_swap') {
      _logger.info('🃏 MyHandWidget: Status is jack_swap - cards are interactive', isOn: LOGGING_SWITCH);
    }
    if (currentPlayerStatus == 'playing_card' || 
        currentPlayerStatus == 'jack_swap' || 
        currentPlayerStatus == 'queen_peek' ||
        currentPlayerStatus == 'same_rank_window' ||
        currentPlayerStatus == 'initial_peek') {
      _logger.info('🎮 MyHandWidget - Status matches allowed statuses: $currentPlayerStatus', isOn: LOGGING_SWITCH);
      final updatedMyHand = {
        ...currentMyHand,
        'selectedIndex': index,
        'selectedCard': card,
      };
      StateManager().updateModuleState('dutch_game', {
        ...currentState,
        'myHand': updatedMyHand,
      });
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      _logger.info('🎮 MyHandWidget - currentGameId: $currentGameId', isOn: LOGGING_SWITCH);
      if (currentGameId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error: No active game found'),
            backgroundColor: AppColors.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      try {
        _logger.info('🎮 MyHandWidget - Inside try block, checking status: $currentPlayerStatus', isOn: LOGGING_SWITCH);
        if (currentPlayerStatus == 'same_rank_window') {
          _logger.info('🎮 MyHandWidget - Status is same_rank_window', isOn: LOGGING_SWITCH);
          final sameRankAction = PlayerAction.sameRankPlay(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
          await sameRankAction.execute();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Same Rank Play: ${card['rank']} of ${card['suit']}'
              ),
              backgroundColor: AppColors.infoColor,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (currentPlayerStatus == 'jack_swap') {
          final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
          _logger.info('🃏 MyHandWidget: Card tapped during jack_swap - Card: ${card['cardId']}, Player: $currentUserId, Game: $currentGameId', isOn: LOGGING_SWITCH);
          _logger.info('🃏 MyHandWidget: Current jack swap selection count: ${PlayerAction.getJackSwapSelectionCount()}', isOn: LOGGING_SWITCH);
          await PlayerAction.selectCardForJackSwap(
            cardId: card['cardId']?.toString() ?? '',
            playerId: currentUserId,
            gameId: currentGameId,
          );
          final selectionCount = PlayerAction.getJackSwapSelectionCount();
          _logger.info('🃏 MyHandWidget: After selection, jack swap count: $selectionCount', isOn: LOGGING_SWITCH);
          if (selectionCount == 1) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'First card selected: ${card['rank']} of ${card['suit']}. Select another card to swap.'
                ),
                backgroundColor: AppColors.warningColor,
                duration: Duration(seconds: 2),
              ),
            );
          } else if (selectionCount == 2) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Second card selected: ${card['rank']} of ${card['suit']}. Swapping cards...'
                ),
                backgroundColor: AppColors.accentColor,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else if (currentPlayerStatus == 'queen_peek') {
          final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
          final queenPeekAction = PlayerAction.queenPeek(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
            ownerId: currentUserId,
          );
          await queenPeekAction.execute();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Peeking at: ${card['rank']} of ${card['suit']}'
              ),
              backgroundColor: AppColors.accentColor2,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (currentPlayerStatus == 'initial_peek') {
          final cardId = card['cardId']?.toString() ?? '';
          if (cardId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Invalid card data'),
                backgroundColor: AppColors.errorColor,
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }

          // Check if we're in demo mode
          final games = currentState['games'] as Map<String, dynamic>? ?? {};
          final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
          final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
          final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
          final gameType = gameState['gameType']?.toString() ?? 'normal';
          final isDemoMode = gameType == 'demo';

          if (isDemoMode) {
            // Demo mode: use DemoFunctionality to show card details
            _logger.info('🎮 MyHandWidget: Demo mode - adding card to initial peek via DemoFunctionality', isOn: LOGGING_SWITCH);
            
            // Check if already selected (using DemoFunctionality's tracking)
            final demoSelectedIds = DemoFunctionality.instance.getInitialPeekSelectedCardIds();
            if (demoSelectedIds.contains(cardId)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Card already selected'),
                  backgroundColor: AppColors.warningColor,
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }

            // Add card to initial peek (this will update myCardsToPeek in state)
            final selectedCount = await DemoFunctionality.instance.addCardToInitialPeek(cardId);
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Card $selectedCount/2 selected'
                ),
                backgroundColor: AppColors.infoColor,
                duration: Duration(seconds: 2),
              ),
            );

            // If 2 cards selected, complete the initial peek
            if (selectedCount == 2) {
              await Future.delayed(Duration(milliseconds: 500));
              final completedInitialPeekAction = PlayerAction.completedInitialPeek(
                gameId: currentGameId,
                cardIds: DemoFunctionality.instance.getInitialPeekSelectedCardIds(),
              );
              await completedInitialPeekAction.execute();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Initial peek completed! You have looked at 2 cards.'
                  ),
                  backgroundColor: AppColors.successColor,
                  duration: Duration(seconds: 3),
                ),
              );
              // Note: DemoFunctionality._handleCompletedInitialPeek already clears the tracking set
              // Cards remain visible in myCardsToPeek so user can see both cards they peeked at
            }
          } else {
            // Normal mode: use existing logic
          if (_initialPeekSelectedCardIds.contains(cardId)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Card already selected'),
                backgroundColor: AppColors.warningColor,
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
          if (_initialPeekSelectionCount < 2) {
            _initialPeekSelectedCardIds.add(cardId);
            _initialPeekSelectionCount++;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Card ${_initialPeekSelectionCount}/2 selected'
                ),
                backgroundColor: AppColors.infoColor,
                duration: Duration(seconds: 2),
              ),
            );
            if (_initialPeekSelectionCount == 2) {
              await Future.delayed(Duration(milliseconds: 500));
              final completedInitialPeekAction = PlayerAction.completedInitialPeek(
                gameId: currentGameId,
                cardIds: _initialPeekSelectedCardIds,
              );
              await completedInitialPeekAction.execute();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Initial peek completed! You have looked at 2 cards.'
                  ),
                  backgroundColor: AppColors.successColor,
                  duration: Duration(seconds: 3),
                ),
              );
              _initialPeekSelectionCount = 0;
              _initialPeekSelectedCardIds.clear();
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'You have already peeked at 2 cards. Initial peek is complete.'
                ),
                backgroundColor: AppColors.warningColor,
                duration: Duration(seconds: 2),
              ),
            );
            }
          }
        } else {
          _logger.info('🎮 MyHandWidget - Entering else block for playing_card status', isOn: LOGGING_SWITCH);
          setState(() {
            _isProcessingAction = true;
          });
          _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true', isOn: LOGGING_SWITCH);
          _logger.info('🎮 MyHandWidget - About to execute playerPlayCard: cardId=${card['cardId']}, gameId=$currentGameId', isOn: LOGGING_SWITCH);
          try {
          final playAction = PlayerAction.playerPlayCard(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
            _logger.info('🎮 MyHandWidget - Calling playAction.execute()', isOn: LOGGING_SWITCH);
          await playAction.execute();
          } catch (e, stackTrace) {
            _logger.error('❌ MyHandWidget - Error executing playAction: $e', isOn: LOGGING_SWITCH);
            _logger.error('❌ MyHandWidget - Stack trace: $stackTrace', isOn: LOGGING_SWITCH);
            rethrow;
          }
          _logger.info('🎮 MyHandWidget - playAction.execute() completed', isOn: LOGGING_SWITCH);
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isProcessingAction = false;
              });
              _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false', isOn: LOGGING_SWITCH);
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isProcessingAction = false;
          });
          _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (error case)', isOn: LOGGING_SWITCH);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to execute action: $e'),
            backgroundColor: AppColors.errorColor,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with hand cards while status is "$currentPlayerStatus"'
          ),
          backgroundColor: AppColors.warningColor,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildMyHandBlankCardSlot([Size? cardDimensions]) {
    final dimensions = cardDimensions ?? CardDimensions.getUnifiedDimensions();
    final cardBackColor = HSLColor.fromColor(AppColors.primaryColor)
        .withSaturation(0.2)
        .toColor();
    // Use dynamic border radius from SSOT to match card widgets
    final borderRadius = CardDimensions.calculateBorderRadius(dimensions);
    return SizedBox(
      width: dimensions.width,
      height: dimensions.height,
      child: Container(
        decoration: BoxDecoration(
          color: cardBackColor,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: AppColors.borderDefault,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
      ),
    );
  }

  Widget _buildMyHandCardWidget(Map<String, dynamic> card, bool isSelected, bool isDrawnCard, bool isCollectionRankCard, int index, Map<String, dynamic> cardMap, GlobalKey cardKey, Size cardDimensions, {String? currentPlayerStatus}) {
    // For drawn cards in user's hand, always show face up
    // Ensure card has full data - if not, try to get it from the cardMap or myDrawnCard in state
    Map<String, dynamic> cardDataToUse = card;
    if (isDrawnCard) {
      // For drawn cards, we MUST have full data (rank, suit, points)
      // Check if current card data is incomplete
      final hasIncompleteData = !card.containsKey('rank') || 
                                card['rank'] == null || 
                                card['rank'] == '?' ||
                                !card.containsKey('suit') || 
                                card['suit'] == null || 
                                card['suit'] == '?';
      
      if (hasIncompleteData) {
        // Try to get full data from cardMap first
        if (cardMap.containsKey('rank') && 
            cardMap['rank'] != null && 
            cardMap['rank'] != '?' &&
            cardMap.containsKey('suit') && 
            cardMap['suit'] != null && 
            cardMap['suit'] != '?') {
          cardDataToUse = cardMap;
        } else {
          // Last resort: try to get from myDrawnCard in state
          final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
          final myDrawnCard = dutchGameState['myDrawnCard'] as Map<String, dynamic>?;
          if (myDrawnCard != null && 
              myDrawnCard.containsKey('rank') && 
              myDrawnCard['rank'] != null && 
              myDrawnCard['rank'] != '?' &&
              myDrawnCard.containsKey('suit') && 
              myDrawnCard['suit'] != null && 
              myDrawnCard['suit'] != '?') {
            cardDataToUse = myDrawnCard;
          }
        }
      }
    }
    
    final cardModel = CardModel.fromMap(cardDataToUse);
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    // For drawn cards in user's hand, show face up ONLY if we have complete data
    // If data is still incomplete after all fallbacks, show back to avoid blank white card
    // For other cards, show back if face down or missing full data
    final hasCompleteData = cardModel.hasFullData && 
                           cardModel.rank != '?' && 
                           cardModel.suit != '?';
    final shouldShowBack = isDrawnCard 
        ? !hasCompleteData  // Show back if data is incomplete
        : (cardModel.isFaceDown || !cardModel.hasFullData);
    
    // Use provided cardDimensions (may be rescaled to fit container)
    Widget cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions,
      config: CardDisplayConfig.forMyHand(),
      showBack: shouldShowBack,
      isSelected: isSelected,
      onTap: () => _handleMyHandCardSelection(context, index, cardMap),
    );
    
    if (isDrawnCard) {
      cardWidget = SizedBox(
        width: cardDimensions.width,
        height: cardDimensions.height,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFBC02D).withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: cardWidget,
        ),
      );
    }
    
    // Apply glow effect based on current player status
    final glowColor = currentPlayerStatus != null 
        ? _getGlowColorForCards(currentPlayerStatus, true) 
        : null;
    
    if (glowColor != null && _glowAnimation != null) {
      return AnimatedBuilder(
        animation: _glowAnimation!,
        builder: (context, child) {
          final glowOpacity = _glowAnimation!.value;
          final glowDecoration = _buildGlowDecoration(glowColor, glowOpacity);
          return Container(
            decoration: glowDecoration,
            child: cardWidget,
          );
        },
      );
    }
    
    return cardWidget;
  }

  bool _shouldHighlightStatus(String status) {
    if (status == 'waiting' || status == 'same_rank_window') {
      return false;
    }
    return true;
  }

  /// Build circular profile picture widget
  /// Size is 1.5x the status chip height (small size)
  /// Shows user's profile picture if available, otherwise shows default icon
  /// [playerId] The player's session ID
  /// [profilePictureUrl] Optional profile picture URL (for opponents from player data)
  Widget _buildPlayerProfilePicture(String playerId, {String? profilePictureUrl}) {
    // Status chip small size: padding (2*2=4px) + icon (12px) + text (~10px) ≈ 18-20px
    // 1.5x = ~27-30px, using 28px for a nice round number
    const double profilePictureSize = 28.0;
    
    // Get profile picture URL from game_state (SSOT) if not provided
    if (profilePictureUrl == null || profilePictureUrl.isEmpty) {
      final stateManager = StateManager();
      final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
      final gameData = games[currentGameId] as Map<String, dynamic>?;
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      final players = gameState?['players'] as List<dynamic>? ?? [];
      
      // Find player in game_state by playerId
      try {
        final player = players.cast<Map<String, dynamic>>().firstWhere(
          (p) => p['id']?.toString() == playerId,
        );
        profilePictureUrl = player['profile_picture']?.toString();
      } catch (e) {
        // Player not found in game_state, profilePictureUrl remains null
      }
    }
    
    // If we have a profile picture URL, show it
    if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      return Container(
        width: profilePictureSize,
        height: profilePictureSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceVariant,
          border: Border.all(
            color: AppColors.borderDefault,
            width: 1.5,
          ),
        ),
        child: ClipOval(
          child: Image.network(
            profilePictureUrl,
            width: profilePictureSize,
            height: profilePictureSize,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to icon if image fails to load
              return Icon(
                Icons.person,
                size: profilePictureSize * 0.6,
                color: AppColors.textSecondary,
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              // Show loading indicator while image loads
              return Center(
                child: SizedBox(
                  width: profilePictureSize * 0.4,
                  height: profilePictureSize * 0.4,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    
    // Fallback to default icon
    return Container(
      width: profilePictureSize,
      height: profilePictureSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceVariant,
        border: Border.all(
          color: AppColors.borderDefault,
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.person,
        size: profilePictureSize * 0.6, // Icon is 60% of container size
        color: AppColors.textSecondary,
      ),
    );
  }
}

