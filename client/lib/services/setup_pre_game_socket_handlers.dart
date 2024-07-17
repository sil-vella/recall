import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:client/blocs/game/game_bloc.dart';
import 'package:client/blocs/game/game_event.dart';
import 'package:client/services/socket_service.dart';

void setupPreGameSocketHandlers(BuildContext context) {
  void updateStateHandler(Map<String, dynamic> updates) {
    final gameBloc = context.read<GameBloc>();

    if (updates.containsKey('preGameState')) {
      gameBloc.add(UpdateStatePart('preGameState', updates['preGameState'] ?? {}));
    }
    if (updates.containsKey('gameId')) {
      gameBloc.add(SetGameId(updates['gameId']));
    }
  }

  final handleSocketEvents = [
    {
      'event': 'multiplayer_game_ready',
      'handler': (data) {
        updateStateHandler({
          'preGameState': {
            'gameData': data['gameData'] ?? {},
            'playerData': data['playerData'] ?? {},
          },
          'gameId': data['gameData']?['gameId'] ?? '',
        });
      }
    },
    {
      'event': 'solo_game_ready',
      'handler': (data) {
        updateStateHandler({
          'preGameState': {
            'gameData': data['gameData'] ?? {},
            'playerData': data['playerData'] ?? {},
          },
          'gameId': data['gameData']?['gameId'] ?? '',
        });
      }
    },
  ];

  SocketService.setEventHandlers(handleSocketEvents);
  SocketService.getSocket();
}

void cleanupPreGameSocketHandlers() {
  SocketService.disconnect();
}
