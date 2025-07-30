import 'package:flutter/material.dart';

class RoomListWidget extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> rooms;
  final bool isLoading;
  final bool isConnected;
  final Function(String) onJoinRoom;
  final Function(String)? onLeaveRoom;
  final String? currentRoomId;
  final String emptyMessage;

  const RoomListWidget({
    Key? key,
    required this.title,
    required this.rooms,
    required this.isLoading,
    required this.isConnected,
    required this.onJoinRoom,
    this.onLeaveRoom,
    this.currentRoomId,
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
                  final roomId = room['room_id'] as String?;
                  final isInThisRoom = currentRoomId == roomId;
                  
                  return ListTile(
                    title: Text('Room: ${room['room_name'] ?? room['room_id']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Members: ${room['current_size']}/${room['max_size']}'),
                        if (room['owner_id'] != null)
                          Text('Owner: ${room['owner_id']}'),
                        if (room['permission'] != null)
                          Text('Type: ${room['permission']}'),
                      ],
                    ),
                    trailing: isInThisRoom
                        ? ElevatedButton(
                            onPressed: isConnected && onLeaveRoom != null 
                                ? () => onLeaveRoom!(roomId!) 
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Leave'),
                          )
                        : ElevatedButton(
                            onPressed: isConnected ? () => onJoinRoom(roomId!) : null,
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