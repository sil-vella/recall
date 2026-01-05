import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';

class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final ws = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
        final dutch = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final isConnected = (ws['connected'] ?? ws['isConnected']) == true;
        final isLoading = dutch['isLoading'] == true || ws['connecting'] == true;


        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isConnected ? AppColors.successColor : isLoading ? AppColors.warningColor : AppColors.errorColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                isConnected ? Icons.wifi : isLoading ? Icons.sync : Icons.wifi_off,
                color: AppColors.textOnAccent,
              ),
              const SizedBox(width: 8),
              Text(
                isConnected ? 'Connected' : isLoading ? 'Connecting...' : 'Disconnected',
                style: TextStyle(
                  color: AppColors.textOnAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}