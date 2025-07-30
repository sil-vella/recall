import 'package:flutter/material.dart';
import '../../../../managers/websockets/websocket_manager.dart';
import '../../../../managers/websockets/websocket_events.dart';

class ConnectionStatusWidget extends StatelessWidget {
  final WebSocketManager websocketManager;

  const ConnectionStatusWidget({
    Key? key,
    required this.websocketManager,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionStatusEvent>(
      stream: websocketManager.connectionStatus,
      builder: (context, snapshot) {
        final isConnected = snapshot.data?.status == ConnectionStatus.connected || websocketManager.isConnected;
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