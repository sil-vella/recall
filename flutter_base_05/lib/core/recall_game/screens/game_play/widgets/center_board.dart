import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import '../../../models/game_state.dart' as gm;
import '../../../../../../utils/consts/theme_consts.dart';

class CenterBoard extends StatelessWidget {
  final StateManager stateManager;
  final gm.GameState? gameState;
  final VoidCallback onDrawFromDeck;
  final VoidCallback onTakeFromDiscard;

  const CenterBoard({
    Key? key,
    required this.stateManager,
    required this.gameState,
    required this.onDrawFromDeck,
    required this.onTakeFromDiscard,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final drawCount = gameState?.drawPile.length ?? 0;
    final topDiscard = (gameState?.discardPile.isNotEmpty ?? false)
        ? gameState!.discardPile.last.displayName
        : '—';

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
            const SizedBox(height: 12),
            Semantics(
              label: semanticsId,
              identifier: semanticsId,
              button: true,
              child: ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            )
          ],
        ),
      ),
    );
  }
}


