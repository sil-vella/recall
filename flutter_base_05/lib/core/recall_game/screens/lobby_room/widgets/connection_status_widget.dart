import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';

class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final ws = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
        final recall = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final isConnected = (ws['connected'] ?? ws['isConnected']) == true;
        final isLoading = recall['isLoading'] == true || ws['connecting'] == true;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isConnected ? Colors.green : isLoading ? Colors.orange : Colors.red,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                isConnected ? Icons.wifi : isLoading ? Icons.sync : Icons.wifi_off,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                isConnected ? 'Connected' : isLoading ? 'Connecting...' : 'Disconnected',
                style: const TextStyle(
                  color: Colors.white,
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