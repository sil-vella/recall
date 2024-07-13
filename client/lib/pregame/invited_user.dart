// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';

class InvitedUser extends StatefulWidget {
  final String gameId;
  final String username;
  final ValueChanged<String> onUsernameChange;

  const InvitedUser({
    super.key,
    required this.gameId,
    required this.username,
    required this.onUsernameChange,
  });

  @override
  _InvitedUserState createState() => _InvitedUserState();
}

class _InvitedUserState extends State<InvitedUser> {
  String gameState = '';

  void handleJoinRoom() {
    // GameRoomOperations.joinRoom(widget.username, widget.gameId);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gameState == '') ...[
            Text('Game Room Id: ${widget.gameId}'),
            const SizedBox(height: 8.0),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Enter Username',
              ),
              onChanged: widget.onUsernameChange,
            ),
            const SizedBox(height: 8.0),
            ElevatedButton(
              onPressed: widget.username.isEmpty ? null : handleJoinRoom,
              child: const Text('Join Game'),
            ),
          ] else if (gameState == 'room_closed') ...[
            const Text('Room has closed. Game is ongoing..'),
          ],
        ],
      ),
    );
  }
}
