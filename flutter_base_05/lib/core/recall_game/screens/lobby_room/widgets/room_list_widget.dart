import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import '../../../../managers/navigation_manager.dart';
import '../../../managers/recall_game_manager.dart';

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
  final RecallGameManager _gameManager = RecallGameManager();

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

  Future<void> _joinGame(String roomId) async {
    try {
      print('🎮 Joining game for room: $roomId');
      
      // First join the room if not already in it
      final currentRoomId = _sm.getModuleState<Map<String, dynamic>>('recall_game')?['currentRoomId'];
      if (currentRoomId != roomId) {
        print('🔄 Joining room: $roomId (currently in: $currentRoomId)');
        await widget.onJoinRoom(roomId);
      } else {
        print('✅ Already in room: $roomId');
      }
      
      // Then join the game as a player
      final login = _sm.getModuleState<Map<String, dynamic>>('login') ?? {};
      final playerName = (login['username'] ?? login['email'] ?? 'Player').toString();
      
      print('🎮 Joining game as: $playerName');
      final joinResult = await _gameManager.joinGame(roomId, playerName);
      if (joinResult['error'] != null) {
        _showSnackBar('Failed to join game: ${joinResult['error']}', isError: true);
        return;
      }
      
      // Navigate to game screen (match will be started from there)
      print('🎯 Navigating to game screen...');
      NavigationManager().navigateTo('/recall/game-play');
      
    } catch (e) {
      print('❌ Error joining game: $e');
      _showSnackBar('Error joining game: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recall = _sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    
    // Filter rooms based on roomType
    List<Map<String, dynamic>> rooms;
    if (widget.roomType == 'my') {
      rooms = (recall['myRooms'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
      print('🔍 DEBUG: My Rooms count: ${rooms.length}');
      print('🔍 DEBUG: My Rooms data: $rooms');
    } else {
      rooms = (recall['rooms'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
      print('🔍 DEBUG: Public Rooms count: ${rooms.length}');
    }
    
    final currentRoomId = (recall['currentRoomId'] ?? '') as String;
    final ws = _sm.getModuleState<Map<String, dynamic>>('websocket') ?? {};
    final isConnected = (ws['connected'] ?? ws['isConnected']) == true;
    final isLoading = recall['isLoading'] == true;
    
    print('🔍 DEBUG: Room type: ${widget.roomType}');
    print('🔍 DEBUG: Current room ID: $currentRoomId');
    print('🔍 DEBUG: Is connected: $isConnected');

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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Show Join Game button for room owners in "my" rooms
                            if (widget.roomType == 'my') ...[
                              Builder(builder: (context) {
                                print('🔍 DEBUG: Checking Join Game button for room: $roomId');
                                print('🔍 DEBUG: Room type: ${widget.roomType}, isInThisRoom: $isInThisRoom');
                                
                                // Show Join Game button for room owners (whether in room or not)
                                return Semantics(
                                  label: 'room_join_game_${roomId}',
                                  identifier: 'room_join_game_${roomId}',
                                  button: true,
                                  child: ElevatedButton(
                                    onPressed: isConnected ? () => _joinGame(roomId) : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Join Game'),
                                  ),
                                );
                              }),
                            ],
                            const SizedBox(width: 8),
                            // Show Join/Leave button
                            if (isInThisRoom)
                              Semantics(
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
                            else
                              Semantics(
                                label: 'room_join_${roomId}',
                                identifier: 'room_join_${roomId}',
                                button: true,
                                child: ElevatedButton(
                                  onPressed: isConnected ? () => widget.onJoinRoom(roomId) : null,
                                  child: const Text('Join'),
                                ),
                              ),
                          ],
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