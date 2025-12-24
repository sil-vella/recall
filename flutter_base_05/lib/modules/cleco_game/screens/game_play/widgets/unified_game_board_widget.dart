import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import 'player_status_chip_widget.dart';
import '../../../managers/player_action.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../cleco_game/managers/cleco_event_handler_callbacks.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../utils/card_position_scanner.dart';
import '../../../utils/card_animation_detector.dart';

const bool LOGGING_SWITCH = true; // Enabled for testing and debugging

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

class _UnifiedGameBoardWidgetState extends State<UnifiedGameBoardWidget> {
  final Logger _logger = Logger();
  
  // ========== Opponents Panel State ==========
  String? _clickedCardId;
  bool _isCardsToPeekProtected = false;
  List<dynamic>? _protectedCardsToPeek;
  Timer? _cardsToPeekProtectionTimer;
  
  // ========== Draw Pile State ==========
  String? _clickedPileType;
  
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
  
  /// CardPositionScanner instance
  final CardPositionScanner _positionScanner = CardPositionScanner();
  
  /// CardAnimationDetector instance
  final CardAnimationDetector _animationDetector = CardAnimationDetector();

  @override
  void dispose() {
    _cardsToPeekProtectionTimer?.cancel();
    _myHandCardsToPeekProtectionTimer?.cancel();
    _positionScanner.clearPositions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Schedule position scanning after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scanCardPositions();
        });
        
        return Column(
          children: [
            // Opponents Panel Section
            _buildOpponentsPanel(),
            
            SizedBox(height: AppPadding.smallPadding.top),
            
            // Game Board Section (draw pile, discard pile, match pot)
            _buildGameBoard(),
            
            SizedBox(height: AppPadding.smallPadding.top),
            
            // My Hand Section
            _buildMyHand(),
          ],
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
  
  /// Scan all card positions after build
  void _scanCardPositions() {
    if (!mounted) return;
    
    _logger.info('🎬 UnifiedGameBoardWidget: Starting position scan', isOn: LOGGING_SWITCH);
    
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final Map<String, CardKeyData> cardKeys = {};
    
    // Collect all card keys with metadata
    
    // 1. Draw Pile - Track all cards in draw pile
    final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
    final games = clecoGameState['games'] as Map<String, dynamic>? ?? {};
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
    final opponentsPanel = clecoGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    final cardsToPeekFromState = clecoGameState['myCardsToPeek'] as List<dynamic>? ?? [];
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
    final myHand = clecoGameState['myHand'] as Map<String, dynamic>? ?? {};
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
    _logger.info('🛡️ CardsToPeek protection activated for 5 seconds', isOn: LOGGING_SWITCH);
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
    _logger.info('🛡️ CardsToPeek protection cleared', isOn: LOGGING_SWITCH);
  }

  /// Build the opponents panel widget
  Widget _buildOpponentsPanel() {
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final opponentsPanel = clecoGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    final currentTurnIndex = opponentsPanel['currentTurnIndex'] ?? -1;
    final cardsToPeekFromState = clecoGameState['myCardsToPeek'] as List<dynamic>? ?? [];
    
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
        _logger.info('🛡️ OpponentsPanelWidget: Activated protection for ${cardsToPeekFromState.length} cards', isOn: LOGGING_SWITCH);
      }
    }
    
    final cardsToPeek = _isCardsToPeekProtected && _protectedCardsToPeek != null
        ? _protectedCardsToPeek!
        : cardsToPeekFromState;
    
    final otherPlayers = opponents;
    final isGameActive = clecoGameState['isGameActive'] ?? false;
    final playerStatus = clecoGameState['playerStatus']?.toString() ?? 'unknown';
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (opponents.isEmpty)
              _buildEmptyOpponents()
            else
              _buildOpponentsGrid(otherPlayers, cardsToPeek, currentTurnIndex, isGameActive, playerStatus),
          ],
        ),
      ),
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
        final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        final currentPlayerRaw = clecoGameState['currentPlayer'];
        Map<String, dynamic>? currentPlayerData;
        if (currentPlayerRaw == null || currentPlayerRaw == 'null' || currentPlayerRaw == '') {
          currentPlayerData = null;
        } else if (currentPlayerRaw is Map<String, dynamic>) {
          currentPlayerData = currentPlayerRaw;
        } else {
          currentPlayerData = null;
        }
        final currentPlayerId = currentPlayerData?['id']?.toString() ?? '';
        final opponentsPanelSlice = clecoGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
        final currentPlayerStatus = opponentsPanelSlice['currentPlayerStatus']?.toString() ?? 'unknown';
        final gamePhase = clecoGameState['gamePhase']?.toString() ?? 'waiting';
        final isInitialPeekPhase = gamePhase == 'initial_peek';
    
        return Column(
          children: opponents.asMap().entries.map((entry) {
            final index = entry.key;
            final player = entry.value as Map<String, dynamic>;
            final playerId = player['id']?.toString() ?? '';
            final isCurrentTurn = index == currentTurnIndex;
            final isCurrentPlayer = playerId == currentPlayerId;
            final knownCards = player['known_cards'] as Map<String, dynamic>?;
            
            return SizedBox(
              width: double.infinity,
              child: _buildOpponentCard(
                  player, 
                  cardsToPeek, 
                  player['collection_rank_cards'] as List<dynamic>? ?? [],
                  isCurrentTurn, 
                  isGameActive, 
                  isCurrentPlayer, 
                  currentPlayerStatus,
                  knownCards,
                  isInitialPeekPhase
                ),
              );
          }).toList(),
        );
      },
    );
  }

  Widget _buildOpponentCard(Map<String, dynamic> player, List<dynamic> cardsToPeek, List<dynamic> playerCollectionRankCards, bool isCurrentTurn, bool isGameActive, bool isCurrentPlayer, String currentPlayerStatus, Map<String, dynamic>? knownCards, bool isInitialPeekPhase) {
    final playerName = player['name']?.toString() ?? 'Unknown Player';
    final hand = player['hand'] as List<dynamic>? ?? [];
    final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
    final hasCalledCleco = player['hasCalledCleco'] ?? false;
    final playerStatus = player['status']?.toString() ?? 'unknown';
    
    final shouldHighlightBackground = _shouldHighlightCurrentPlayer(playerStatus) 
        || (isCurrentPlayer && playerStatus == 'same_rank_window');
    final statusChipColor = shouldHighlightBackground ? _getStatusChipColor(playerStatus) : null;
    final shouldHighlight = isCurrentPlayer && _shouldHighlightCurrentPlayer(playerStatus);
    
    if (drawnCard != null) {
      final drawnCardId = drawnCard['cardId']?.toString() ?? 'unknown';
      final drawnCardRank = drawnCard['rank']?.toString() ?? 'unknown';
      final drawnCardSuit = drawnCard['suit']?.toString() ?? 'unknown';
      final isIdOnly = drawnCardRank == '?' && drawnCardSuit == '?';
      _logger.info('🔍 OpponentsPanel: Player $playerName (${player['id']}) drawnCard - cardId: $drawnCardId, rank: $drawnCardRank, suit: $drawnCardSuit, isIdOnly: $isIdOnly', isOn: LOGGING_SWITCH);
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerPadding = constraints.maxWidth.isFinite 
            ? constraints.maxWidth * 0.02 
            : 16.0;
        final backgroundColor = shouldHighlightBackground && statusChipColor != null
            ? statusChipColor.withOpacity(0.1) 
            : (isCurrentTurn 
                ? Color.lerp(AppColors.white, AppColors.black, 0.02) ?? AppColors.white
                : AppColors.white);
        final shouldShowBorder = shouldHighlight;
        final borderColor = shouldShowBorder && statusChipColor != null
            ? statusChipColor
            : (isCurrentTurn ? AppColors.accentColor2 : AppColors.borderDefault);
        
        return Container(
          padding: EdgeInsets.all(containerPadding),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: (shouldShowBorder || isCurrentTurn) ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: shouldHighlightBackground && statusChipColor != null
                    ? statusChipColor.withOpacity(0.1) 
                    : AppColors.black.withOpacity(0.05),
                blurRadius: shouldHighlightBackground ? 4 : 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: hand.isNotEmpty
                      ? _buildOpponentsCardsRow(hand, cardsToPeek, playerCollectionRankCards, drawnCard, player['id']?.toString() ?? '', knownCards, isInitialPeekPhase, player)
                      : _buildEmptyHand(),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (hasCalledCleco) ...[
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
                        Expanded(
                          child: Text(
                            playerName,
                            textAlign: TextAlign.right,
                            style: AppTextStyles.label().copyWith(
                              fontWeight: FontWeight.bold,
                              color: isCurrentPlayer && statusChipColor != null 
                                  ? statusChipColor 
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (playerStatus != 'unknown') ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: PlayerStatusChip(
                          playerId: player['id']?.toString() ?? '',
                          size: shouldHighlight ? PlayerStatusChipSize.medium : PlayerStatusChipSize.small,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOpponentsCardsRow(List<dynamic> cards, List<dynamic> cardsToPeek, List<dynamic> playerCollectionRankCards, Map<String, dynamic>? drawnCard, String playerId, Map<String, dynamic>? knownCards, bool isInitialPeekPhase, Map<String, dynamic> player) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth.isFinite 
            ? constraints.maxWidth 
            : MediaQuery.of(context).size.width * 0.5;
        final cardWidth = containerWidth * 0.10;
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
        
        return SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              if (card == null) {
                return Padding(
                  padding: EdgeInsets.only(right: cardPadding),
                  child: _buildBlankCardSlot(cardDimensions),
                );
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
                  return Padding(
                    padding: EdgeInsets.only(right: cardPadding),
                    child: stackWidget,
                  );
                } else {
                  return const SizedBox.shrink();
                }
              }
              if (cardId == null) {
                return const SizedBox.shrink();
              }
              final cardKey = _getOrCreateCardKey(cardId, 'opponent_$playerId');
              final cardWidget = _buildOpponentCardWidget(cardDataToUse, isDrawnCard, playerId, false, cardDimensions, cardKey: cardKey);
              return Padding(
                padding: EdgeInsets.only(
                  right: cardPadding,
                  left: isDrawnCard ? cardPadding * 2 : 0,
                ),
                child: cardWidget,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildOpponentCardWidget(Map<String, dynamic> card, bool isDrawnCard, String playerId, bool isCollectionRankCard, Size cardDimensions, {GlobalKey? cardKey}) {
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
    return SizedBox(
      width: dimensions.width,
      height: dimensions.height,
      child: Container(
        decoration: BoxDecoration(
          color: cardBackColor,
          borderRadius: BorderRadius.circular(6),
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
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
    final myHand = clecoGameState['myHand'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
    
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

  bool _shouldHighlightCurrentPlayer(String status) {
    if (status == 'waiting' || status == 'same_rank_window') {
      return false;
    }
    return true;
  }

  // ========== Game Board Methods ==========

  Widget _buildGameBoard() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildDrawPile(),
            const SizedBox(width: 16),
            _buildDiscardPile(),
            const SizedBox(width: 16),
            _buildMatchPot(),
          ],
        ),
      ),
    );
  }

  // ========== Draw Pile Methods ==========

  Widget _buildDrawPile() {
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
    final games = clecoGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get full draw pile list
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Draw',
            style: AppTextStyles.headingSmall(),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final cardDimensions = CardDimensions.getUnifiedDimensions();
              
              if (drawPile.isEmpty) {
                // Empty draw pile - render placeholder
                final emptyKey = _getOrCreateCardKey('draw_pile_empty', 'draw_pile');
                return CardWidget(
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
              }
              
              // Render all cards in draw pile (stacked, all at same position)
              // Only the top card is visible, but all are tracked for animation
              return SizedBox(
                width: cardDimensions.width,
                height: cardDimensions.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: drawPile.asMap().entries.map((entry) {
                    final index = entry.key;
                    final cardData = entry.value as Map<String, dynamic>? ?? {};
                    final cardId = cardData['cardId']?.toString() ?? 'draw_pile_empty';
                    
                    // Get or create key for this card
                    final cardKey = _getOrCreateCardKey(cardId, 'draw_pile');
                    
                    // Only show the top card (last in list), but render all for tracking
                    final isTopCard = index == drawPile.length - 1;
                    
                    return Positioned.fill(
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
                    );
                  }).toList(),
                ),
              );
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
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final centerBoard = clecoGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = centerBoard['playerStatus']?.toString() ?? 'unknown';
    
    if (currentPlayerStatus == 'drawing_card') {
      try {
        final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
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
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
    final games = clecoGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get full discard pile list
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final hasCards = discardPile.isNotEmpty;
    
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Last Played',
            style: AppTextStyles.headingSmall(),
          ),
          const SizedBox(height: 12),
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
              
              // Render all cards in discard pile (stacked, all at same position)
              // Only the top card is visible, but all are tracked for animation
              return SizedBox(
                width: cardDimensions.width,
                height: cardDimensions.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: discardPile.asMap().entries.map((entry) {
                    final index = entry.key;
                    final cardData = entry.value as Map<String, dynamic>? ?? {};
                    final cardId = cardData['cardId']?.toString() ?? 'discard_pile_empty';
                    
                    // Get or create key for this card
                    final cardKey = _getOrCreateCardKey(cardId, 'discard_pile');
                    
                    // Only show the top card (last in list), but render all for tracking
                    final isTopCard = index == discardPile.length - 1;
                    
                    return Positioned.fill(
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
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _handleDiscardPileClick() async {
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final gamePhase = clecoGameState['gamePhase']?.toString() ?? 'unknown';
    
    if (gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') {
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
    
    try {
      final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
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

  Widget _buildMatchPot() {
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final centerBoard = clecoGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final matchPot = centerBoard['matchPot'] as int? ?? 0;
    final gamePhase = clecoGameState['gamePhase']?.toString() ?? 'waiting';
    final isGameActive = clecoGameState['isGameActive'] ?? false;
    
    final shouldShowPot = isGameActive && gamePhase != 'waiting';
    
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Match Pot',
            style: AppTextStyles.headingSmall(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: shouldShowPot 
                  ? AppColors.primaryColor.withOpacity(0.1)
                  : AppColors.widgetContainerBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: shouldShowPot 
                    ? AppColors.primaryColor.withOpacity(0.3)
                    : AppColors.borderDefault.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.monetization_on,
                  color: shouldShowPot 
                      ? AppColors.primaryColor
                      : AppColors.textSecondary,
                  size: 24,
                ),
                const SizedBox(height: 8),
                Text(
                  shouldShowPot ? matchPot.toString() : '—',
                  style: AppTextStyles.headingMedium().copyWith(
                    color: shouldShowPot 
                        ? AppColors.primaryColor
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'coins',
                  style: AppTextStyles.bodySmall().copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
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
    _logger.info('🛡️ CardsToPeek protection activated for 5 seconds', isOn: LOGGING_SWITCH);
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
    _logger.info('🛡️ CardsToPeek protection cleared', isOn: LOGGING_SWITCH);
  }

  Widget _buildMyHand() {
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final myHand = clecoGameState['myHand'] as Map<String, dynamic>? ?? {};
    final cards = myHand['cards'] as List<dynamic>? ?? [];
    final selectedIndex = myHand['selectedIndex'] ?? -1;
    final cardsToPeekFromState = clecoGameState['myCardsToPeek'] as List<dynamic>? ?? [];
    final protectedCardsToPeek = clecoGameState['protectedCardsToPeek'] as List<dynamic>?;
    final protectedTimestamp = clecoGameState['protectedCardsToPeekTimestamp'] as int?;
    final now = DateTime.now().millisecondsSinceEpoch;
    final isProtectedDataValid = protectedCardsToPeek != null && 
        protectedTimestamp != null && 
        (now - protectedTimestamp) < 5000;
    
    _logger.info('🛡️ MyHandWidget: cardsToPeekFromState.length: ${cardsToPeekFromState.length}, protectedCardsToPeek.length: ${protectedCardsToPeek?.length ?? 0}, isProtectedDataValid: $isProtectedDataValid, isProtected: $_isMyHandCardsToPeekProtected', isOn: LOGGING_SWITCH);
    
    if (isProtectedDataValid && !_isMyHandCardsToPeekProtected) {
      _protectMyHandCardsToPeek(protectedCardsToPeek);
      _logger.info('🛡️ MyHandWidget: Activated protection from state sync for ${protectedCardsToPeek.length} cards', isOn: LOGGING_SWITCH);
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
        _logger.info('🛡️ MyHandWidget: Activated protection from state for ${cardsToPeekFromState.length} cards', isOn: LOGGING_SWITCH);
      }
    }
    
    final cardsToPeek = _isMyHandCardsToPeekProtected && _protectedMyHandCardsToPeek != null
        ? _protectedMyHandCardsToPeek!
        : cardsToPeekFromState;
    
    _logger.info('🛡️ MyHandWidget: Final cardsToPeek.length: ${cardsToPeek.length}', isOn: LOGGING_SWITCH);
    
    final isGameActive = clecoGameState['isGameActive'] ?? false;
    final isMyTurn = clecoGameState['isMyTurn'] ?? false;
    final playerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
    final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
    final games = clecoGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final finalRoundActive = gameState['finalRoundActive'] as bool? ?? false;
    final finalRoundCalledBy = gameState['finalRoundCalledBy']?.toString();
    final currentUserId = _getCurrentUserId();
    final hasPlayerCalledFinalRound = gameState['players'] != null
        ? (gameState['players'] as List<dynamic>?)
            ?.any((p) => p is Map<String, dynamic> && 
                p['id']?.toString() == currentUserId && 
                p['hasCalledFinalRound'] == true) ?? false
        : false;
    
    final actionError = clecoGameState['actionError'] as Map<String, dynamic>?;
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
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        StateManager().updateModuleState('cleco_game', {
          ...currentState,
          'actionError': null,
        });
      });
    }
    
    _logger.info('🃏 MyHandWidget - playerStatus: $playerStatus', isOn: LOGGING_SWITCH);
    _logger.info('🃏 MyHandWidget - cards.length: ${cards.length}', isOn: LOGGING_SWITCH);
    _logger.info('🃏 MyHandWidget - cardsToPeek.length: ${cardsToPeek.length}', isOn: LOGGING_SWITCH);
    if (cardsToPeek.isNotEmpty) {
      _logger.info('🃏 MyHandWidget - cardsToPeek IDs: ${cardsToPeek.map((c) => c['cardId']).toList()}', isOn: LOGGING_SWITCH);
    }
    _logger.info('🃏 MyHandWidget - myHand keys: ${myHand.keys.toList()}', isOn: LOGGING_SWITCH);
    _logger.info('🃏 MyHandWidget - clecoGameState keys: ${clecoGameState.keys.toList()}', isOn: LOGGING_SWITCH);
    final myHandCards = currentGame['myHandCards'] as List<dynamic>? ?? [];
    _logger.info('🃏 MyHandWidget - currentGameId: $currentGameId', isOn: LOGGING_SWITCH);
    _logger.info('🃏 MyHandWidget - myHandCards.length: ${myHandCards.length}', isOn: LOGGING_SWITCH);
    
    if (playerStatus != 'initial_peek' && _initialPeekSelectionCount > 0) {
      _initialPeekSelectionCount = 0;
      _initialPeekSelectedCardIds.clear();
    }
    
    final shouldHighlight = _shouldHighlightStatus(playerStatus);
    final statusChipColor = shouldHighlight ? _getStatusChipColor(playerStatus) : null;
    final backgroundColor = shouldHighlight && statusChipColor != null
        ? statusChipColor.withValues(alpha: 0.1)
        : AppColors.widgetContainerBackground;
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: shouldHighlight && statusChipColor != null
            ? Border.all(
                color: statusChipColor,
                width: 2,
              )
            : null,
        boxShadow: shouldHighlight && statusChipColor != null
            ? [
                BoxShadow(
                  color: statusChipColor.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
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
        final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        final drawnCard = clecoGameState['myDrawnCard'] as Map<String, dynamic>?;
        final drawnCardId = drawnCard?['cardId']?.toString();
        final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
        final games = clecoGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
        final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
        final players = gameState['players'] as List<dynamic>? ?? [];
        final currentUserId = ClecoEventHandlerCallbacks.getCurrentUserId();
        
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
            final cardKey = _getOrCreateCardKey(cardId, 'my_hand');
            final cardWidget = _buildMyHandCardWidget(cardDataToUse, isSelected, isDrawnCard, false, i, cardMap, cardKey);
            collectionRankWidgets[cardId] = cardWidget;
          }
        }
        
        final cardHeight = CardDimensions.getUnifiedHeight();
        final stackOffset = CardDimensions.getUnifiedStackOffset();
        
        return SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              if (card == null) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildMyHandBlankCardSlot(),
                );
              }
              final cardMap = card as Map<String, dynamic>;
              final cardId = cardMap['cardId']?.toString();
              final isSelected = index == selectedIndex;
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
              if (cardId != null && myCollectionRankCards.isNotEmpty) {
                for (var collectionCard in myCollectionRankCards) {
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
                  for (var collectionCard in myCollectionRankCards) {
                    if (collectionCard is Map<String, dynamic>) {
                      final collectionCardId = collectionCard['cardId']?.toString();
                      if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                        orderedCollectionWidgets.add(collectionRankWidgets[collectionCardId]!);
                      }
                    }
                  }
                  final cardDimensions = CardDimensions.getUnifiedDimensions();
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
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: stackWidget,
                  );
                } else {
                  return const SizedBox.shrink();
                }
              }
              if (cardId == null) {
                return const SizedBox.shrink();
              }
              final cardKey = _getOrCreateCardKey(cardId, 'my_hand');
              final cardWidget = _buildMyHandCardWidget(cardDataToUse, isSelected, isDrawnCard, false, index, cardMap, cardKey);
              return Padding(
                padding: EdgeInsets.only(
                  right: 8,
                  left: isDrawnCard ? 16 : 0,
                ),
                child: cardWidget,
              );
            },
          ),
        );
      },
    );
  }

  String _getCurrentUserId() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    return loginState['userId']?.toString() ?? '';
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
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final currentMyHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = currentMyHand['playerStatus']?.toString() ?? 'unknown';
      
    if (currentPlayerStatus == 'jack_swap') {
      _logger.info('🃏 MyHandWidget: Status is jack_swap - cards are interactive', isOn: LOGGING_SWITCH);
    }
    if (currentPlayerStatus == 'playing_card' || 
        currentPlayerStatus == 'jack_swap' || 
        currentPlayerStatus == 'queen_peek' ||
        currentPlayerStatus == 'same_rank_window' ||
        currentPlayerStatus == 'initial_peek') {
      final updatedMyHand = {
        ...currentMyHand,
        'selectedIndex': index,
        'selectedCard': card,
      };
      StateManager().updateModuleState('cleco_game', {
        ...currentState,
        'myHand': updatedMyHand,
      });
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
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
        if (currentPlayerStatus == 'same_rank_window') {
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
          final currentUserId = ClecoEventHandlerCallbacks.getCurrentUserId();
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
          final currentUserId = ClecoEventHandlerCallbacks.getCurrentUserId();
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
        } else {
          setState(() {
            _isProcessingAction = true;
          });
          _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true', isOn: LOGGING_SWITCH);
          final playAction = PlayerAction.playerPlayCard(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
          await playAction.execute();
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

  Widget _buildMyHandBlankCardSlot() {
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    return SizedBox(
      width: cardDimensions.width,
      height: cardDimensions.height,
      child: Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.borderDefault,
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.space_bar,
              size: 24,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              'Empty',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyHandCardWidget(Map<String, dynamic> card, bool isSelected, bool isDrawnCard, bool isCollectionRankCard, int index, Map<String, dynamic> cardMap, GlobalKey cardKey) {
    final cardModel = CardModel.fromMap(card);
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    final cardDimensions = CardDimensions.getUnifiedDimensions();
    
    Widget cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions,
      config: CardDisplayConfig.forMyHand(),
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
    
    return cardWidget;
  }

  bool _shouldHighlightStatus(String status) {
    if (status == 'waiting' || status == 'same_rank_window') {
      return false;
    }
    return true;
  }
}

