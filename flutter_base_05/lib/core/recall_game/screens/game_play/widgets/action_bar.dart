import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../managers/state_manager.dart';

class ActionBar extends StatefulWidget {
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
  State<ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<ActionBar> {
  final StateManager _stateManager = StateManager();

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
    // Read from widget-specific state slice for optimal performance
    final recall = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final actionBarState = recall['actionBar'] as Map<String, dynamic>? ?? {};
    
    // Use state slice data with fallbacks
    final hasSelection = recall['selectedCard'] != null;
    final showStartButton = actionBarState['showStartButton'] ?? false;
    final canPlayCard = actionBarState['canPlayCard'] ?? false;
    final canCallRecall = actionBarState['canCallRecall'] ?? false;
    final isGameStarted = actionBarState['isGameStarted'] ?? false;
    
    // Debug logging
    print('🎮 ActionBar Debug (using state slice):');
    print('  - hasStartMatchCallback: ${widget.onStartMatch != null}');
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
            if (widget.onStartMatch != null && showStartButton)
              Semantics(
                label: 'match_action_start',
                identifier: 'match_action_start',
                button: true,
                child: ElevatedButton(
                  onPressed: widget.onStartMatch,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  child: const Text('Start Match'),
                ),
              ),
            if (widget.onPlayOutOfTurn != null)
              Semantics(
                label: 'match_action_out_of_turn',
                identifier: 'match_action_out_of_turn',
                button: true,
                child: ElevatedButton(
                  onPressed: hasSelection ? widget.onPlayOutOfTurn : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                  child: const Text('Play Out-of-Turn'),
                ),
              ),
            
            Semantics(
              label: 'match_action_play',
              identifier: 'match_action_play',
              button: true,
              child: ElevatedButton(
                onPressed: canPlayCard && hasSelection ? widget.onPlay : null,
                child: const Text('Play'),
              ),
            ),
            Semantics(
              label: 'match_action_replace',
              identifier: 'match_action_replace',
              button: true,
              child: OutlinedButton(
                onPressed: canPlayCard && hasSelection ? widget.onReplaceWithDrawn : null,
                child: const Text('Replace with Drawn'),
              ),
            ),
            Semantics(
              label: 'match_action_place_drawn_play',
              identifier: 'match_action_place_drawn_play',
              button: true,
              child: OutlinedButton(
                onPressed: canPlayCard ? widget.onPlaceDrawnAndPlay : null,
                child: const Text('Play Drawn'),
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: 'match_action_call_recall',
              identifier: 'match_action_call_recall',
              button: true,
              child: ElevatedButton(
                onPressed: canCallRecall ? widget.onCallRecall : null,
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


