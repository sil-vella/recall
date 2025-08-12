import 'package:flutter/material.dart';
import '../../../../../managers/state_manager.dart';
import '../../../../models/game_state.dart' as gm;
import '../../../../../utils/consts/theme_consts.dart';

class StatusBar extends StatelessWidget {
  final StateManager stateManager;
  final gm.GameState? gameState;

  const StatusBar({Key? key, required this.stateManager, required this.gameState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ws = stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
    final isConnected = ws['isConnected'] == true;

    final phase = gameState?.phase.name ?? 'waiting';
    final current = gameState?.currentPlayer?.name ?? '—';
    final turn = gameState?.turnNumber ?? 0;
    final round = gameState?.roundNumber ?? 1;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.lightGray.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(isConnected ? Icons.wifi : Icons.wifi_off, color: isConnected ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Text('Phase: $phase', style: AppTextStyles.bodyMedium),
          const SizedBox(width: 12),
          Text('Turn: $turn', style: AppTextStyles.bodyMedium),
          const SizedBox(width: 12),
          Text('Round: $round', style: AppTextStyles.bodyMedium),
          const Spacer(),
          Text('Current: $current', style: AppTextStyles.bodyLarge),
        ],
      ),
    );
  }
}


