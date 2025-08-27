import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';

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
  static final Logger _log = Logger();
  
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
        final canPlayCard = recallGameState['canPlayCard'] ?? false;
        
        _log.info('🎮 MyHandWidget: cards=${cards.length}, selectedIndex=$selectedIndex, gamePhase=$gamePhase, isMyTurn=$isMyTurn, canPlayCard=$canPlayCard');
        
        return _buildMyHandCard(
          cards: cards,
          selectedIndex: selectedIndex,
          selectedCard: selectedCard,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
          canPlayCard: canPlayCard,
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
    required bool canPlayCard,
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
              _buildCardsGrid(cards, selectedIndex, canPlayCard),
            
            const SizedBox(height: 12),
            
            // Action buttons
            if (selectedIndex >= 0 && selectedIndex < cards.length)
              _buildActionButtons(selectedCard!, canPlayCard, isMyTurn, gamePhase),
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

  /// Build the cards grid
  Widget _buildCardsGrid(List<dynamic> cards, int selectedIndex, bool canPlayCard) {
    return Container(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        itemBuilder: (context, index) {
          final card = cards[index] as Map<String, dynamic>;
          final isSelected = index == selectedIndex;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _handleCardSelection(index, card),
              child: _buildCardWidget(card, isSelected, canPlayCard),
            ),
          );
        },
      ),
    );
  }

  /// Build individual card widget
  Widget _buildCardWidget(Map<String, dynamic> card, bool isSelected, bool canPlayCard) {
    final rank = card['rank']?.toString() ?? '?';
    final suit = card['suit']?.toString() ?? '?';
    final color = _getCardColor(suit);
    
    return Container(
      width: 70,
      height: 100,
      decoration: BoxDecoration(
        color: isSelected ? Colors.yellow.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? Colors.yellow.shade600 : Colors.grey.shade400,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            // Top-left rank and suit
            Align(
              alignment: Alignment.topLeft,
              child: Text(
                '$rank\n${_getSuitSymbol(suit)}',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            
            // Center suit symbol
            Expanded(
              child: Center(
                child: Text(
                  _getSuitSymbol(suit),
                  style: TextStyle(
                    fontSize: 20,
                    color: color,
                  ),
                ),
              ),
            ),
            
            // Bottom-right rank and suit (rotated)
            Align(
              alignment: Alignment.bottomRight,
              child: Transform.rotate(
                angle: 3.14159, // 180 degrees
                child: Text(
                  '$rank\n${_getSuitSymbol(suit)}',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build action buttons for selected card
  Widget _buildActionButtons(Map<String, dynamic> selectedCard, bool canPlayCard, bool isMyTurn, String gamePhase) {
    final bool canPlay = canPlayCard && isMyTurn && gamePhase == 'playing';
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Play Card button
        if (canPlay)
          ElevatedButton.icon(
            onPressed: () => _handlePlayCard(selectedCard),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Play Card'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              !isMyTurn ? 'Not your turn' : 'Cannot play',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        
        // Discard Card button (always available when card is selected)
        ElevatedButton.icon(
          onPressed: () => _handleDiscardCard(selectedCard),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Discard'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }

  /// Get the color for a card suit
  Color _getCardColor(String suit) {
    switch (suit.toLowerCase()) {
      case 'hearts':
      case 'diamonds':
        return Colors.red;
      case 'clubs':
      case 'spades':
        return Colors.black;
      default:
        return Colors.black;
    }
  }

  /// Get the Unicode symbol for a card suit
  String _getSuitSymbol(String suit) {
    switch (suit.toLowerCase()) {
      case 'hearts':
        return '♥';
      case 'diamonds':
        return '♦';
      case 'clubs':
        return '♣';
      case 'spades':
        return '♠';
      default:
        return '?';
    }
  }

  /// Handle card selection
  void _handleCardSelection(int index, Map<String, dynamic> card) {
    _log.info('🎮 MyHandWidget: Card selected at index $index: ${card['rank']} of ${card['suit']}');
    
    // Update the selected card in the state
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentMyHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
    
    final updatedMyHand = {
      ...currentMyHand,
      'selectedIndex': index,
      'selectedCard': card,
    };
    
    StateManager().updateModuleState('recall_game', {
      ...currentState,
      'myHand': updatedMyHand,
    });
  }

  /// Handle playing a card
  void _handlePlayCard(Map<String, dynamic> card) {
    _log.info('🎮 MyHandWidget: Play card action triggered: ${card['rank']} of ${card['suit']}');
    
    // TODO: Implement play card logic
    // This will be connected to the game action system
    // For now, just log the action
    
    // Example implementation:
    // GameActionManager().playCard(card);
  }

  /// Handle discarding a card
  void _handleDiscardCard(Map<String, dynamic> card) {
    _log.info('🎮 MyHandWidget: Discard card action triggered: ${card['rank']} of ${card['suit']}');
    
    // TODO: Implement discard card logic
    // This will be connected to the game action system
    // For now, just log the action
    
    // Example implementation:
    // GameActionManager().discardCard(card);
  }
}
