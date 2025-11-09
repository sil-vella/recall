import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import 'player_status_chip_widget.dart';
import '../../../managers/player_action.dart';

/// Widget to display other players (opponents)
/// 
/// This widget subscribes to the opponentsPanel state slice and displays:
/// - List of all opponent players
/// - Small card-like elements showing number of cards in their hand
/// - Player names and status
/// - Clickable cards for special power interactions (queen_peek, jack_swap)
/// - No card details (handled by backend for security)
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class OpponentsPanelWidget extends StatefulWidget {
  const OpponentsPanelWidget({Key? key}) : super(key: key);

  @override
  State<OpponentsPanelWidget> createState() => _OpponentsPanelWidgetState();
}

class _OpponentsPanelWidgetState extends State<OpponentsPanelWidget> {
  // Internal state to store clicked card information
  String? _clickedCardId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get opponentsPanel state slice
        final opponentsPanel = recallGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
        final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
        final currentTurnIndex = opponentsPanel['currentTurnIndex'] ?? -1;
        
        // Get cardsToPeek state slice (current user's peeked cards, could be from opponents)
        final cardsToPeek = recallGameState['myCardsToPeek'] as List<dynamic>? ?? [];
        
        // Get current user ID to filter out self from opponents
        final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
        final currentUserId = loginState['userId']?.toString() ?? '';
        
        // Filter out current player from opponents list
        final otherPlayers = opponents.where((player) => 
          player['id']?.toString() != currentUserId
        ).toList();
        
        // Get additional game state for context
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = recallGameState['isGameActive'] ?? false;
        final isMyTurn = recallGameState['isMyTurn'] ?? false;
        final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
        
        
        return _buildOpponentsPanel(
          opponents: otherPlayers,
          cardsToPeek: cardsToPeek,
          currentTurnIndex: currentTurnIndex,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
          playerStatus: playerStatus,
        );
      },
    );
  }

  /// Build the opponents panel widget
  Widget _buildOpponentsPanel({
    required List<dynamic> opponents,
    required List<dynamic> cardsToPeek,
    required int currentTurnIndex,
    required String gamePhase,
    required bool isGameActive,
    required bool isMyTurn,
    required String playerStatus,
  }) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              Icon(Icons.people, color: Colors.purple),
              const SizedBox(width: 8),
              const Text(
                'Opponents',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Opponents display
          if (opponents.isEmpty)
            _buildEmptyOpponents()
          else
            _buildOpponentsGrid(opponents, cardsToPeek, currentTurnIndex, isGameActive, playerStatus),
        ],
      ),
    );
  }

  /// Build empty opponents state
  Widget _buildEmptyOpponents() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people,
              size: 24,
              color: Colors.grey,
            ),
            SizedBox(height: 4),
            Text(
              'No other players',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the opponents grid
  Widget _buildOpponentsGrid(List<dynamic> opponents, List<dynamic> cardsToPeek, int currentTurnIndex, bool isGameActive, String playerStatus) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get current player information from state (following standard pattern)
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final currentPlayerRaw = recallGameState['currentPlayer'];
        
        // Handle different types of currentPlayer data (null, string "null", or actual Map)
        Map<String, dynamic>? currentPlayerData;
        if (currentPlayerRaw == null || currentPlayerRaw == 'null' || currentPlayerRaw == '') {
          currentPlayerData = null;
        } else if (currentPlayerRaw is Map<String, dynamic>) {
          currentPlayerData = currentPlayerRaw;
        } else {
          currentPlayerData = null;
        }
        
        final currentPlayerId = currentPlayerData?['id']?.toString() ?? '';
        final currentPlayerStatus = recallGameState['currentPlayerStatus']?.toString() ?? 'unknown';
        
        // Determine if we're in initial peek phase - use gamePhase instead of playerStatus
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isInitialPeekPhase = gamePhase == 'initial_peek';
    
    return Column(
      children: opponents.asMap().entries.map((entry) {
        final index = entry.key;
        final player = entry.value as Map<String, dynamic>;
        final playerId = player['id']?.toString() ?? '';
        final isCurrentTurn = index == currentTurnIndex;
        final isCurrentPlayer = playerId == currentPlayerId;
        
        // Extract known_cards from player data
        final knownCards = player['known_cards'] as Map<String, dynamic>?;
        
        return SizedBox(
          width: double.infinity, // Take 100% of available width
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

  /// Build individual opponent card
  Widget _buildOpponentCard(Map<String, dynamic> player, List<dynamic> cardsToPeek, List<dynamic> playerCollectionRankCards, bool isCurrentTurn, bool isGameActive, bool isCurrentPlayer, String currentPlayerStatus, Map<String, dynamic>? knownCards, bool isInitialPeekPhase) {
    final playerName = player['name']?.toString() ?? 'Unknown Player';
    final hand = player['hand'] as List<dynamic>? ?? [];
    final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
    final hasCalledRecall = player['hasCalledRecall'] ?? false;
    final playerStatus = player['status']?.toString() ?? 'unknown';
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate 2% padding based on container width
        final containerPadding = constraints.maxWidth.isFinite 
            ? constraints.maxWidth * 0.02 
            : 16.0; // Fallback to fixed padding if width is unbounded
        
        return Container(
          padding: EdgeInsets.all(containerPadding),
          decoration: BoxDecoration(
            color: isCurrentPlayer ? Colors.blue.shade50 : (isCurrentTurn ? Colors.yellow.shade50 : Colors.white),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCurrentPlayer ? Colors.blue.shade400 : (isCurrentTurn ? Colors.yellow.shade400 : Colors.grey.shade300),
              width: (isCurrentPlayer || isCurrentTurn) ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isCurrentPlayer ? Colors.blue.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                blurRadius: isCurrentPlayer ? 4 : 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: Player name, turn indicator, status chip
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Player name, turn indicator, and recall flag
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            playerName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isCurrentPlayer ? Colors.blue.shade800 : Colors.black87,
                            ),
                          ),
                        ),
                        if (isCurrentTurn && !isCurrentPlayer) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.play_arrow,
                            size: 16,
                            color: Colors.yellow.shade700,
                          ),
                        ],
                        if (hasCalledRecall) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.flag,
                            size: 16,
                            color: Colors.red,
                          ),
                        ],
                      ],
                    ),
                    
                    // Player status indicator (show for all players)
                    if (playerStatus != 'unknown') ...[
                      const SizedBox(height: 4),
                      PlayerStatusChip(
                        playerId: player['id']?.toString() ?? '',
                        size: PlayerStatusChipSize.small,
                      ),
                    ],
                  ],
                ),
              ),
              
              // Right side: Cards display - horizontal layout, aligned to the right
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: hand.isNotEmpty
                      ? _buildCardsRow(hand, cardsToPeek, playerCollectionRankCards, drawnCard, player['id']?.toString() ?? '', knownCards, isInitialPeekPhase, player)
                      : _buildEmptyHand(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build cards row - horizontal layout with stacked collection rank cards
  Widget _buildCardsRow(List<dynamic> cards, List<dynamic> cardsToPeek, List<dynamic> playerCollectionRankCards, Map<String, dynamic>? drawnCard, String playerId, Map<String, dynamic>? knownCards, bool isInitialPeekPhase, Map<String, dynamic> player) {
    // Use LayoutBuilder to get available width for responsive card sizing
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate card dimensions: 15% of container width, maintaining 5:7 aspect ratio
        // Handle unbounded constraints by using a fallback
        final containerWidth = constraints.maxWidth.isFinite 
            ? constraints.maxWidth 
            : MediaQuery.of(context).size.width * 0.5; // Fallback to 50% of screen width
        final cardWidth = containerWidth * 0.15; // 15% of container width
        final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO; // Maintain 5:7 ratio
        final cardDimensions = Size(cardWidth, cardHeight);
        final stackOffset = cardHeight * CardDimensions.STACK_OFFSET_PERCENTAGE;
        final cardPadding = containerWidth * 0.02; // 2% of container width for spacing between cards
        
        // Build list of card IDs that are collection rank cards
        final collectionRankCardIds = playerCollectionRankCards
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
          final drawnCardId = drawnCard?['cardId']?.toString();
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
          if (playerCollectionRankCards.isNotEmpty) {
            for (var collectionCard in playerCollectionRankCards) {
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
            
            // Build the collection rank card widget with dynamic dimensions
            final cardWidget = _buildCardWidget(cardDataToUse, isDrawnCard, playerId, false, cardDimensions);
            collectionRankWidgets[cardId] = cardWidget;
          }
        }
        
        return SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            reverse: true, // Start from right
            itemCount: cards.length,
            itemBuilder: (context, index) {
          // Reverse the index to maintain correct card order
          final reversedIndex = cards.length - 1 - index;
          final card = cards[reversedIndex];
          
          // Handle null cards (blank slots from same-rank plays)
          if (card == null) {
            return Padding(
              padding: EdgeInsets.only(left: cardPadding), // 5% of container width
              child: _buildBlankCardSlot(cardDimensions),
            );
          }
          
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          final drawnCardId = drawnCard?['cardId']?.toString();
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          
          // Check if this card is in cardsToPeek (peeked cards have full data)
          // This is for when the current user is peeking at opponent cards (e.g., Queen peek)
          Map<String, dynamic>? peekedCardData;
          if (cardId != null && cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          
          // Check if this card is in player's collection_rank_cards (AI decision cards have full data)
          // This is for when players have selected cards as collection rank during initial peek
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
          
          // Determine which data to use (priority: drawn card > peeked card > collection rank card > ID-only hand card)
          final cardDataToUse = isDrawnCard && drawnCard != null 
              ? drawnCard 
              : (peekedCardData ?? collectionRankCardData ?? cardMap);
          
          // If this is a collection rank card, render the stack (only once, at the first collection card)
          if (isCollectionRankCard && collectionRankWidgets.containsKey(cardId)) {
            // Check if this is the first collection card in the hand (using original index order)
            bool isFirstCollectionCard = true;
            for (int i = 0; i < reversedIndex; i++) {
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
              for (var collectionCard in playerCollectionRankCards) {
                if (collectionCard is Map<String, dynamic>) {
                  final collectionCardId = collectionCard['cardId']?.toString();
                  if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                    orderedCollectionWidgets.add(collectionRankWidgets[collectionCardId]!);
                  }
                }
              }
              
              // Stack needs size constraint to render - constrain container, NOT individual cards
              final cardWidth = cardDimensions.width;
              final cardHeight = cardDimensions.height;
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
                      top: entry.key * stackOffset, // First card at top (0), subsequent cards offset downward
                      child: entry.value, // CardWidget already has exact dimensions
                    );
                  }).toList(),
                ),
              );
              
              return Padding(
                padding: EdgeInsets.only(left: cardPadding), // 5% of container width
                child: stackWidget,
              );
            } else {
              // Not the first collection card, skip rendering (already handled in stack)
              return const SizedBox.shrink();
            }
          }
          
          // Normal card rendering (non-collection rank)
          // CardWidget uses dynamic dimensions based on container width
          final cardWidget = _buildCardWidget(cardDataToUse, isDrawnCard, playerId, false, cardDimensions);
          
          return Padding(
            padding: EdgeInsets.only(
              left: cardPadding, // 5% of container width
              right: isDrawnCard ? cardPadding * 2 : 0, // Double padding for drawn card
            ),
            child: cardWidget,
          );
            },
          ),
        );
      },
    );
  }

  /// Build individual card widget for opponents using the new CardWidget system
  Widget _buildCardWidget(Map<String, dynamic> card, bool isDrawnCard, String playerId, bool isCollectionRankCard, Size cardDimensions) {
    // Convert to CardModel
    final cardModel = CardModel.fromMap(card);
    
    // Check if this card is currently selected
    final cardId = card['cardId']?.toString();
    final isSelected = cardId != null && _clickedCardId == cardId;
    
    // Update the card model with selection state
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    // Build card widget with dynamic dimensions (10% of container width)
    Widget cardWidget = CardWidget(
      card: updatedCardModel,
      dimensions: cardDimensions, // Pass dynamic dimensions
      config: CardDisplayConfig.forOpponent(),
      isSelected: isSelected,
      onTap: () => _handleCardClick(card, playerId),
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

  /// Build empty hand state
  Widget _buildEmptyHand() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 20,
              color: Colors.grey,
            ),
            SizedBox(height: 4),
            Text(
              'No cards',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }



  /// Get the currently clicked card ID (for external access)
  String? getClickedCardId() {
    return _clickedCardId;
  }

  /// Clear the clicked card ID (for resetting state)
  void clearClickedCardId() {
    setState(() {
      _clickedCardId = null;
    });
  }

  /// Handle card click for special power interactions
  void _handleCardClick(Map<String, dynamic> card, String cardOwnerId) async {
    // Get current player status from state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentPlayerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    
    // Check if current player can interact with cards (queen_peek or jack_swap status)
    if (currentPlayerStatus == 'queen_peek' || currentPlayerStatus == 'jack_swap') {
      final cardId = card['cardId']?.toString();
      if (cardId != null) {
        setState(() {
          _clickedCardId = cardId;
        });
        
        if (currentPlayerStatus == 'queen_peek') {
          // Handle Queen peek card selection
          try {
            final queenPeekAction = PlayerAction.queenPeek(
              gameId: currentGameId,
              cardId: cardId,
              ownerId: cardOwnerId,
            );
            await queenPeekAction.execute();
            
            // Show feedback for Queen peek
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Peeking at: ${card['rank']} of ${card['suit']}'
                ),
                backgroundColor: Colors.pink,
                duration: Duration(seconds: 2),
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to peek at card: $e'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (currentPlayerStatus == 'jack_swap') {
          // Handle Jack swap card selection
          try {
            await PlayerAction.selectCardForJackSwap(
              cardId: cardId,
              playerId: cardOwnerId,
              gameId: currentGameId,
            );
            
            // Show feedback for Jack swap selection
            final selectionCount = PlayerAction.getJackSwapSelectionCount();
            if (selectionCount == 1) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'First card selected: ${card['rank']} of ${card['suit']}. Select another card to swap.'
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
            } else if (selectionCount == 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Second card selected: ${card['rank']} of ${card['suit']}. Swapping cards...'
                  ),
                  backgroundColor: Colors.purple,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to select card for Jack swap: $e'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Card information incomplete'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Show invalid action feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with cards while status is "$currentPlayerStatus"'
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }


  /// Build a blank card slot for same-rank play empty spaces
  /// Note: This method is called from within LayoutBuilder context, so dimensions should be passed
  /// For now, we'll use a placeholder that will be replaced with dynamic dimensions
  Widget _buildBlankCardSlot([Size? cardDimensions]) {
    // Use provided dimensions or fallback to unified dimensions
    final dimensions = cardDimensions ?? CardDimensions.getUnifiedDimensions();
    
    return SizedBox(
      width: dimensions.width,
      height: dimensions.height,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.space_bar,
              size: 16,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 2),
            Text(
              'Empty',
              style: TextStyle(
                fontSize: 8,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

}
