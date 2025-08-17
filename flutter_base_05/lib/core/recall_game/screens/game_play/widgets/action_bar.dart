import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../managers/state_manager.dart';

class ActionBar extends StatelessWidget {
  final VoidCallback onPlay;
  final VoidCallback onReplaceWithDrawn;
  final VoidCallback onPlaceDrawnAndPlay;
  final VoidCallback onCallRecall;
  final VoidCallback? onPlayOutOfTurn;
  final VoidCallback? onStartMatch;

  const ActionBar({
    Key? key,
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
        
        // Debug logging
        print('🎮 ActionBar Debug (using ListenableBuilder):');
        print('  - hasStartMatchCallback: ${onStartMatch != null}');
        print('  - showStartButton: $showStartButton');
        print('  - canPlayCard: $canPlayCard');
        print('  - canCallRecall: $canCallRecall');
        print('  - isGameStarted: $isGameStarted');
        
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
                      onPressed: hasSelection ? onPlayOutOfTurn : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                      child: const Text('Play Out-of-Turn'),
                    ),
                  ),
                
                Semantics(
                  label: 'match_action_play',
                  identifier: 'match_action_play',
                  button: true,
                  child: ElevatedButton(
                    onPressed: hasSelection && canPlayCard ? onPlay : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasSelection && canPlayCard ? AppColors.primaryColor : AppColors.lightGray,
                      foregroundColor: hasSelection && canPlayCard ? Colors.white : AppColors.darkGray,
                    ),
                    child: const Text('Play Card'),
                  ),
                ),
                
                Semantics(
                  label: 'match_action_replace',
                  identifier: 'match_action_replace',
                  button: true,
                  child: ElevatedButton(
                    onPressed: hasSelection ? onReplaceWithDrawn : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasSelection ? AppColors.accentColor : AppColors.lightGray,
                      foregroundColor: hasSelection ? Colors.white : AppColors.darkGray,
                    ),
                    child: const Text('Replace with Drawn'),
                  ),
                ),
                
                Semantics(
                  label: 'match_action_place_and_play',
                  identifier: 'match_action_place_and_play',
                  button: true,
                  child: ElevatedButton(
                    onPressed: hasSelection ? onPlaceDrawnAndPlay : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasSelection ? AppColors.accentColor2 : AppColors.lightGray,
                      foregroundColor: hasSelection ? Colors.white : AppColors.darkGray,
                    ),
                    child: const Text('Place Drawn & Play'),
                  ),
                ),
                
                Semantics(
                  label: 'match_action_recall',
                  identifier: 'match_action_recall',
                  button: true,
                  child: ElevatedButton(
                    onPressed: canCallRecall ? onCallRecall : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canCallRecall ? AppColors.redAccent : AppColors.lightGray,
                      foregroundColor: canCallRecall ? Colors.white : AppColors.darkGray,
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


