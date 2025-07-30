import 'package:flutter/material.dart';

class JoinRoomWidget extends StatelessWidget {
  final bool isLoading;
  final bool isConnected;
  final VoidCallback onJoinRoom;
  final TextEditingController roomIdController;

  const JoinRoomWidget({
    Key? key,
    required this.isLoading,
    required this.isConnected,
    required this.onJoinRoom,
    required this.roomIdController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                  child: TextField(
                    controller: roomIdController,
                    decoration: const InputDecoration(
                      labelText: 'Room ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: isConnected && !isLoading ? onJoinRoom : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Join'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 