import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../managers/player_action.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';

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
  const DiscardPileWidget({Key? key}) : super(key: key);

  @override
  State<DiscardPileWidget> createState() => _DiscardPileWidgetState();
}

class _DiscardPileWidgetState extends State<DiscardPileWidget> {
  // Internal state to store clicked pile type
  String? _clickedPileType;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        print('🔍 DEBUG: DiscardPileWidget build() called');
        print('🔍 DEBUG: DiscardPileWidget - recallGameState keys: ${recallGameState.keys.toList()}');
        
        // Get centerBoard state slice
        final centerBoard = recallGameState['centerBoard'] as Map<String, dynamic>? ?? {};
        print('🔍 DEBUG: DiscardPileWidget - centerBoard: $centerBoard');
        
        final topDiscard = centerBoard['topDiscard'] as Map<String, dynamic>?;
        print('🔍 DEBUG: DiscardPileWidget - topDiscard: $topDiscard');
        
        if (topDiscard != null) {
          print('🔍 DEBUG: DiscardPileWidget - topDiscard cardId: ${topDiscard['cardId']}');
          print('🔍 DEBUG: DiscardPileWidget - topDiscard rank: ${topDiscard['rank']}');
          print('🔍 DEBUG: DiscardPileWidget - topDiscard suit: ${topDiscard['suit']}');
          print('🔍 DEBUG: DiscardPileWidget - topDiscard has displayName: ${topDiscard.containsKey('displayName')}');
        } else {
          print('🔍 DEBUG: DiscardPileWidget - topDiscard is NULL');
        }
        
        final canTakeFromDiscard = centerBoard['canTakeFromDiscard'] ?? false;
        
        // Get additional game state for context
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = recallGameState['isGameActive'] ?? false;
        final isMyTurn = recallGameState['isMyTurn'] ?? false;
        final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
        
        
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
            
            // Discard pile visual representation (clickable) - CardWidget handles its own sizing
            Builder(
              builder: (context) {
                final cardDimensions = CardDimensions.getUnifiedDimensions();
                return hasCards 
                    ? CardWidget(
                        card: CardModel.fromMap(topDiscard),
                        dimensions: cardDimensions, // Pass dimensions directly
                        config: CardDisplayConfig.forDiscardPile(),
                        onTap: _handlePileClick, // Use CardWidget's internal GestureDetector
                      )
                    : CardWidget(
                        card: CardModel(
                          cardId: 'discard_pile_empty',
                          rank: '?',
                          suit: '?',
                          points: 0,
                        ),
                        dimensions: cardDimensions, // Pass dimensions directly
                        config: CardDisplayConfig.forDiscardPile(),
                        showBack: true, // Show back when empty
                        onTap: _handlePileClick, // Use CardWidget's internal GestureDetector
                      );
              },
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

  /// Handle pile click for collecting cards from discard pile
  void _handlePileClick() async {
    // Get current game phase and state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final gamePhase = recallGameState['gamePhase']?.toString() ?? 'unknown';
    
    // Block during same_rank_window and initial_peek phases
    if (gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') {
      String reason = gamePhase == 'same_rank_window' 
        ? 'Cannot collect cards during same rank window'
        : 'Cannot collect cards during initial peek phase';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Otherwise allow collection attempt at any time
    try {
      final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
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
      
      // Use existing playerDraw action with discard source
      final drawAction = PlayerAction.playerDraw(pileType: 'discard_pile', gameId: currentGameId);
      await drawAction.execute();
      
      setState(() {
        _clickedPileType = 'discard_pile';
      });
      
      // Note: Success/error feedback will come from backend via recall_error event
      // or successful state update showing card in collection_rank_cards
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to collect card: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
