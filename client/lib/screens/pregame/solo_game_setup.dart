import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:client/utilities/utility.dart';
import 'package:client/blocs/game/game_bloc.dart';
import 'package:client/blocs/game/game_event.dart';
import 'package:client/blocs/game/game_state.dart';

class SoloGameSetup extends StatelessWidget {
  final String gameId;

  const SoloGameSetup({super.key, required this.gameId});

  void handleJoinRoom(BuildContext context) {
    final gameBloc = context.read<GameBloc>();

    // Update the state to 'activeGameRoom' within 'gameData'
    final updatedGameData = {'gameState': 'activeGameRoom'};

    gameBloc.add(UpdateStatePart('preGameState.gameData', updatedGameData));

    final preGameState = gameBloc.state.preGameState;
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
