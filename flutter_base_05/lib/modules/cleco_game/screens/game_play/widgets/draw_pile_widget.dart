import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../managers/player_action.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import '../../../../../tools/logging/logger.dart';
import '../card_position_tracker.dart';
import '../../../../../utils/consts/theme_consts.dart';

const bool LOGGING_SWITCH = true; // Enabled for animation debugging

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        
        // Get centerBoard state slice
        final centerBoard = clecoGameState['centerBoard'] as Map<String, dynamic>? ?? {};
        final drawPileCount = centerBoard['drawPileCount'] ?? 0;
        final canDrawFromDeck = centerBoard['canDrawFromDeck'] ?? false;
        
        // Get additional game state for context
        final gamePhase = clecoGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = clecoGameState['isGameActive'] ?? false;
        final isMyTurn = clecoGameState['isMyTurn'] ?? false;
        // Get playerStatus from centerBoard slice (computed from SSOT)
        final playerStatus = centerBoard['playerStatus']?.toString() ?? 'unknown';
        
        
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
    
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Text(
            'Draw',
            style: AppTextStyles.headingSmall(),
          ),
          const SizedBox(height: 12),
          
          // Draw pile visual representation (clickable) - CardWidget handles its own sizing
          Builder(
            builder: (context) {
              final cardDimensions = CardDimensions.getUnifiedDimensions();
              return CardWidget(
                key: _drawCardKey,
                card: CardModel(
                  cardId: 'draw_pile_${drawPileCount > 0 ? 'full' : 'empty'}',
                  rank: '?',
                  suit: '?',
                  points: 0,
                ),
                dimensions: cardDimensions, // Pass dimensions directly
                config: CardDisplayConfig.forDrawPile(),
                showBack: true, // Always show back for draw pile
                onTap: _handlePileClick, // Use CardWidget's internal GestureDetector
              );
            },
          ),
          
          // Update position on rebuild (after card is rendered)
          Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _updateDrawPilePosition();
              });
              return const SizedBox.shrink();
            },
          ),
        ],
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

  /// Update draw pile position in animation manager
  void _updateDrawPilePosition() {
    _logger.info(
      'DrawPileWidget._updateDrawPilePosition() called',
      isOn: LOGGING_SWITCH,
    );
    
    // Check if key is attached
    final renderObject = _drawCardKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      _logger.info(
        'DrawPileWidget._updateDrawPilePosition() - renderObject is null (widget not yet rendered)',
        isOn: LOGGING_SWITCH,
      );
      return;
    }
    
    // Get position and size
    final RenderBox? renderBox = renderObject as RenderBox?;
    if (renderBox == null) {
      _logger.info(
        'DrawPileWidget._updateDrawPilePosition() - renderBox is null',
        isOn: LOGGING_SWITCH,
      );
      return;
    }

    // Get screen position and size
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    // Verbose logging disabled to reduce log noise
    
    // Update position in tracker
    final tracker = CardPositionTracker.instance();
    tracker.updateCardPosition(
      'draw_pile',
      position,
      size,
      'draw_pile',
    );
    
    // Verbose logging removed to reduce log noise
    // tracker.logAllPositions(); // Disabled - too verbose
  }

  /// Handle pile click for card drawing
  void _handlePileClick() async {
    // Get current player status from state
    final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
    // Get playerStatus from centerBoard slice (computed from SSOT)
    final centerBoard = clecoGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = centerBoard['playerStatus']?.toString() ?? 'unknown';
    
    // Check if current player can interact with draw pile (drawing_card status only)
    if (currentPlayerStatus == 'drawing_card') {
      try {
        // Get current game ID from state
        final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
        if (currentGameId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Error: No active game found'),
              backgroundColor: AppColors.errorColor,
              duration: const Duration(seconds: 3),
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
          SnackBar(
            content: const Text('Card drawn from draw pile'),
            backgroundColor: AppColors.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to draw card: $e'),
            backgroundColor: AppColors.errorColor,
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
          backgroundColor: AppColors.warningColor,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }


}
