import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import '../../../models/game_state.dart' as gm;
import '../../../../../../utils/consts/theme_consts.dart';

class StatusBar extends StatefulWidget {
  final StateManager stateManager;
  final gm.GameState? gameState;

  const StatusBar({Key? key, required this.stateManager, required this.gameState}) : super(key: key);

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
  @override
  void initState() {
    super.initState();
    widget.stateManager.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.stateManager.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
    final isConnected = ws['isConnected'] == true;

    final phase = widget.gameState?.phase.name ?? 'waiting';
    final current = widget.gameState?.currentPlayer?.name ?? '—';
    final turn = widget.gameState?.turnNumber ?? 0;
    final round = widget.gameState?.roundNumber ?? 1;

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


