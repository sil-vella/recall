import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import '../../../../../../utils/consts/theme_consts.dart';
import '../../../../../tools/logging/logger.dart';

class StatusBar extends StatelessWidget {
  static final Logger _log = Logger();
  
  const StatusBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Read from validated state
        final recall = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final isConnected = recall['isConnected'] == true;
        final statusBarState = recall['statusBar'] as Map<String, dynamic>? ?? {};
        
        // Use state slice data with fallbacks to full game state
        final currentPhase = statusBarState['currentPhase'] as String? ?? 'waiting';
        final turnInfo = statusBarState['turnInfo'] as String? ?? '';
        final playerCount = statusBarState['playerCount'] as int? ?? 0;

        // Get turn and round from status bar slice
        final turn = statusBarState['turnNumber'] as int? ?? 0;
        final round = statusBarState['roundNumber'] as int? ?? 1;

        _log.info('🎮 StatusBar: Phase=$currentPhase, Turn=$turn, Round=$round, Players=$playerCount, Connected=$isConnected');

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
              Text('Phase: $currentPhase', style: AppTextStyles.bodyMedium),
              const SizedBox(width: 12),
              Text('Turn: $turn', style: AppTextStyles.bodyMedium),
              const SizedBox(width: 12),
              Text('Round: $round', style: AppTextStyles.bodyMedium),
              const Spacer(),
              Text(turnInfo.isNotEmpty ? turnInfo : 'Players: $playerCount', style: AppTextStyles.bodyLarge),
            ],
          ),
        );
      },
    );
  }
}


