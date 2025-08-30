import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../managers/game_coordinator.dart';

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
    // Determine if player can draw based on status and game state
    final bool canDraw = canDrawFromDeck && isGameActive && isMyTurn && 
        (playerStatus == 'drawing_card' || gamePhase == 'playing' || gamePhase == 'out_of_turn');
    
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
              child: Container(
                width: 80,
                height: 120,
                decoration: BoxDecoration(
                  color: drawPileCount > 0 ? Colors.blue.shade100 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: drawPileCount > 0 ? Colors.blue.shade300 : Colors.grey.shade400,
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
                child: Stack(
                  children: [
                    // Card back pattern
                    if (drawPileCount > 0) ...[
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                    
                    // Card count
                    Center(
                      child: Text(
                        drawPileCount.toString(),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: drawPileCount > 0 ? Colors.blue.shade800 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            // Card count text
            Text(
              '$drawPileCount cards',
              style: TextStyle(
                fontSize: 14,
                color: drawPileCount > 0 ? Colors.blue.shade700 : Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            
            // Draw button (only show when it's the player's turn and they can draw)
            if (canDraw)
              ElevatedButton.icon(
                onPressed: _handleDrawCard,
                icon: const Icon(Icons.draw, size: 16),
                label: const Text('Draw Card'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              )
            else if (drawPileCount == 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Text(
                  'Empty',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
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
    
    _log.info('🎯 Draw pile clicked, current player status: $currentPlayerStatus');
    
    // Check if current player can interact with draw pile (drawing_card status only)
    if (currentPlayerStatus == 'drawing_card') {
      setState(() {
        _clickedPileType = 'draw_pile';
      });
      
      _log.info('✅ Draw pile selected (status: $currentPlayerStatus)');
      
      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draw pile selected for card drawing'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
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

  /// Handle drawing a card from the draw pile
  void _handleDrawCard() async {
    _log.info('🎮 DrawPileWidget: Draw card action triggered');
    
    try {
      // Import GameCoordinator
      final gameCoordinator = GameCoordinator();
      final success = await gameCoordinator.drawCard(source: 'deck');
      
      if (success) {
        _log.info('✅ DrawPileWidget: Draw card action sent successfully');
      } else {
        _log.error('❌ DrawPileWidget: Failed to send draw card action');
      }
    } catch (e) {
      _log.error('❌ DrawPileWidget: Error in draw card action: $e');
    }
  }
}
