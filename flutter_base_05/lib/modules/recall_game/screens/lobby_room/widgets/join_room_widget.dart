import 'package:flutter/material.dart';
import '../../../../../tools/logging/logger.dart';

class JoinRoomWidget extends StatelessWidget {
  static final Logger _log = Logger();
  final VoidCallback onJoinRoom;
  final TextEditingController roomIdController;

  const JoinRoomWidget({
    Key? key,
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
                      onPressed: () {
                        final roomId = roomIdController.text.trim();
                        _log.info('🎮 Joining room: $roomId');
                        onJoinRoom();
                      },
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
  }
} 