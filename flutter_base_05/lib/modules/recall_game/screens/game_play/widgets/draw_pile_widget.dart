import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../managers/player_action.dart';
import '../../../widgets/card_back_widget.dart';

/// Widget to display the draw pile information
/// 
/// This widget subscribes to the centerBoard state slice and displays:
/// - Number of cards remaining in draw pile
/// - Visual representation of the draw pile
/// - Interaction capabilities (draw card when it's player's turn)
/// - Clickable pile for special power interactions (drawing_card status only)
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class DrawPileWidget extends StatefulWidget {
  static final Logger _log = Logger();
  
  const DrawPileWidget({Key? key}) : super(key: key);

  @override
  State<DrawPileWidget> createState() => _DrawPileWidgetState();
}

class _DrawPileWidgetState extends State<DrawPileWidget> {
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
        final drawPileCount = centerBoard['drawPileCount'] ?? 0;
        final canDrawFromDeck = centerBoard['canDrawFromDeck'] ?? false;
        
        // Get additional game state for context
        final gamePhase = recallGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = recallGameState['isGameActive'] ?? false;
        final isMyTurn = recallGameState['isMyTurn'] ?? false;
        final playerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
        
        _log.info('🎮 DrawPileWidget: drawPileCount=$drawPileCount, canDrawFromDeck=$canDrawFromDeck, gamePhase=$gamePhase, isMyTurn=$isMyTurn, playerStatus=$playerStatus');
        
        return _buildDrawPileCard(
          drawPileCount: drawPileCount,
          canDrawFromDeck: canDrawFromDeck,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
          playerStatus: playerStatus,
        );
      },
    );
  }

  /// Build the draw pile card widget
  Widget _buildDrawPileCard({
    required int drawPileCount,
    required bool canDrawFromDeck,
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.style, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Draw Pile',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Draw pile visual representation (clickable)
            GestureDetector(
              onTap: _handlePileClick,
              child: drawPileCount > 0
                  ? CardBackWidget(
                      size: CardSize.medium,
                      customSymbol: '?',
                      backgroundColor: Colors.blue.shade100,
                      borderColor: Colors.blue.shade300,
                    )
                  : CardBackWidget(
                      size: CardSize.medium,
                      customSymbol: '?',
                      backgroundColor: Colors.grey.shade200,
                      borderColor: Colors.grey.shade400,
                    ),
            ),
            const SizedBox(height: 8),
            
            // Card count text
            Text(
              drawPileCount > 0 ? '$drawPileCount cards' : 'Empty',
              style: TextStyle(
                fontSize: 14,
                color: drawPileCount > 0 ? Colors.blue.shade700 : Colors.grey.shade600,
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
    
    _log.info('🎯 Draw pile clicked, current player status: $currentPlayerStatus');
    
    // Check if current player can interact with draw pile (drawing_card status only)
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
        
        // Get current user ID from login state (consistent with recall_event_manager pattern)
        final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
        final currentUserId = loginState['userId']?.toString() ?? '';
        if (currentUserId.isEmpty) {
          _log.error('❌ No current user ID found in login state');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: User not authenticated'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        
        // Create and execute the draw action
        final drawAction = PlayerAction.playerDraw(
          pileType: 'draw_pile',
          gameId: currentGameId,
          playerId: currentUserId,
        );
        await drawAction.execute();
        
        setState(() {
          _clickedPileType = 'draw_pile';
        });
        
        _log.info('✅ Draw action executed successfully (status: $currentPlayerStatus)');
        
        // Show success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card drawn from draw pile'),
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
      _log.info('❌ Invalid draw pile click action: status=$currentPlayerStatus');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with draw pile while status is "$currentPlayerStatus"'
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }


}
