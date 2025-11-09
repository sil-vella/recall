import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../managers/player_action.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import '../../../managers/card_animation_manager.dart';
import '../../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = true;

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
  const DrawPileWidget({Key? key}) : super(key: key);

  @override
  State<DrawPileWidget> createState() => _DrawPileWidgetState();
}

class _DrawPileWidgetState extends State<DrawPileWidget> {
  final Logger _logger = Logger();
  
  // Internal state to store clicked pile type
  String? _clickedPileType;
  
  // GlobalKey for draw pile card position tracking
  final GlobalKey _drawCardKey = GlobalKey(debugLabel: 'draw_pile_card');
  final CardAnimationManager _animationManager = CardAnimationManager();

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
                Icon(Icons.style, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Draw',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Draw pile visual representation (clickable) - CardWidget handles its own sizing
            Builder(
              builder: (context) {
                final cardDimensions = CardDimensions.getUnifiedDimensions();
                final cardWidget = CardWidget(
                  card: CardModel(
                    cardId: 'draw_pile_${drawPileCount > 0 ? 'full' : 'empty'}',
                    rank: '?',
                    suit: '?',
                    points: 0,
                  ),
                  dimensions: cardDimensions, // Pass dimensions directly
                  config: CardDisplayConfig.forDrawPile(),
                  cardKey: _drawCardKey, // Pass GlobalKey for position tracking
                  showBack: true, // Always show back for draw pile
                  onTap: _handlePileClick, // Use CardWidget's internal GestureDetector
                );
                
                // Register draw pile position after build (for cards being drawn)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _registerDrawPilePosition();
                });
                
                return cardWidget;
              },
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

  /// Handle pile click for card drawing
  void _handlePileClick() async {
    // Get current player status from state
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final currentPlayerStatus = recallGameState['playerStatus']?.toString() ?? 'unknown';
    
    // Check if current player can interact with draw pile (drawing_card status only)
    if (currentPlayerStatus == 'drawing_card') {
      try {
        // Get current game ID from state
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
        
        // Create and execute the draw action (playerId is auto-added by event emitter)
        final drawAction = PlayerAction.playerDraw(
          pileType: 'draw_pile',
          gameId: currentGameId,
        );
        await drawAction.execute();
        
        setState(() {
          _clickedPileType = 'draw_pile';
        });
        
        // Show success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card drawn from draw pile'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
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

  /// Register draw pile position with animation manager
  void _registerDrawPilePosition() {
    // Draw pile position is used as source for cards being drawn
    // We register it with a special cardId to track the draw pile location
    final position = _animationManager.positionTracker.calculatePositionFromKey(
      _drawCardKey,
      'draw_pile_location',
      'draw_pile',
    );

    if (position != null) {
      _logger.info('🎬 DrawPileWidget: Registered draw pile position', isOn: LOGGING_SWITCH);
      _animationManager.registerCardPosition(position);
    } else {
      _logger.info('🎬 DrawPileWidget: Failed to calculate draw pile position', isOn: LOGGING_SWITCH);
    }
  }
}
