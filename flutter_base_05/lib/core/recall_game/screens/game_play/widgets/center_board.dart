import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';

import '../../../../../../utils/consts/theme_consts.dart';

class CenterBoard extends StatelessWidget {
  final VoidCallback onDrawFromDeck;
  final VoidCallback onTakeFromDiscard;

  const CenterBoard({
    Key? key,
    required this.onDrawFromDeck,
    required this.onTakeFromDiscard,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Read game state from StateManager
        // Read from widget-specific state slice for optimal performance
        final recall = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final centerBoardState = recall['centerBoard'] as Map<String, dynamic>? ?? {};
        
        final drawCount = centerBoardState['drawPileCount'] as int? ?? 0;
        final lastPlayedCard = centerBoardState['lastPlayedCard'] as Map<String, dynamic>?;
        final topDiscard = lastPlayedCard?['displayName'] as String? ?? '—';

        return Row(
          children: [
            Expanded(
              child: _PileCard(
                title: 'Draw Pile',
                subtitle: 'Cards: $drawCount',
                actionLabel: 'Draw',
                onAction: onDrawFromDeck,
                semanticsId: 'pile_draw',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _PileCard(
                title: 'Discard Pile',
                subtitle: 'Top: $topDiscard',
                actionLabel: 'Take Top',
                onAction: onTakeFromDiscard,
                semanticsId: 'pile_discard_top',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PileCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final String semanticsId;

  const _PileCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.semanticsId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.headingSmall()),
            const SizedBox(height: 8),
            Text(subtitle, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 16),
            Semantics(
              label: 'pile_action_$semanticsId',
              identifier: 'pile_action_$semanticsId',
              button: true,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(actionLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


