import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';

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
    return Card(
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onStartMatch != null)
              Semantics(
                label: 'match_action_start',
                identifier: 'match_action_start',
                button: true,
                child: ElevatedButton(
                  onPressed: onStartMatch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue, 
                    foregroundColor: Colors.white
                  ),
                  child: const Text('Start Match'),
                ),
              ),
            
            if (onPlayOutOfTurn != null)
              Semantics(
                label: 'match_action_out_of_turn',
                identifier: 'match_action_out_of_turn',
                button: true,
                child: ElevatedButton(
                  onPressed: onPlayOutOfTurn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Play Out-of-Turn'),
                ),
              ),
            
            Semantics(
              label: 'match_action_play',
              identifier: 'match_action_play',
              button: true,
              child: ElevatedButton(
                onPressed: onPlay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Play Card'),
              ),
            ),
            
            Semantics(
              label: 'match_action_replace',
              identifier: 'match_action_replace',
              button: true,
              child: ElevatedButton(
                onPressed: onReplaceWithDrawn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Replace with Drawn'),
              ),
            ),
            
            Semantics(
              label: 'match_action_place_and_play',
              identifier: 'match_action_place_and_play',
              button: true,
              child: ElevatedButton(
                onPressed: onPlaceDrawnAndPlay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentColor2,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Place Drawn & Play'),
              ),
            ),
            
            Semantics(
              label: 'match_action_recall',
              identifier: 'match_action_recall',
              button: true,
              child: ElevatedButton(
                onPressed: onCallRecall,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.redAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Call Recall!'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


