import 'package:flutter/material.dart';
import '../utilities/utility.dart';
import '../game_state.dart';
import 'package:provider/provider.dart';

class SoloGameSetup extends StatelessWidget {
  final String gameId;

  const SoloGameSetup({super.key, required this.gameId});

  void handleJoinRoom(BuildContext context) {
    final gameState = Provider.of<GameState>(context, listen: false);

    // Update the state to 'activeGameRoom' within 'gameData'
    final updatedGameData =
        Map<String, dynamic>.from(gameState.preGameState['gameData'] ?? {});
    updatedGameData['gameState'] = 'activeGameRoom';

    gameState.updateGameData(updatedGameData);

    final preGameState = gameState.preGameState;
    Utility.emitEvent('starting-game', preGameState);
  }

  @override
  Widget build(BuildContext context) {
    return gameId.isNotEmpty
        ? Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton(
                  onPressed: () => handleJoinRoom(context),
                  child: const Text('Start Game'),
                ),
              ],
            ),
          )
        : Container();
  }
}
