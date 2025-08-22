import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../models/turn_phase.dart';

class ActionBar extends StatelessWidget {
  static final Logger _log = Logger();
  final PlayerTurnPhase currentTurnPhase;
  final Map<String, dynamic>? pendingDrawnCard;
  final VoidCallback onPlay;
  final VoidCallback onReplaceWithDrawn;
  final VoidCallback onPlaceDrawnAndPlay;
  final VoidCallback onCallRecall;
  final VoidCallback? onPlayOutOfTurn;
  final VoidCallback? onStartMatch;

  const ActionBar({
    Key? key,
    required this.currentTurnPhase,
    this.pendingDrawnCard,
    required this.onPlay,
    required this.onReplaceWithDrawn,
    required this.onPlaceDrawnAndPlay,
    required this.onCallRecall,
    this.onPlayOutOfTurn,
    this.onStartMatch,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recall = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final actionState = recall['actionBar'] as Map<String, dynamic>? ?? {};
        
        // Use state slice data with fallbacks
        final showStartButton = actionState['showStartButton'] ?? false;
        final canPlayCard = actionState['canPlayCard'] ?? false;
        final canCallRecall = actionState['canCallRecall'] ?? false;
        final isGameStarted = actionState['isGameStarted'] ?? false;
        
        // Get additional state for button logic
        final hasSelection = recall['selectedCard'] != null;
        
        // Determine button availability based on turn phase
        final canPlay = currentTurnPhase == PlayerTurnPhase.canPlay && hasSelection && canPlayCard;
        final canReplaceWithDrawn = currentTurnPhase == PlayerTurnPhase.hasDrawnCard && hasSelection && pendingDrawnCard != null;
        final canPlaceDrawnAndPlay = currentTurnPhase == PlayerTurnPhase.hasDrawnCard && pendingDrawnCard != null;
        final canCallRecallButton = (currentTurnPhase == PlayerTurnPhase.recallOpportunity || currentTurnPhase == PlayerTurnPhase.canPlay) && canCallRecall;
        final canPlayOutOfTurn = currentTurnPhase == PlayerTurnPhase.outOfTurn && hasSelection && onPlayOutOfTurn != null;
        
        // Debug logging
        _log.info('🎮 ActionBar Debug (using ListenableBuilder):');
        _log.info('  - currentTurnPhase: ${currentTurnPhase.name}');
        _log.info('  - hasSelection: $hasSelection');
        _log.info('  - pendingDrawnCard: ${pendingDrawnCard != null}');
        _log.info('  - canPlay: $canPlay');
        _log.info('  - canReplaceWithDrawn: $canReplaceWithDrawn');
        _log.info('  - canPlaceDrawnAndPlay: $canPlaceDrawnAndPlay');
        _log.info('  - canCallRecallButton: $canCallRecallButton');
        _log.info('  - canPlayOutOfTurn: $canPlayOutOfTurn');
        
        return Card(
          child: Padding(
            padding: AppPadding.cardPadding,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onStartMatch != null && showStartButton)
                  Semantics(
                    label: 'match_action_start',
                    identifier: 'match_action_start',
                    button: true,
                    child: ElevatedButton(
                      onPressed: onStartMatch,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      child: const Text('Start Match'),
                    ),
                  ),
                if (onPlayOutOfTurn != null)
                  Semantics(
                    label: 'match_action_out_of_turn',
                    identifier: 'match_action_out_of_turn',
                    button: true,
                    child: ElevatedButton(
                      onPressed: canPlayOutOfTurn ? onPlayOutOfTurn : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canPlayOutOfTurn ? Colors.purple : AppColors.lightGray,
                        foregroundColor: canPlayOutOfTurn ? Colors.white : AppColors.darkGray,
                      ),
                      child: const Text('Play Out-of-Turn'),
                    ),
                  ),
                
                Semantics(
                  label: 'match_action_play',
                  identifier: 'match_action_play',
                  button: true,
                  child: ElevatedButton(
                    onPressed: canPlay ? onPlay : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canPlay ? AppColors.primaryColor : AppColors.lightGray,
                      foregroundColor: canPlay ? Colors.white : AppColors.darkGray,
                    ),
                    child: const Text('Play Card'),
                  ),
                ),
                
                Semantics(
                  label: 'match_action_replace',
                  identifier: 'match_action_replace',
                  button: true,
                  child: ElevatedButton(
                    onPressed: canReplaceWithDrawn ? onReplaceWithDrawn : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canReplaceWithDrawn ? AppColors.accentColor : AppColors.lightGray,
                      foregroundColor: canReplaceWithDrawn ? Colors.white : AppColors.darkGray,
                    ),
                    child: const Text('Replace with Drawn'),
                  ),
                ),
                
                Semantics(
                  label: 'match_action_place_and_play',
                  identifier: 'match_action_place_and_play',
                  button: true,
                  child: ElevatedButton(
                    onPressed: canPlaceDrawnAndPlay ? onPlaceDrawnAndPlay : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canPlaceDrawnAndPlay ? AppColors.accentColor2 : AppColors.lightGray,
                      foregroundColor: canPlaceDrawnAndPlay ? Colors.white : AppColors.darkGray,
                    ),
                    child: const Text('Place Drawn & Play'),
                  ),
                ),
                
                Semantics(
                  label: 'match_action_recall',
                  identifier: 'match_action_recall',
                  button: true,
                  child: ElevatedButton(
                    onPressed: canCallRecallButton ? onCallRecall : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canCallRecallButton ? AppColors.redAccent : AppColors.lightGray,
                      foregroundColor: canCallRecallButton ? Colors.white : AppColors.darkGray,
                    ),
                    child: const Text('Call Recall!'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


