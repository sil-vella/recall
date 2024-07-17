import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:client/blocs/game/game_bloc.dart';
import 'package:client/blocs/game/game_event.dart';
import 'package:client/services/socket_service.dart';

void setupActiveGameSocketHandlers(BuildContext context) {
  void updateStateHandler(Map<String, dynamic> updates) {
    final gameBloc = context.read<GameBloc>();

    if (updates.containsKey('gameId')) {
      gameBloc.add(SetGameId(updates['gameId']));
    }
    if (updates.containsKey('activeGamePlayState')) {
      gameBloc.add(UpdateStatePart('activeGamePlayState', updates['activeGamePlayState']));
    }
    if (updates.containsKey('userSection')) {
      gameBloc.add(UpdateStatePart('userSection', updates['userSection']));
    }
    if (updates.containsKey('messageAnimation')) {
      gameBloc.add(SetMessageAnimation(updates['messageAnimation']));
    }
    if (updates.containsKey('callWindow')) {
      gameBloc.add(UpdateStatePart('callWindow', updates['callWindow']));
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
      'handler': (data) => updateStateHandler({'gameId': data}), // Assuming GAME_WINNER updates gameId
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
