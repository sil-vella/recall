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

// Logging switch
const bool LOGGING_SWITCH = false; // Enabled for animation debugging - Animation ID system

/// Widget to display the player's hand
/// 
/// This widget subscribes to the myHand state slice and displays:
/// - All cards in the player's hand
/// - Card selection functionality
/// - Visual representation of each card
/// - Dynamic add/remove cards based on state changes
/// - Initial peek functionality (2 card selection during initial_peek status)
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class MyHandWidget extends StatefulWidget {
  const MyHandWidget({Key? key}) : super(key: key);

  @override
  State<MyHandWidget> createState() => _MyHandWidgetState();
}

class _MyHandWidgetState extends State<MyHandWidget> {
  final Logger _logger = Logger();
  
  // Local state for initial peek card selections
  int _initialPeekSelectionCount = 0;
  List<String> _initialPeekSelectedCardIds = [];
  
  // Local flag to prevent rapid action execution (frontend-only, doesn't update backend state)
  bool _isProcessingAction = false;
  
  // Protection mechanism for cardsToPeek
  bool _isCardsToPeekProtected = false;
  List<dynamic>? _protectedCardsToPeek;
  Timer? _cardsToPeekProtectionTimer;

  /// Protect cardsToPeek data for 5 seconds
  void _protectCardsToPeek(List<dynamic> cardsToPeek) {
    // Cancel existing timer if any
    _cardsToPeekProtectionTimer?.cancel();
    
    // Set protection flag and cache data
    _isCardsToPeekProtected = true;
    _protectedCardsToPeek = List<dynamic>.from(cardsToPeek);
    
    // Start 5-second timer
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
    
    // Trigger rebuild to use state value
    if (mounted) {
      setState(() {});
    }
    
    _logger.info('🛡️ CardsToPeek protection cleared', isOn: LOGGING_SWITCH);
  }

  @override
  void dispose() {
    _cardsToPeekProtectionTimer?.cancel();
    _cardsToPeekProtectionTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        
        // Get myHand state slice
        final myHand = clecoGameState['myHand'] as Map<String, dynamic>? ?? {};
        final cards = myHand['cards'] as List<dynamic>? ?? [];
        final selectedIndex = myHand['selectedIndex'] ?? -1;
        final selectedCard = myHand['selectedCard'] as Map<String, dynamic>?;
        
        // Get cardsToPeek from state
        final cardsToPeekFromState = clecoGameState['myCardsToPeek'] as List<dynamic>? ?? [];
        
        // Check for protected data stored by _syncWidgetStatesFromGameState
        final protectedCardsToPeek = clecoGameState['protectedCardsToPeek'] as List<dynamic>?;
        final protectedTimestamp = clecoGameState['protectedCardsToPeekTimestamp'] as int?;
        
        // Check if protected data is still valid (within 5 seconds)
        final now = DateTime.now().millisecondsSinceEpoch;
        final isProtectedDataValid = protectedCardsToPeek != null && 
            protectedTimestamp != null && 
            (now - protectedTimestamp) < 5000;
        
        _logger.info('🛡️ MyHandWidget: cardsToPeekFromState.length: ${cardsToPeekFromState.length}, protectedCardsToPeek.length: ${protectedCardsToPeek?.length ?? 0}, isProtectedDataValid: $isProtectedDataValid, isProtected: $_isCardsToPeekProtected', isOn: LOGGING_SWITCH);
        
        // If we have valid protected data from state sync, activate local protection
        if (isProtectedDataValid && !_isCardsToPeekProtected) {
          _protectCardsToPeek(protectedCardsToPeek);
          _logger.info('🛡️ MyHandWidget: Activated protection from state sync for ${protectedCardsToPeek.length} cards', isOn: LOGGING_SWITCH);
        }
        
        // Also check if current state has full card data (fallback)
        if (cardsToPeekFromState.isNotEmpty && !_isCardsToPeekProtected) {
          final hasFullCardData = cardsToPeekFromState.any((card) {
            if (card is Map<String, dynamic>) {
              final hasSuit = card.containsKey('suit') && card['suit'] != '?' && card['suit'] != null;
              final hasRank = card.containsKey('rank') && card['rank'] != '?' && card['rank'] != null;
              return hasSuit || hasRank;
            }
            return false;
          });
          
          if (hasFullCardData) {
            _protectCardsToPeek(cardsToPeekFromState);
            _logger.info('🛡️ MyHandWidget: Activated protection from state for ${cardsToPeekFromState.length} cards', isOn: LOGGING_SWITCH);
          }
        }
        
        // Use protected data if available, otherwise use state value
        final cardsToPeek = _isCardsToPeekProtected && _protectedCardsToPeek != null
            ? _protectedCardsToPeek!
            : cardsToPeekFromState;
        
        _logger.info('🛡️ MyHandWidget: Final cardsToPeek.length: ${cardsToPeek.length}', isOn: LOGGING_SWITCH);
        
        // Get additional game state for context
        final gamePhase = clecoGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = clecoGameState['isGameActive'] ?? false;
        final isMyTurn = clecoGameState['isMyTurn'] ?? false;
        // Get playerStatus from myHand slice (computed from SSOT)
        final playerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
        
        // Check what's in the games map
        final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
        final games = clecoGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
        final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
        
        // Check final round status from games map
        final finalRoundActive = gameState['finalRoundActive'] as bool? ?? false;
        final finalRoundCalledBy = gameState['finalRoundCalledBy']?.toString();
        final currentUserId = _getCurrentUserId();
        final hasPlayerCalledFinalRound = gameState['players'] != null
            ? (gameState['players'] as List<dynamic>?)
                ?.any((p) => p is Map<String, dynamic> && 
                    p['id']?.toString() == currentUserId && 
                    p['hasCalledFinalRound'] == true) ?? false
            : false;
        
        
        // Check for action errors and display snackbar
        final actionError = clecoGameState['actionError'] as Map<String, dynamic>?;
        if (actionError != null) {
          final message = actionError['message']?.toString() ?? 'Action failed';
          
          // Show snackbar with error message
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: AppColors.warningColor,
                duration: const Duration(seconds: 3),
              ),
            );
            
            // Clear the error after showing
            final currentState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
            StateManager().updateModuleState('cleco_game', {
              ...currentState,
              'actionError': null,
            });
          });
        }
        
        // Debug logging
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
        
        // Reset initial peek state when not in initial_peek status
        if (playerStatus != 'initial_peek' && _initialPeekSelectionCount > 0) {
          _initialPeekSelectionCount = 0;
          _initialPeekSelectedCardIds.clear();
        }
        
        return _buildMyHandCard(
          cards: cards,
          cardsToPeek: cardsToPeek,
          selectedIndex: selectedIndex,
          selectedCard: selectedCard,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
          playerStatus: playerStatus,
          finalRoundActive: finalRoundActive,
          finalRoundCalledBy: finalRoundCalledBy,
          hasPlayerCalledFinalRound: hasPlayerCalledFinalRound,
          currentGameId: currentGameId,
        );
      },
    );
  }

  /// Get status chip color for a given status (matches PlayerStatusChip logic)
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

  /// Check if a status should trigger highlighting (excludes "waiting" and "same_rank_window")
  bool _shouldHighlightStatus(String status) {
    if (status == 'waiting' || status == 'same_rank_window') {
      return false;
    }
    return true;
  }

  /// Build the my hand card widget
  Widget _buildMyHandCard({
    required List<dynamic> cards,
    required List<dynamic> cardsToPeek,
    required int selectedIndex,
    required Map<String, dynamic>? selectedCard,
    required String gamePhase,
    required bool isGameActive,
    required bool isMyTurn,
    required String playerStatus,
    required bool finalRoundActive,
    required String? finalRoundCalledBy,
    required bool hasPlayerCalledFinalRound,
    required String currentGameId,
  }) {
    // Get status chip color for background overlay
    final shouldHighlight = _shouldHighlightStatus(playerStatus);
    final statusChipColor = shouldHighlight ? _getStatusChipColor(playerStatus) : null;
    
    // Calculate background color - apply status color overlay if highlighting
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
            // Title and Status - aligned right
            Row(
              children: [
                Text(
                  'You',
                  style: AppTextStyles.headingSmall(),
                ),
                const Spacer(),
                // Call Final Round chip (matches status chip styling)
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
                  // Show indicator if final round is active (matches status chip styling)
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
                // Player status indicator - aligned right
                if (playerStatus != 'unknown')
                  PlayerStatusChip(
                    playerId: _getCurrentUserId(),
                    size: PlayerStatusChipSize.small,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Cards display
            if (cards.isEmpty)
              _buildEmptyHand()
            else
              _buildCardsGrid(cards, cardsToPeek, selectedIndex),
            

          ],
        ),
      ),
    );
  }

  /// Build empty hand state
  Widget _buildEmptyHand() {
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

  /// Build the cards grid using the new CardWidget system
  Widget _buildCardsGrid(List<dynamic> cards, List<dynamic> cardsToPeek, int selectedIndex) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        final drawnCard = clecoGameState['myDrawnCard'] as Map<String, dynamic>?;
        final drawnCardId = drawnCard?['cardId']?.toString();
        
        // Get current player's collection rank cards from games map
        final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
        final games = clecoGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
        final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
        final players = gameState['players'] as List<dynamic>? ?? [];
        
        // Get current user ID - use helper that handles both practice and multiplayer modes
        final currentUserId = ClecoEventHandlerCallbacks.getCurrentUserId();
        
        // Find current player's collection rank cards
        List<dynamic> myCollectionRankCards = [];
        for (var player in players) {
          if (player is Map<String, dynamic> && player['id']?.toString() == currentUserId) {
            myCollectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
            break;
          }
        }
        
        // Build list of card IDs that are collection rank cards
        final collectionRankCardIds = myCollectionRankCards
            .where((c) => c is Map<String, dynamic>)
            .map((c) => (c as Map<String, dynamic>)['cardId']?.toString())
            .where((id) => id != null)
            .toSet();
        
        // Pre-build collection rank widgets map - ALL CARDS USE SAME BUILD PROCESS
        Map<String, Widget> collectionRankWidgets = {};
        
        // First pass: build all collection rank widgets with same build process as normal cards
        for (int i = 0; i < cards.length; i++) {
          final card = cards[i];
          if (card == null) continue;
          
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          if (cardId == null) continue;
          
          // Get the same parameters as normal card building
          final isSelected = i == selectedIndex;
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          
          // Check if this card is in cardsToPeek (peeked cards have full data)
          Map<String, dynamic>? peekedCardData;
          if (cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          
          // Check if this card is a collection rank card
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
            // Determine which data to use (same priority as normal cards)
            // collectionRankCardData is guaranteed non-null here, so no need for ?? cardMap fallback
            final cardDataToUse = isDrawnCard && drawnCard != null
                ? drawnCard 
                : (peekedCardData ?? collectionRankCardData);
            
            // Build the collection rank card widget with SAME BUILD PROCESS as normal cards
            // Use default dimensions here - will be rebuilt with calculated dimensions in LayoutBuilder
            final cardKey = GlobalKey(debugLabel: 'card_$cardId');
            final defaultDimensions = CardDimensions.getUnifiedDimensions();
            final cardWidget = _buildCardWidget(cardDataToUse, isSelected, isDrawnCard, false, i, cardMap, cardKey, defaultDimensions);
            collectionRankWidgets[cardId] = cardWidget;
          }
        }
        
        // Use LayoutBuilder to get container width and calculate card dimensions
        // Auto-rescale cards if they would overflow, maintaining 5:7 aspect ratio
        return LayoutBuilder(
          builder: (context, constraints) {
            // Get container width - prioritize constraints, but ensure we have a value immediately
            // If constraints are not yet available, use a reasonable default based on screen width
            double containerWidth;
            if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
              containerWidth = constraints.maxWidth;
            } else {
              // Fallback: use screen width minus padding as estimate
              // This ensures we have a value immediately, even if constraints aren't ready
              final screenWidth = MediaQuery.of(context).size.width;
              containerWidth = screenWidth > 0 ? screenWidth : 500; // Final fallback
            }
            
            // Get default unified dimensions
            final defaultDimensions = CardDimensions.getUnifiedDimensions();
            final defaultCardWidth = defaultDimensions.width; // 70px
            const cardPadding = 8.0; // Padding between cards
            const drawnCardExtraPadding = 16.0; // Extra left padding for drawn card
            
            // Count non-null cards (excluding blank slots)
            int nonNullCardCount = 0;
            bool hasDrawnCard = false;
            for (var card in cards) {
              if (card != null) {
                nonNullCardCount++;
                final cardMap = card as Map<String, dynamic>;
                final cardId = cardMap['cardId']?.toString();
                if (drawnCardId != null && cardId == drawnCardId) {
                  hasDrawnCard = true;
                }
              }
            }
            
            // Calculate total width needed with default size
            // Count total items (cards + blank slots) for padding calculation
            int totalItems = cards.length;
            double totalWidthNeeded = 0;
            for (int i = 0; i < cards.length; i++) {
              final card = cards[i];
              if (card != null) {
                final cardMap = card as Map<String, dynamic>;
                final cardId = cardMap['cardId']?.toString();
                final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
                totalWidthNeeded += defaultCardWidth;
                if (isDrawnCard) {
                  totalWidthNeeded += drawnCardExtraPadding;
                }
              } else {
                // Blank slot still takes space
                totalWidthNeeded += defaultCardWidth;
              }
              // Add padding after each item except the last
              if (i < cards.length - 1) {
                totalWidthNeeded += cardPadding;
              }
            }
            
            // Calculate card dimensions - rescale if needed
            // Add safety margin (8px) to prevent rounding errors and small overflows
            const safetyMargin = 8.0;
            Size cardDimensions;
            if (totalWidthNeeded > (containerWidth - safetyMargin) && nonNullCardCount > 0) {
              // Need to rescale - calculate new width that fits all cards
              // Account for padding between all items and drawn card extra padding
              final totalPadding = (totalItems - 1) * cardPadding;
              final drawnCardPadding = hasDrawnCard ? drawnCardExtraPadding : 0;
              final availableWidth = containerWidth - totalPadding - drawnCardPadding - safetyMargin;
              final newCardWidth = availableWidth / totalItems;
              
              // Maintain 5:7 aspect ratio
              final newCardHeight = newCardWidth / CardDimensions.CARD_ASPECT_RATIO;
              cardDimensions = Size(newCardWidth, newCardHeight);
              
              _logger.info(
                'MyHandWidget: Rescaling cards - containerWidth=$containerWidth, '
                'totalWidthNeeded=$totalWidthNeeded, cardCount=$nonNullCardCount, '
                'newCardWidth=${cardDimensions.width}, newCardHeight=${cardDimensions.height}',
                isOn: LOGGING_SWITCH,
              );
            } else {
              // Use default unified dimensions
              cardDimensions = defaultDimensions;
            }
            
            final cardHeight = cardDimensions.height;
        final stackOffset = CardDimensions.getUnifiedStackOffset();
        
            // Build all card widgets with calculated dimensions
            List<Widget> cardWidgets = [];
            for (int index = 0; index < cards.length; index++) {
              final card = cards[index];
              
              // Handle null cards (blank slots from same-rank plays)
              if (card == null) {
                cardWidgets.add(
                  Padding(
                    padding: const EdgeInsets.only(right: cardPadding),
                  child: _buildBlankCardSlot(),
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
              final cardDataToUse = isDrawnCard && drawnCard != null 
                  ? drawnCard 
                  : (peekedCardData ?? collectionRankCardData ?? cardMap);
              
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
                        // Rebuild collection widgets with new dimensions
                        final collectionCardKey = GlobalKey(debugLabel: 'collection_card_$collectionCardId');
                        final collectionCardWidget = _buildCardWidget(
                          collectionCard, 
                          false, 
                          false, 
                          false, 
                          index, 
                          collectionCard, 
                          collectionCardKey,
                          cardDimensions,
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
                } else {
                  // Not the first collection card, skip rendering (already handled in stack)
                  // Don't add anything to cardWidgets
                }
              } else {
              // Normal card rendering (non-collection rank)
                final cardKey = GlobalKey(debugLabel: 'card_$cardId');
                final cardWidget = _buildCardWidget(
                  cardDataToUse, 
                  isSelected, 
                  isDrawnCard, 
                  false, 
                  index, 
                  cardMap, 
                  cardKey,
                  cardDimensions,
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
            
            return SizedBox(
              width: containerWidth,
              height: cardHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: cardWidgets,
          ),
            );
          },
        );
      },
    );
  }





  /// Get current user ID from login state
  String _getCurrentUserId() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    return loginState['userId']?.toString() ?? '';
  }

  /// Handle calling final round
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
      // Set local processing flag
      setState(() {
        _isProcessingAction = true;
      });
      _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true (call final round)', isOn: LOGGING_SWITCH);

      // Execute call final round action
      _logger.info('🎯 MyHandWidget - Creating PlayerAction.callFinalRound with gameId: $gameId', isOn: LOGGING_SWITCH);
      final callFinalRoundAction = PlayerAction.callFinalRound(gameId: gameId);
      _logger.info('🎯 MyHandWidget - Executing callFinalRoundAction...', isOn: LOGGING_SWITCH);
      await callFinalRoundAction.execute();
      _logger.info('✅ MyHandWidget - callFinalRoundAction.execute() completed', isOn: LOGGING_SWITCH);

      // Reset processing flag after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isProcessingAction = false;
          });
          _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (call final round)', isOn: LOGGING_SWITCH);
        }
      });

      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Final Round Called! All players will get one last turn.'),
          backgroundColor: AppColors.warningColor,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // Reset processing flag on error
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



  /// Handle card selection with status validation
  void _handleCardSelection(BuildContext context, int index, Map<String, dynamic> card) async {
    // Check local processing flag first (prevents rapid clicking without touching backend state)
    if (_isProcessingAction) {
      _logger.info('🚫 MyHandWidget - Action already in progress, ignoring card selection', isOn: LOGGING_SWITCH);
      return;
    }
    
    // Get current player status from state
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    final currentMyHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
    // Get playerStatus from myHand slice (computed from SSOT)
    final currentPlayerStatus = currentMyHand['playerStatus']?.toString() ?? 'unknown';
      
    // Check if current player can interact with hand cards (playing_card, jack_swap, queen_peek, same_rank_window, or initial_peek status)
    if (currentPlayerStatus == 'jack_swap') {
      _logger.info('🃏 MyHandWidget: Status is jack_swap - cards are interactive', isOn: LOGGING_SWITCH);
    }
    if (currentPlayerStatus == 'playing_card' || 
        currentPlayerStatus == 'jack_swap' || 
        currentPlayerStatus == 'queen_peek' ||
        currentPlayerStatus == 'same_rank_window' ||
        currentPlayerStatus == 'initial_peek') {
      
      // Update the selected card in the state

      final updatedMyHand = {
        ...currentMyHand,
        'selectedIndex': index,
        'selectedCard': card,
      };
      
      StateManager().updateModuleState('cleco_game', {
        ...currentState,
        'myHand': updatedMyHand,
      });
      
      // Get current game ID from state
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
      
      // Execute the appropriate action based on player status
      try {
        if (currentPlayerStatus == 'same_rank_window') {
          // Use same rank play action for same rank window
          final sameRankAction = PlayerAction.sameRankPlay(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
          await sameRankAction.execute();
          
          // Show success feedback for same rank play
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
          // Handle Jack swap card selection
          // Get current user ID (sessionId) - handles both practice and multiplayer modes
          final currentUserId = ClecoEventHandlerCallbacks.getCurrentUserId();
          
          _logger.info('🃏 MyHandWidget: Card tapped during jack_swap - Card: ${card['cardId']}, Player: $currentUserId, Game: $currentGameId', isOn: LOGGING_SWITCH);
          _logger.info('🃏 MyHandWidget: Current jack swap selection count: ${PlayerAction.getJackSwapSelectionCount()}', isOn: LOGGING_SWITCH);
          
          await PlayerAction.selectCardForJackSwap(
            cardId: card['cardId']?.toString() ?? '',
            playerId: currentUserId,
            gameId: currentGameId,
          );
          
          // Show feedback for Jack swap selection
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
          // Handle Queen peek card selection
          // Get current user ID (sessionId) - handles both practice and multiplayer modes
          final currentUserId = ClecoEventHandlerCallbacks.getCurrentUserId();
          
          final queenPeekAction = PlayerAction.queenPeek(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
            ownerId: currentUserId,
          );
          await queenPeekAction.execute();
          
          // Show feedback for Queen peek
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
          // Handle Initial peek card selection (limit to 2 cards)
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
          
          // Check if card already selected
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
            // Add card ID to selected list
            _initialPeekSelectedCardIds.add(cardId);
            _initialPeekSelectionCount++;
            
            // Show card selection feedback (without card details since we only have ID)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Card ${_initialPeekSelectionCount}/2 selected'
                ),
                backgroundColor: AppColors.infoColor,
                duration: Duration(seconds: 2),
              ),
            );
            
            // If this is the second card, trigger completed initial peek
            if (_initialPeekSelectionCount == 2) {
              // Small delay to show the second card snackbar
              await Future.delayed(Duration(milliseconds: 500));
              
              // Send completed_initial_peek with both card IDs
              final completedInitialPeekAction = PlayerAction.completedInitialPeek(
                gameId: currentGameId,
                cardIds: _initialPeekSelectedCardIds,
              );
              await completedInitialPeekAction.execute();
              
              // Show completion feedback
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Initial peek completed! You have looked at 2 cards.'
                  ),
                  backgroundColor: AppColors.successColor,
                  duration: Duration(seconds: 3),
                ),
              );
              
              // Reset state
              _initialPeekSelectionCount = 0;
              _initialPeekSelectedCardIds.clear();
            }
          } else {
            // Already selected 2 cards, show message
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
          // Set local processing flag (prevents rapid clicking, frontend-only)
          setState(() {
            _isProcessingAction = true;
          });
          _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true', isOn: LOGGING_SWITCH);
          
          // Use regular play card action for other states
          final playAction = PlayerAction.playerPlayCard(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
          await playAction.execute();
          
          // Reset processing flag after a short delay to allow backend response to arrive
          // Backend will set the correct status (waiting on success, playing_card on failure)
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isProcessingAction = false;
              });
              _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false', isOn: LOGGING_SWITCH);
            }
          });
          
          // Note: Success feedback removed to avoid showing success when action actually failed
          // Failed actions will show error messages via actionError state
          // Successful plays will be visible via game state updates (card moves to discard pile)
        }
      } catch (e) {
        // Reset processing flag on error
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
      // Show invalid action feedback
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

  /// Build a blank card slot for same-rank play empty spaces
  Widget _buildBlankCardSlot() {
    // Use unified card dimensions to match regular cards
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


  /// Build card widget with optional drawn card glow and collection rank border
  Widget _buildCardWidget(Map<String, dynamic> card, bool isSelected, bool isDrawnCard, bool isCollectionRankCard, int index, Map<String, dynamic> cardMap, GlobalKey cardKey, Size cardDimensions) {
    // Convert to CardModel
    final cardModel = CardModel.fromMap(card);
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    // Use provided cardDimensions (may be rescaled to fit container)
    Widget cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions, // Pass dimensions directly
      config: CardDisplayConfig.forMyHand(),
      isSelected: isSelected,
      onTap: () => _handleCardSelection(context, index, cardMap),
    );
    
    // Note: Collection rank cards no longer get a border - they're visually distinct through stacking + full data
    
    // Wrap with drawn card glow if needed - explicit size constraints to prevent size changes
    if (isDrawnCard) {
      cardWidget = SizedBox(
        width: cardDimensions.width,
        height: cardDimensions.height,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFBC02D).withOpacity(0.6), // Gold glow using theme color
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

}
