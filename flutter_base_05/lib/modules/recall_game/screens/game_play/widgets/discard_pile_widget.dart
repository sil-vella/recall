import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../managers/player_action.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import '../../../../../tools/logging/logger.dart';
import '../card_position_tracker.dart';

const bool LOGGING_SWITCH = true;

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
                const Text(
                  'Last Played',
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
            
            // Update position on rebuild (after card is rendered)
            Builder(
              builder: (context) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _updateDiscardPilePosition(topDiscard);
                });
                return const SizedBox.shrink();
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

  /// Update discard pile position in animation manager
  void _updateDiscardPilePosition(Map<String, dynamic>? topDiscard) {
    _logger.info(
      'DiscardPileWidget._updateDiscardPilePosition() called - topDiscard: ${topDiscard != null ? topDiscard['cardId']?.toString() ?? 'null' : 'null'}',
      isOn: LOGGING_SWITCH,
    );
    
    // Check if key is attached
    final renderObject = _discardCardKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      _logger.info(
        'DiscardPileWidget._updateDiscardPilePosition() - renderObject is null (widget not yet rendered)',
        isOn: LOGGING_SWITCH,
      );
      return;
    }
    
    // Get position and size
    final RenderBox? renderBox = renderObject as RenderBox?;
    if (renderBox == null) {
      _logger.info(
        'DiscardPileWidget._updateDiscardPilePosition() - renderBox is null',
        isOn: LOGGING_SWITCH,
      );
      return;
    }
    
    // Get screen position and size
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    // Determine cardId for the discard pile
    final cardId = topDiscard?['cardId']?.toString() ?? 'discard_pile_empty';
    
    _logger.info(
      'DiscardPileWidget._updateDiscardPilePosition() - Updating position: cardId=$cardId, position=(${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)}), size=(${size.width.toStringAsFixed(1)}, ${size.height.toStringAsFixed(1)})',
      isOn: LOGGING_SWITCH,
    );
    
    // Update position in tracker
    final tracker = CardPositionTracker.instance();
    tracker.updateCardPosition(
      cardId,
      position,
      size,
      'discard_pile',
    );
    
    _logger.info(
      'DiscardPileWidget._updateDiscardPilePosition() - Position updated successfully',
      isOn: LOGGING_SWITCH,
    );
    
    // Log all positions
    tracker.logAllPositions();
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
