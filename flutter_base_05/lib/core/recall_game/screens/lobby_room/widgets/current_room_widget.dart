import 'package:flutter/material.dart';

class CurrentRoomWidget extends StatelessWidget {
  final Map<String, dynamic>? currentRoomInfo;
  final String? currentRoomId;
  final bool isConnected;
  final VoidCallback onLeaveRoom;

  const CurrentRoomWidget({
    Key? key,
    required this.currentRoomInfo,
    required this.currentRoomId,
    required this.isConnected,
    required this.onLeaveRoom,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (currentRoomInfo == null) {
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
                ElevatedButton(
                  onPressed: isConnected && currentRoomId != null ? onLeaveRoom : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Leave'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Room ID: ${currentRoomInfo!['room_id']}'),
            Text('Owner: ${currentRoomInfo!['owner_id']}'),
            Text('Members: ${currentRoomInfo!['current_size']}/${currentRoomInfo!['max_size']}'),
            Text('Permission: ${currentRoomInfo!['permission']}'),
          ],
        ),
      ),
    );
  }
} 