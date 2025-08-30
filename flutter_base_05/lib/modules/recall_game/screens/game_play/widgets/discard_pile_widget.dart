import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../managers/player_action.dart';
import '../../../models/card_model.dart';
import '../../../widgets/card_widget.dart';
import '../../../widgets/card_back_widget.dart';

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
              child: hasCards 
                  ? CardWidget(
                      card: CardModel.fromMap(topDiscard!),
                      size: CardSize.medium,
                      isSelectable: false,
                      showPoints: false,
                      showSpecialPower: false,
                    )
                  : CardBackWidget(
                      size: CardSize.medium,
                      customSymbol: '?',
                      backgroundColor: Colors.grey.shade200,
                      borderColor: Colors.grey.shade400,
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
          ],
        ),
      ),
    );
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

  /// Handle pile click for card drawing
  void _handlePileClick() async {
    // Get current player status from state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentPlayerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
    
    _log.info('🎯 Discard pile clicked, current player status: $currentPlayerStatus');
    
    // Check if current player can interact with discard pile (drawing_card status only)
    if (currentPlayerStatus == 'drawing_card') {
      try {
        // Get current game ID from state
        final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
        if (currentGameId.isEmpty) {
          _log.error('❌ No current game ID found');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No active game found'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        
        // Get current player ID from recall game state (consistent with other widgets)
        final currentPlayerId = recallGameState['currentPlayer']?.toString() ?? '';
        if (currentPlayerId.isEmpty) {
          _log.error('❌ No current player ID found in recall game state');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No active player found'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        
        // Create and execute the draw action
        final drawAction = PlayerAction.playerDraw(
          pileType: 'discard_pile',
          gameId: currentGameId,
          playerId: currentPlayerId,
        );
        await drawAction.execute();
        
        setState(() {
          _clickedPileType = 'discard_pile';
        });
        
        _log.info('✅ Draw action executed successfully (status: $currentPlayerStatus)');
        
        // Show success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card drawn from discard pile'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        _log.error('❌ Failed to execute draw action: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to draw card: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
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


}
