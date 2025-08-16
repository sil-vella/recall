import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import '../../../models/game_state.dart' as gm;
import '../../../../../../utils/consts/theme_consts.dart';

class CenterBoard extends StatefulWidget {
  final VoidCallback onDrawFromDeck;
  final VoidCallback onTakeFromDiscard;

  const CenterBoard({
    Key? key,
    required this.onDrawFromDeck,
    required this.onTakeFromDiscard,
  }) : super(key: key);

  @override
  State<CenterBoard> createState() => _CenterBoardState();
}

class _CenterBoardState extends State<CenterBoard> {
  final StateManager _stateManager = StateManager(); // ✅ Pattern 1: Widget creates its own instance

  @override
  void initState() {
    super.initState();
    _stateManager.addListener(_onChanged);
  }

  @override
  void dispose() {
    _stateManager.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Read game state from StateManager
    final recall = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final gameStateJson = recall['gameState'] as Map<String, dynamic>?;
    
    // Convert to GameState object if available
    dynamic gameState;
    if (gameStateJson != null) {
      try {
        gameState = gm.GameState.fromJson(gameStateJson);
      } catch (e) {
        // If conversion fails, use the JSON directly
        gameState = gameStateJson;
      }
    }
    
    final drawCount = gameState?.drawPile?.length ?? 0;
    final topDiscard = (gameState?.discardPile?.isNotEmpty ?? false)
        ? gameState!.discardPile.last.displayName
        : '—';

    return Row(
      children: [
        Expanded(
          child: _PileCard(
            title: 'Draw Pile',
            subtitle: 'Cards: $drawCount',
            actionLabel: 'Draw',
            onAction: widget.onDrawFromDeck,
            semanticsId: 'pile_draw',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _PileCard(
            title: 'Discard Pile',
            subtitle: 'Top: $topDiscard',
            actionLabel: 'Take Top',
            onAction: widget.onTakeFromDiscard,
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


