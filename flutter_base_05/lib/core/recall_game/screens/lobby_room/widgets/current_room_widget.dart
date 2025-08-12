import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../managers/state_manager.dart';
import '../../../../managers/navigation_manager.dart';

class CurrentRoomWidget extends StatelessWidget {
  final StateManager stateManager;
  final bool isConnected;
  final Function(String) onLeaveRoom;

  const CurrentRoomWidget({
    Key? key,
    required this.stateManager,
    required this.isConnected,
    required this.onLeaveRoom,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<StateManager>(
      builder: (context, stateManager, child) {
        // Get recall game state from StateManager
        final recallState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
        final currentRoom = recallState['currentRoom'];
        final currentRoomId = recallState['currentRoomId'];
        
        // Get WebSocket connection state from StateManager
        final websocketState = stateManager.getModuleState<Map<String, dynamic>>("websocket") ?? {};
        final isConnected = websocketState['isConnected'] ?? false;
        
        if (currentRoom == null) {
          return const SizedBox.shrink();
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Current Room',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Enter Game button
                    Semantics(
                      label: 'enter_game_screen',
                      identifier: 'enter_game_screen',
                      button: true,
                      child: ElevatedButton(
                        onPressed: isConnected && currentRoomId != null
                            ? () => NavigationManager().navigateTo('/recall/game-play')
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Enter Game'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: isConnected && currentRoomId != null ? () => onLeaveRoom(currentRoomId!) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Leave'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Room ID: ${currentRoom['room_id']}'),
                Text('Owner: ${currentRoom['owner_id']}'),
                Text('Members: ${currentRoom['current_size']}/${currentRoom['max_size']}'),
                Text('Permission: ${currentRoom['permission']}'),
              ],
            ),
          ),
        );
      },
    );
  }
} 