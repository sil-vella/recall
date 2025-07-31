import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../managers/state_manager.dart';

class RoomListWidget extends StatelessWidget {
  final String title;
  final StateManager stateManager;
  final bool isLoading;
  final bool isConnected;
  final Function(String) onJoinRoom;
  final Function(String) onLeaveRoom;
  final String emptyMessage;
  final String roomType; // 'public' or 'my'

  const RoomListWidget({
    Key? key,
    required this.title,
    required this.stateManager,
    required this.isLoading,
    required this.isConnected,
    required this.onJoinRoom,
    required this.onLeaveRoom,
    required this.emptyMessage,
    required this.roomType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<StateManager>(
      builder: (context, stateManager, child) {
        // Get recall game state from StateManager
        final recallState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
        final currentRoomId = recallState['currentRoomId'];
        
        // Get WebSocket connection state from StateManager
        final websocketState = stateManager.getModuleState<Map<String, dynamic>>("websocket") ?? {};
        final isConnected = websocketState['isConnected'] ?? false;
        
        // Get rooms based on type
        List<Map<String, dynamic>> rooms = [];
        if (roomType == 'public') {
          rooms = (recallState['rooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        } else if (roomType == 'my') {
          rooms = (recallState['myRooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        }
        
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
                                onPressed: isConnected ? () => onLeaveRoom(roomId!) : null,
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
      },
    );
  }
} 