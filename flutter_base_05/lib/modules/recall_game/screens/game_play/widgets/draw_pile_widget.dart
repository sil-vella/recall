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
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class DrawPileWidget extends StatelessWidget {
  static final Logger _log = Logger();
  
  const DrawPileWidget({Key? key}) : super(key: key);

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
        
        _log.info('🎮 DrawPileWidget: drawPileCount=$drawPileCount, canDrawFromDeck=$canDrawFromDeck, gamePhase=$gamePhase, isMyTurn=$isMyTurn');
        
        return _buildDrawPileCard(
          drawPileCount: drawPileCount,
          canDrawFromDeck: canDrawFromDeck,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
          isMyTurn: isMyTurn,
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
  }) {
    final bool canDraw = canDrawFromDeck && isGameActive && isMyTurn && gamePhase == 'playing';
    
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
            
            // Draw pile visual representation
            Container(
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
