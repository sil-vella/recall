import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../managers/player_action.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';

const bool LOGGING_SWITCH = false; // Enabled for animation debugging - Animation ID system

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
  final Logger _logger = Logger();
  
  // Internal state to store clicked pile type
  String? _clickedPileType;
  
  // GlobalKey for discard pile card position tracking
  final GlobalKey _discardCardKey = GlobalKey(debugLabel: 'discard_pile_card');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        
        // Get centerBoard state slice
        final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
        
        final topDiscard = centerBoard['topDiscard'] as Map<String, dynamic>?;
        
        final canTakeFromDiscard = centerBoard['canTakeFromDiscard'] ?? false;
        
        // Get additional game state for context
        final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = dutchGameState['isGameActive'] ?? false;
        final isMyTurn = dutchGameState['isMyTurn'] ?? false;
        // Get playerStatus from centerBoard slice (computed from SSOT)
        final playerStatus = centerBoard['playerStatus']?.toString() ?? 'unknown';
        
        
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
    
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Text(
            'Last Played',
            style: AppTextStyles.headingSmall(),
          ),
          const SizedBox(height: 12),
          
          // Discard pile visual representation (clickable) - CardWidget handles its own sizing
          Builder(
            builder: (context) {
              final cardDimensions = CardDimensions.getUnifiedDimensions();
              return hasCards 
                  ? CardWidget(
                      key: _discardCardKey,
                      card: CardModel.fromMap(topDiscard),
                      dimensions: cardDimensions, // Pass dimensions directly
                      config: CardDisplayConfig.forDiscardPile(),
                      onTap: _handlePileClick, // Use CardWidget's internal GestureDetector
                    )
                  : CardWidget(
                      key: _discardCardKey,
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


  /// Handle pile click for collecting cards from discard pile
  void _handlePileClick() async {
    // Get current game phase and state
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'unknown';
    final gameState = dutchGameState['gameState'] as Map<String, dynamic>? ?? {};
    final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? true; // Default to true for backward compatibility
    
    // Block during same_rank_window and initial_peek phases - but only if collection mode is enabled
    if ((gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') && isClearAndCollect) {
      String reason = gamePhase == 'same_rank_window' 
        ? 'Cannot collect cards during same rank window'
        : 'Cannot collect cards during initial peek phase';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: AppColors.warningColor,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // If collection is disabled (isClearAndCollect: false), silently ignore clicks during same_rank_window
    if ((gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') && !isClearAndCollect) {
      return; // Silently ignore - collection is disabled in this game mode
    }
    
    // Otherwise allow collection attempt at any time
    try {
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
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
      
      // Use collectFromDiscard action to collect card matching collection rank
      final collectAction = PlayerAction.collectFromDiscard(gameId: currentGameId);
      await collectAction.execute();
      
      setState(() {
        _clickedPileType = 'discard_pile';
      });
      
      // Note: Success/error feedback will come from backend via dutch_error event
      // or successful state update showing card in collection_rank_cards
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to collect card: $e'),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
