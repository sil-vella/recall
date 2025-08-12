import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../managers/state_manager.dart';

class JoinRoomWidget extends StatelessWidget {
  final StateManager stateManager;
  final bool isLoading;
  final bool isConnected;
  final VoidCallback onJoinRoom;
  final TextEditingController roomIdController;

  const JoinRoomWidget({
    Key? key,
    required this.stateManager,
    required this.isLoading,
    required this.isConnected,
    required this.onJoinRoom,
    required this.roomIdController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<StateManager>(
      builder: (context, stateManager, child) {
        // Get recall game state from StateManager
        final recallState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
        final isLoading = recallState['isLoading'] ?? false;
        
        // Get WebSocket connection state from StateManager
        final websocketState = stateManager.getModuleState<Map<String, dynamic>>("websocket") ?? {};
        final isConnected = websocketState['isConnected'] ?? false;
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Join Room',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'join_room_field_room_id',
                        identifier: 'join_room_field_room_id',
                        textField: true,
                        child: TextField(
                        controller: roomIdController,
                        decoration: const InputDecoration(
                          labelText: 'Room ID',
                          border: OutlineInputBorder(),
                        ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      label: 'join_room_submit',
                      identifier: 'join_room_submit',
                      button: true,
                      child: ElevatedButton(
                      onPressed: isConnected && !isLoading ? onJoinRoom : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Join'),
                    ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
} 