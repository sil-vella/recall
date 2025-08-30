import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../managers/game_coordinator.dart';

/// Widget to display the discard pile information
/// 
/// This widget subscribes to the centerBoard state slice and displays:
/// - Top card of the discard pile
/// - Visual representation of the discard pile
/// - Interaction capabilities (take from discard when it's player's turn)
/// - Clickable pile for special power interactions (drawing_card status only)
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class DiscardPileWidget extends StatefulWidget {
  static final Logger _log = Logger();
  
  const DiscardPileWidget({Key? key}) : super(key: key);

  @override
  State<DiscardPileWidget> createState() => _DiscardPileWidgetState();
}

class _DiscardPileWidgetState extends State<DiscardPileWidget> {
  static final Logger _log = Logger();
  
  // Internal state to store clicked pile type
  String? _clickedPileType;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get centerBoard state slice
        final centerBoard = recallGameState['centerBoard'] as Map<String, dynamic>? ?? {};
        final topDiscard = centerBoard['topDiscard'] as Map<String, dynamic>?;
        final canTakeFromDiscard = centerBoard['canTakeFromDiscard'] ?? false;
        
        // Get additional game state for context
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = recallGameState['isGameActive'] ?? false;
        final isMyTurn = recallGameState['isMyTurn'] ?? false;
        final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
        
        _log.info('🎮 DiscardPileWidget: topDiscard=${topDiscard != null}, canTakeFromDiscard=$canTakeFromDiscard, gamePhase=$gamePhase, isMyTurn=$isMyTurn, playerStatus=$playerStatus');
        
        return _buildDiscardPileCard(
          topDiscard: topDiscard,
          canTakeFromDiscard: canTakeFromDiscard,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
          playerStatus: playerStatus,
        );
      },
    );
  }

  /// Build the discard pile card widget
  Widget _buildDiscardPileCard({
    required Map<String, dynamic>? topDiscard,
    required bool canTakeFromDiscard,
    required String gamePhase,
    required bool isGameActive,
    required bool isMyTurn,
    required String playerStatus,
  }) {
    // Determine if player can take from discard based on status and game state
    final bool canTake = canTakeFromDiscard && isGameActive && isMyTurn && 
        (playerStatus == 'drawing_card' || playerStatus == 'playing_card' || 
         gamePhase == 'playing' || gamePhase == 'out_of_turn');
    final bool hasCards = topDiscard != null;
    
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline, color: Colors.red),
                const SizedBox(width: 8),
                const Text(
                  'Discard Pile',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Discard pile visual representation (clickable)
            GestureDetector(
              onTap: _handlePileClick,
              child: Container(
                width: 80,
                height: 120,
                decoration: BoxDecoration(
                  color: hasCards ? Colors.red.shade100 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasCards ? Colors.red.shade300 : Colors.grey.shade400,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: hasCards ? _buildCardFace(topDiscard!) : _buildEmptyState(),
              ),
            ),
            const SizedBox(height: 8),
            
            // Card info text
            Text(
              hasCards ? 'Top card' : 'Empty',
              style: TextStyle(
                fontSize: 14,
                color: hasCards ? Colors.red.shade700 : Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            
            // Take button (only show when it's the player's turn and they can take)
            if (canTake)
              ElevatedButton.icon(
                onPressed: _handleTakeFromDiscard,
                icon: const Icon(Icons.handshake, size: 16),
                label: const Text('Take Card'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              )
            else if (!hasCards)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'Empty',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else if (!isGameActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'Game not active',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else if (!isMyTurn)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'Not your turn',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build the card face when there's a top card
  Widget _buildCardFace(Map<String, dynamic> card) {
    final rank = card['rank']?.toString() ?? '?';
    final suit = card['suit']?.toString() ?? '?';
    final color = _getCardColor(suit);
    
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          // Top-left rank and suit
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              '$rank\n${_getSuitSymbol(suit)}',
              style: TextStyle(
                fontSize: 10,
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
                  fontSize: 24,
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
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build empty state when no cards in discard pile
  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.delete_outline,
            size: 32,
            color: Colors.grey,
          ),
          SizedBox(height: 4),
          Text(
            'Empty',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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

  /// Get the currently clicked pile type (for external access)
  String? getClickedPileType() {
    return _clickedPileType;
  }

  /// Clear the clicked pile type (for resetting state)
  void clearClickedPileType() {
    setState(() {
      _clickedPileType = null;
    });
  }

  /// Handle pile click for special power interactions
  void _handlePileClick() {
    // Get current player status from state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentPlayerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
    
    _log.info('🎯 Discard pile clicked, current player status: $currentPlayerStatus');
    
    // Check if current player can interact with discard pile (drawing_card status only)
    if (currentPlayerStatus == 'drawing_card') {
      setState(() {
        _clickedPileType = 'discard_pile';
      });
      
      _log.info('✅ Discard pile selected (status: $currentPlayerStatus)');
      
      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Discard pile selected for card taking'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Show invalid action feedback
      _log.info('❌ Invalid discard pile click action: status=$currentPlayerStatus');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with discard pile while status is "$currentPlayerStatus"'
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Handle taking a card from the discard pile
  void _handleTakeFromDiscard() async {
    _log.info('🎮 DiscardPileWidget: Take from discard action triggered');
    
    try {
      // Import GameCoordinator
      final gameCoordinator = GameCoordinator();
      final success = await gameCoordinator.takeFromDiscard();
      
      if (success) {
        _log.info('✅ DiscardPileWidget: Take from discard action sent successfully');
      } else {
        _log.error('❌ DiscardPileWidget: Failed to send take from discard action');
      }
    } catch (e) {
      _log.error('❌ DiscardPileWidget: Error in take from discard action: $e');
    }
  }
}
