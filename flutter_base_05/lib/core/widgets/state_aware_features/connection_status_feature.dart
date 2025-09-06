import 'package:flutter/material.dart';
import '../../managers/state_manager.dart';
import '../../managers/websockets/websocket_manager.dart';

/// State-aware connection status feature widget
/// 
/// This widget subscribes to the websocket state slice and updates dynamically
/// when the connection status changes. It follows the same pattern as other
/// widgets in the app using ListenableBuilder.
class StateAwareConnectionStatusFeature extends StatelessWidget {
  const StateAwareConnectionStatusFeature({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get WebSocket state from StateManager
        final websocketState = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
        final isConnected = websocketState['isConnected'] == true;
        
        // Get connecting state from WebSocketManager
        final websocketManager = WebSocketManager.instance;
        final isConnecting = websocketManager.isConnecting;
        
        // Determine icon and color based on state
        IconData icon;
        Color color;
        String tooltip;
        
        if (isConnecting) {
          icon = Icons.sync;
          color = Colors.orange;
          tooltip = 'WebSocket Connecting...';
        } else if (isConnected) {
          icon = Icons.wifi;
          color = Colors.green;
          tooltip = 'WebSocket Connected - Tap to disconnect';
        } else {
          icon = Icons.wifi_off;
          color = Colors.red;
          tooltip = 'WebSocket Disconnected - Tap to connect';
        }
        
        return IconButton(
          icon: isConnecting 
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            : Icon(icon, color: color),
          onPressed: isConnecting 
            ? null // Disable button while connecting
            : () async {
                if (isConnected) {
                  // Disconnect if currently connected
                  websocketManager.disconnect();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('WebSocket: Disconnecting...'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } else {
                  // Connect if currently disconnected
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('WebSocket: Connecting...'),
                      backgroundColor: Colors.blue,
                    ),
                  );
                  
                  final success = await websocketManager.connect();
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('WebSocket: Connected successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('WebSocket: Connection failed'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
          tooltip: tooltip,
        );
      },
    );
  }
}
