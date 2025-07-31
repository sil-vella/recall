import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../managers/state_manager.dart';
import '../../../../managers/websockets/websocket_manager.dart';

class ConnectionStatusWidget extends StatelessWidget {
  final WebSocketManager websocketManager;

  const ConnectionStatusWidget({
    Key? key,
    required this.websocketManager,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<StateManager>(
      builder: (context, stateManager, child) {
        // Get WebSocket connection state from StateManager
        final websocketState = stateManager.getModuleState<Map<String, dynamic>>("websocket") ?? {};
        final isConnected = websocketState['isConnected'] ?? false;
        
        // Also check the direct WebSocket manager for more detailed status
        final isConnecting = websocketManager.isConnecting;
        
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isConnected ? Colors.green : isConnecting ? Colors.orange : Colors.red,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                isConnected ? Icons.wifi : isConnecting ? Icons.sync : Icons.wifi_off,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                isConnected ? 'Connected' : isConnecting ? 'Connecting...' : 'Disconnected',
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