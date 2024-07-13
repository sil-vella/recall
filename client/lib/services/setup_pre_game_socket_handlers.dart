import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../game_state.dart';
import 'socket_service.dart';

void setupPreGameSocketHandlers(BuildContext context) {
  void updateStateHandler(Map<String, dynamic> updates) {
    Provider.of<GameState>(context, listen: false)
        .updateSection('preGameState', updates['preGameState'] ?? {});
    if (updates.containsKey('gameId')) {
      Provider.of<GameState>(context, listen: false)
          .setGameId(updates['gameId']);
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
