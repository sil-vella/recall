import 'package:provider/provider.dart';
import '../game_state.dart';
import 'package:flutter/widgets.dart';
import 'socket_service.dart';

void setupActiveGameSocketHandlers(BuildContext context) {
  void updateStateHandler(Map<String, dynamic> updates) {
    if (updates.containsKey('gameId')) {
      Provider.of<GameState>(context, listen: false)
          .setGameId(updates['gameId']);
    }
    if (updates.containsKey('activeGamePlayState')) {
      Provider.of<GameState>(context, listen: false)
          .updateSection('activeGamePlayState', updates['activeGamePlayState']);
    }
    if (updates.containsKey('userSection')) {
      Provider.of<GameState>(context, listen: false)
          .updateSection('userSection', updates['userSection']);
    }
    if (updates.containsKey('messageAnimation')) {
      Provider.of<GameState>(context, listen: false)
          .setMessageAnimation(updates['messageAnimation']);
    }
    if (updates.containsKey('callWindow')) {
      Provider.of<GameState>(context, listen: false)
          .updateSection('callWindow', updates['callWindow']);
    }
  }

  final handleSocketEvents = [
    {
      'event': 'loading',
      'handler': (data) => updateStateHandler({'activeGamePlayState': data}),
    },
    {
      'event': 'loading',
      'handler': (data) => updateStateHandler({'userSection': data}),
    },
    {
      'event': 'same_rank_phase',
      'handler': (data) => updateStateHandler({'activeGamePlayState': data}),
    },
    {
      'event': 'gameWinner',
      'handler': (data) => updateStateHandler(
          {'gameId': data}), // Assuming GAME_WINNER updates gameId
    },
    {
      'event': 'player_data',
      'handler': (data) => updateStateHandler({'userSection': data}),
    },
    {
      'event': 'revealTwoCards',
      'handler': (data) => updateStateHandler({'userSection': data}),
    },
    {
      'event': 'msgBoardAndAnim',
      'handler': (data) => updateStateHandler({'messageAnimation': data}),
    },
    {
      'event': 'callWindow',
      'handler': (data) => updateStateHandler({'callWindow': data}),
    },
  ];

  SocketService.setEventHandlers(handleSocketEvents);
  SocketService.getSocket();
}

void cleanupActiveGameSocketHandlers() {
  SocketService.disconnect();
}
