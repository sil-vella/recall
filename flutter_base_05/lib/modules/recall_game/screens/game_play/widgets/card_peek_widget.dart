import 'package:flutter/material.dart';
import '../../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../widgets/card_widget.dart';
import '../../../widgets/card_back_widget.dart';

/// Widget to display cards that can be peeked at
/// 
/// This widget subscribes to the cards_to_peek state slice and displays:
/// - List of cards available for peeking
/// - Card details for each peekable card
/// - Visual representation of each card
/// - Owner information for each card
/// - Interaction capabilities for peek actions
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class CardPeekWidget extends StatelessWidget {
  const CardPeekWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get cards_to_peek state slice
        final cardsToPeek = recallGameState['cards_to_peek'] as List<dynamic>? ?? [];
        
        // Get additional game state for context
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = recallGameState['isGameActive'] ?? false;
        final isMyTurn = recallGameState['isMyTurn'] ?? false;
        final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
        
        return _buildCardPeekCard(
          cardsToPeek: cardsToPeek,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
          playerStatus: playerStatus,
        );
      },
    );
  }

  /// Build the card peek card widget
  Widget _buildCardPeekCard({
    required List<dynamic> cardsToPeek,
    required String gamePhase,
    required bool isGameActive,
    required bool isMyTurn,
    required String playerStatus,
  }) {
    // Check if player is in peeking status
    final isPeeking = playerStatus == 'peeking';
    
    // Only show modal when player is peeking and there are cards to peek
    if (!isPeeking || cardsToPeek.isEmpty) {
      return const SizedBox.shrink(); // Don't show anything
    }
    
    // Show as modal overlay
    return Container(
      color: Colors.black54, // Semi-transparent overlay
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Peek at Cards',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        // TODO: Handle close peek modal
                        // This could send a message to clear the peek state
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildPeekCardsGrid(cardsToPeek),
              ],
            ),
          ),
        ),
      ),
    );
  }


  /// Build the peek cards grid using the CardWidget system
  Widget _buildPeekCardsGrid(List<dynamic> cardsToPeek) {
    return Container(
      height: 180, // Increased height to accommodate owner info
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: cardsToPeek.length,
        itemBuilder: (context, index) {
          final cardData = cardsToPeek[index];
          
          // Handle null cards
          if (cardData == null) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildBlankCardSlot(),
            );
          }
          
          final cardMap = cardData as Map<String, dynamic>;
          final ownerPlayerId = cardMap['owner_player_id']?.toString() ?? 'unknown';
          
          // Convert to CardModel
          final cardModel = CardModel.fromMap(cardMap);
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              children: [
                // Card display
                CardWidget(
                  card: cardModel,
                  size: CardSize.medium,
                  isSelectable: false,
                  showPoints: true,
                  showSpecialPower: true,
                ),
                const SizedBox(height: 4),
                // Owner information
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Owner: ${ownerPlayerId.length > 8 ? '${ownerPlayerId.substring(0, 8)}...' : ownerPlayerId}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Build a blank card slot for empty spaces
  Widget _buildBlankCardSlot() {
    return Container(
      width: 80,
      height: 120,
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
