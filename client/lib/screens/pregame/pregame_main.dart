import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:client/utilities/utility.dart';
import 'package:client/screens/pregame/multi_game_setup.dart';
import 'package:client/screens/pregame/invited_user.dart';
import 'package:client/screens/pregame/solo_game_setup.dart';
import 'package:client/blocs/game/game_bloc.dart';
import 'package:client/blocs/game/game_event.dart';
import 'package:client/blocs/game/game_state.dart';
import 'package:client/services/setup_pre_game_socket_handlers.dart';

class PreGameMain extends StatefulWidget {
  const PreGameMain({super.key});

  @override
  PreGameMainState createState() => PreGameMainState();
}

class PreGameMainState extends State<PreGameMain> {
  String gameMode = 'solo';
  String username = '';
  String numOfOpponents = '2';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setupPreGameSocketHandlers(context);
    });
  }

  void handleGameModeChange(String? value) {
    setState(() {
      gameMode = value ?? 'solo';
    });
  }

  void onUsernameChange(String value) {
    setState(() {
      username = value;
    });
  }

  void onNumOfOppChange(String? value) {
    setState(() {
      numOfOpponents = value ?? '2';
    });
  }

  void handleCreateSoloGame(BuildContext context) {
    if (gameMode.isNotEmpty) {
      final gameData = {
        'gameMode': gameMode,
        'numOfOpponents': numOfOpponents,
      };
      final playerData = {
        'gameCreatorUsername': 'You',
      };
      Utility.emitEvent('game_mode_selection',
          {'gameData': gameData, 'playerData': playerData});
    }
  }

  void handleCreateMultiGame(BuildContext context) {
    if (gameMode.isNotEmpty && username.isNotEmpty) {
      final gameData = {
        'gameMode': gameMode,
      };
      final playerData = {
        'gameCreatorUsername': username,
        'username': username,
      };
      Utility.emitEvent('game_mode_selection',
          {'gameData': gameData, 'playerData': playerData});
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameBloc, GameState>(
      builder: (context, gameState) {
        final preGameState = gameState.preGameState;
        final gameData = preGameState['gameData'] ?? {};
        final gameStateValue = gameData['gameState'];
        final gameId = gameData['gameId'];
        final playerData = preGameState['playerData'] ?? {};
        final username = playerData['username'] ?? 'Player';
        final shareLink = gameData['shareLink'] ?? '';

        return Center(
          child: Column(
            children: [
              if (gameStateValue == 'pre_game') ...[
                RadioListTile<String>(
                  title: const Text('Solo Play'),
                  value: 'solo',
                  groupValue: gameMode,
                  onChanged: handleGameModeChange,
                ),
                RadioListTile<String>(
                  title: const Text('Multiplayer'),
                  value: 'multiplayer',
                  groupValue: gameMode,
                  onChanged: handleGameModeChange,
                ),
                if (gameMode == 'multiplayer') ...[
                  TextField(
                    onChanged: onUsernameChange,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  ElevatedButton(
                    onPressed: () => handleCreateMultiGame(context),
                    child: const Text('Create New Game'),
                  ),
                ],
                if (gameMode == 'solo') ...[
                  DropdownButton<String>(
                    value: numOfOpponents,
                    items: ['2', '3', '4']
                        .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: onNumOfOppChange,
                  ),
                  ElevatedButton(
                    onPressed: () => handleCreateSoloGame(context),
                    child: const Text('Create New Game'),
                  ),
                ],
              ],
              if (gameStateValue == 'multiplayer_game_ready' &&
                  shareLink.isNotEmpty &&
                  playerData.isNotEmpty) ...[
                MultiGameSetup(
                  gameId: gameId,
                  username: username,
                  shareLink: shareLink,
                ),
              ],
              if (gameStateValue == 'received_invitation' &&
                  gameId != null &&
                  playerData != null) ...[
                InvitedUser(
                  gameId: gameId,
                  username: username,
                  onUsernameChange: onUsernameChange,
                ),
              ],
              if (gameStateValue == 'solo_game_ready' && gameId != null) ...[
                SoloGameSetup(
                  gameId: gameId,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
