import 'package:flutter/material.dart';
import '../../../../managers/navigation_manager.dart';
import '../../../../managers/state_manager.dart';

class CurrentRoomWidget extends StatelessWidget {
  final Function(String) onLeaveRoom;

  const CurrentRoomWidget({
    Key? key,
    required this.onLeaveRoom,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recall = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final ws = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
        final isConnected = (ws['connected'] ?? ws['isConnected']) == true;
        final currentRoom = recall['currentRoom'] as Map<String, dynamic>?;
        // Access players from the game state
        final gameStateJson = recall['gameState'] as Map<String, dynamic>?;
        final gameStatePlayers = gameStateJson?['players'] as List<dynamic>?;
        final players = (gameStatePlayers ?? const []).cast<Map<String, dynamic>>();
        final isRoomOwner = recall['isRoomOwner'] == true;

        if (currentRoom == null) return const SizedBox.shrink();

        final roomId = currentRoom['room_id']?.toString() ?? '';
        final roomName = currentRoom['room_name']?.toString() ?? roomId;
        final maxPlayers = currentRoom['max_size'] ?? players.length;

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
                    Semantics(
                      label: 'enter_game_screen',
                      identifier: 'enter_game_screen',
                      button: true,
                      child: ElevatedButton(
                        onPressed: isConnected
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
                      onPressed: isConnected ? () => onLeaveRoom(roomId) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Leave'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Room: $roomName'),
                Text('Room ID: $roomId'),
                Text('Players: ${players.length}/$maxPlayers'),
                if (isRoomOwner)
                  const Text(
                    'You are the room owner',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
} 