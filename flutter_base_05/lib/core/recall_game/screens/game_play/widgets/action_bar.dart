import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';

class ActionBar extends StatelessWidget {
  final bool isMyTurn;
  final bool hasSelection;
  final VoidCallback onPlay;
  final VoidCallback onReplaceWithDrawn;
  final VoidCallback onPlaceDrawnAndPlay;
  final VoidCallback onCallRecall;

  const ActionBar({
    Key? key,
    required this.isMyTurn,
    required this.hasSelection,
    required this.onPlay,
    required this.onReplaceWithDrawn,
    required this.onPlaceDrawnAndPlay,
    required this.onCallRecall,
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
            Semantics(
              label: 'match_action_play',
              identifier: 'match_action_play',
              button: true,
              child: ElevatedButton(
                onPressed: isMyTurn && hasSelection ? onPlay : null,
                child: const Text('Play'),
              ),
            ),
            Semantics(
              label: 'match_action_replace',
              identifier: 'match_action_replace',
              button: true,
              child: OutlinedButton(
                onPressed: isMyTurn && hasSelection ? onReplaceWithDrawn : null,
                child: const Text('Replace with Drawn'),
              ),
            ),
            Semantics(
              label: 'match_action_place_drawn_play',
              identifier: 'match_action_place_drawn_play',
              button: true,
              child: OutlinedButton(
                onPressed: isMyTurn ? onPlaceDrawnAndPlay : null,
                child: const Text('Play Drawn'),
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: 'match_action_call_recall',
              identifier: 'match_action_call_recall',
              button: true,
              child: ElevatedButton(
                onPressed: onCallRecall,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                child: const Text('Call Recall'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


