import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../widgets/card_widget.dart';
import '../../../widgets/card_back_widget.dart';
import '../../../managers/player_action.dart';

/// Widget to display the player's hand
/// 
/// This widget subscribes to the myHand state slice and displays:
/// - All cards in the player's hand
/// - Card selection functionality
/// - Visual representation of each card
/// - Dynamic add/remove cards based on state changes
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class MyHandWidget extends StatelessWidget {
  const MyHandWidget({Key? key}) : super(key: key);

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
        
        // Get additional game state for context
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = recallGameState['isGameActive'] ?? false;
        final isMyTurn = recallGameState['isMyTurn'] ?? false;
        final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
        
        
        return _buildMyHandCard(
          cards: cards,
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
            // Title
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
              _buildCardsGrid(cards, selectedIndex),
            

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
  Widget _buildCardsGrid(List<dynamic> cards, int selectedIndex) {
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
              final isSelected = index == selectedIndex;
              final isDrawnCard = drawnCardId != null && cardMap['cardId']?.toString() == drawnCardId;
              
              
              // Convert to CardModel
              final cardModel = CardModel.fromMap(cardMap);
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





  /// Handle card selection with status validation
  void _handleCardSelection(BuildContext context, int index, Map<String, dynamic> card) async {
    // Get current player status from state
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentPlayerStatus = currentState['playerStatus']?.toString() ?? 'unknown';
    final currentMyHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
      
    // Check if current player can interact with hand cards (playing_card, jack_swap, queen_peek, or same_rank_window status)
    if (currentPlayerStatus == 'playing_card' || 
        currentPlayerStatus == 'jack_swap' || 
        currentPlayerStatus == 'queen_peek' ||
        currentPlayerStatus == 'same_rank_window') {
      
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
          final currentPlayerId = currentState['currentPlayerId']?.toString() ?? '';
          await PlayerAction.selectCardForJackSwap(
            cardId: card['cardId']?.toString() ?? '',
            playerId: currentPlayerId,
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
