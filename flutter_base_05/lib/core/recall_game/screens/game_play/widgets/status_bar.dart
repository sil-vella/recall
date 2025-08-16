import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';

import '../../../../../../utils/consts/theme_consts.dart';

class StatusBar extends StatefulWidget {
  const StatusBar({Key? key}) : super(key: key);

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
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
    final ws = _stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
    final isConnected = ws['isConnected'] == true;

    // Read from widget-specific state slice for optimal performance
    final recall = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final statusBarState = recall['statusBar'] as Map<String, dynamic>? ?? {};
    
    // Use state slice data with fallbacks to full game state
    final currentPhase = statusBarState['currentPhase'] as String? ?? 'waiting';
    final turnInfo = statusBarState['turnInfo'] as String? ?? '';
    final playerCount = statusBarState['playerCount'] as int? ?? 0;


    // Extract turn number and round from turnInfo if available, otherwise use fallback
    final turn = recall['turnNumber'] as int? ?? 0;
    final round = recall['roundNumber'] as int? ?? 1;

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
  }
}


