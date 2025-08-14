import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';

class RoomListWidget extends StatefulWidget {
  final String title;
  final Function(String) onJoinRoom;
  final Function(String) onLeaveRoom;
  final String emptyMessage;
  final String roomType; // 'public' or 'my'

  const RoomListWidget({
    Key? key,
    required this.title,
    required this.onJoinRoom,
    required this.onLeaveRoom,
    required this.emptyMessage,
    required this.roomType,
  }) : super(key: key);

  @override
  State<RoomListWidget> createState() => _RoomListWidgetState();
}

class _RoomListWidgetState extends State<RoomListWidget> {
  final StateManager _sm = StateManager();

  @override
  void initState() {
    super.initState();
    _sm.addListener(_onChanged);
  }

  @override
  void dispose() {
    _sm.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    final rooms = (recall['rooms'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final currentRoomId = (recall['currentRoomId'] ?? '') as String;
    final ws = _sm.getModuleState<Map<String, dynamic>>('websocket') ?? {};
    final isConnected = (ws['connected'] ?? ws['isConnected']) == true;
    final isLoading = recall['isLoading'] == true;

    return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                if (isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (rooms.isEmpty)
                  Text(widget.emptyMessage)
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rooms.length,
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      final roomId = room['room_id']?.toString() ?? '';
                      final isInThisRoom = currentRoomId == roomId;
                      
                       return ListTile(
                        title: Text('Room: ${room['room_name'] ?? roomId}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Players: ${(room['current_size'] ?? '?')}/${room['max_size'] ?? '?'}'),
                            if (room['permission'] == 'private')
                              const Text('🔒 Private', style: TextStyle(color: Colors.orange)),
                          ],
                        ),
                         trailing: isInThisRoom
                             ? Semantics(
                                 label: 'room_leave_${roomId}',
                                 identifier: 'room_leave_${roomId}',
                                 button: true,
                                  child: ElevatedButton(
                                     onPressed: isConnected ? () => widget.onLeaveRoom(roomId) : null,
                                   style: ElevatedButton.styleFrom(
                                     backgroundColor: Colors.red,
                                     foregroundColor: Colors.white,
                                   ),
                                   child: const Text('Leave'),
                                 ),
                               )
                             : Semantics(
                                 label: 'room_join_${roomId}',
                                 identifier: 'room_join_${roomId}',
                                 button: true,
                                  child: ElevatedButton(
                                    onPressed: isConnected ? () => widget.onJoinRoom(roomId) : null,
                                   child: const Text('Join'),
                                 ),
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