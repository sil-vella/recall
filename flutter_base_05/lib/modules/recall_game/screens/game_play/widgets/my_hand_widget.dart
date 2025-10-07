import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../widgets/card_widget.dart';
import 'player_status_chip_widget.dart';
import '../../../managers/player_action.dart';
import '../../../../../../utils/consts/theme_consts.dart';

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
  // Local state for initial peek card selections
  int _initialPeekSelectionCount = 0;
  List<String> _initialPeekSelectedCardIds = [];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get myHand state slice
        final myHand = recallGameState['myHand'] as Map<String, dynamic>? ?? {};
        final cards = myHand['cards'] as List<dynamic>? ?? [];
        final selectedIndex = myHand['selectedIndex'] ?? -1;
        final selectedCard = myHand['selectedCard'] as Map<String, dynamic>?;
        
        // Get cardsToPeek state slice
        final cardsToPeek = recallGameState['myCardsToPeek'] as List<dynamic>? ?? [];
        
        // Get additional game state for context
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = recallGameState['isGameActive'] ?? false;
        final isMyTurn = recallGameState['isMyTurn'] ?? false;
        final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
        
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
        );
      },
    );
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
  }) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and Status
            Row(
              children: [
                Icon(Icons.style, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'My Hand',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                // Player status indicator
                if (playerStatus != 'unknown') ...[
                  PlayerStatusChip(
                    playerId: _getCurrentUserId(),
                    size: PlayerStatusChipSize.small,
                  ),
                ],
                const Spacer(),
                Text(
                  '${cards.length} cards',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
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
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 32,
              color: Colors.grey,
            ),
            SizedBox(height: 8),
            Text(
              'No cards in hand',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
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
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final drawnCard = recallGameState['myDrawnCard'] as Map<String, dynamic>?;
        final drawnCardId = drawnCard?['cardId']?.toString();
        
        
        return Container(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              
              // Handle null cards (blank slots from same-rank plays)
              if (card == null) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildBlankCardSlot(),
                );
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
              
              // Determine which data to use (priority: drawn card > peeked card > ID-only hand card)
              final cardDataToUse = isDrawnCard && drawnCard != null 
                  ? drawnCard 
                  : (peekedCardData ?? cardMap);
              
              // Convert to CardModel
              final cardModel = CardModel.fromMap(cardDataToUse);
              final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
              
              return Padding(
                padding: EdgeInsets.only(
                  right: 8,
                  left: isDrawnCard ? 16 : 0, // Extra left margin for drawn card
                ),
                child: Container(
                  decoration: isDrawnCard ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFBC02D).withOpacity(0.6), // Gold glow using theme color
                        blurRadius: 12,
                        spreadRadius: 2,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ) : null,
                  child: CardWidget(
                    card: updatedCardModel,
                    size: CardSize.large,
                    isSelectable: true,
                    isSelected: isSelected,
                    onTap: () => _handleCardSelection(context, index, cardMap),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }





  /// Get current user ID from login state
  String _getCurrentUserId() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    return loginState['userId']?.toString() ?? '';
  }

  /// Handle card selection with status validation
  void _handleCardSelection(BuildContext context, int index, Map<String, dynamic> card) async {
    // Get current player status from state
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentPlayerStatus = currentState['playerStatus']?.toString() ?? 'unknown';
    final currentMyHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
      
    // Check if current player can interact with hand cards (playing_card, jack_swap, queen_peek, same_rank_window, or initial_peek status)
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
      
      StateManager().updateModuleState('recall_game', {
        ...currentState,
        'myHand': updatedMyHand,
      });
      
      // Get current game ID from state
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      if (currentGameId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: No active game found'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
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
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (currentPlayerStatus == 'jack_swap') {
          // Handle Jack swap card selection
          // Get current user ID from login state (card owner for my hand)
          final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
          final currentUserId = loginState['userId']?.toString() ?? '';
          
          await PlayerAction.selectCardForJackSwap(
            cardId: card['cardId']?.toString() ?? '',
            playerId: currentUserId,
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
        } else if (currentPlayerStatus == 'queen_peek') {
          // Handle Queen peek card selection
          // Get current user ID from login state (card owner for my hand)
          final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
          final currentUserId = loginState['userId']?.toString() ?? '';
          
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
              backgroundColor: Colors.pink,
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
                backgroundColor: Colors.red,
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
                backgroundColor: Colors.orange,
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
                backgroundColor: Colors.teal,
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
                  backgroundColor: Colors.green,
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
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          // Use regular play card action for other states
          final playAction = PlayerAction.playerPlayCard(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
          await playAction.execute();
          
          // Show success feedback for regular play
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Playing card: ${card['rank']} of ${card['suit']}'
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to execute action: $e'),
            backgroundColor: Colors.red,
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
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Build a blank card slot for same-rank play empty spaces
  Widget _buildBlankCardSlot() {
    return Container(
      width: 80, // Same width as regular cards
      height: 120, // Same height as regular cards
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade300,
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
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 4),
            Text(
              'Empty',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
