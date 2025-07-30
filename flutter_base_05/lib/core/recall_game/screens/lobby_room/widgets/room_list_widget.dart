import 'package:flutter/material.dart';

class RoomListWidget extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> rooms;
  final bool isLoading;
  final bool isConnected;
  final Function(String) onJoinRoom;
  final String emptyMessage;

  const RoomListWidget({
    Key? key,
    required this.title,
    required this.rooms,
    required this.isLoading,
    required this.isConnected,
    required this.onJoinRoom,
    required this.emptyMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (rooms.isEmpty)
              Text(emptyMessage)
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return ListTile(
                    title: Text('Room: ${room['room_id']}'),
                    subtitle: Text('Members: ${room['current_size']}/${room['max_size']}'),
                    trailing: ElevatedButton(
                      onPressed: isConnected ? () => onJoinRoom(room['room_id']) : null,
                      child: const Text('Join'),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
} 