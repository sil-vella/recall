import 'package:flutter/material.dart';
import '../../managers/state_manager.dart';
import '../../../modules/recall_game/screens/game_play/widgets/game_phase_chip_widget.dart';

/// State-aware game phase chip feature widget
/// 
/// This widget subscribes to the recall_game state slice and displays
/// the current game phase chip in the app bar. It automatically updates
/// when the game phase changes.
class StateAwareGamePhaseChipFeature extends StatelessWidget {
  const StateAwareGamePhaseChipFeature({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get recall game state from StateManager
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final gameInfo = recallGameState['gameInfo'] as Map<String, dynamic>? ?? {};
        final currentGameId = gameInfo['currentGameId']?.toString() ?? '';
        
        // Return empty widget if no game is active
        if (currentGameId.isEmpty) {
          return const SizedBox.shrink();
        }
        
        // Return the game phase chip with appropriate padding for app bar
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GamePhaseChip(
            gameId: currentGameId,
            size: GamePhaseChipSize.small, // Compact size for app bar
          ),
        );
      },
    );
  }
}

