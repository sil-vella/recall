import 'package:flutter/material.dart';
import 'package:client/utilities/user_input.dart';

class MultiGameSetup extends StatelessWidget {
  final String username;
  final String gameId;
  final String shareLink;

  const MultiGameSetup(
      {super.key,
      required this.username,
      required this.gameId,
      required this.shareLink});

  void handleCopyLink(BuildContext context) {
    UserInput.copyTextToClipboard(shareLink);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  void handleJoinRoom() {
    // GameRoomOperations.joinRoom(username, gameId, 'multiplayer');
  }

  @override
  Widget build(BuildContext context) {
    return gameId.isNotEmpty && username.isNotEmpty
        ? Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Game Room Id: $gameId'),
                const SizedBox(height: 8.0),
                Text('Your Username: $username'),
                const SizedBox(height: 16.0),
                ElevatedButton(
                  onPressed: handleJoinRoom,
                  child: const Text('Join Game'),
                ),
                const SizedBox(height: 8.0),
                ElevatedButton(
                  onPressed: () => handleCopyLink(context),
                  child: const Text('Share Link'),
                ),
              ],
            ),
          )
        : Container();
  }
}
