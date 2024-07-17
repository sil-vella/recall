import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:client/screens/pregame/pregame_main.dart';
import 'package:client/screens/active_game_room/active_game_room_main.dart';
import 'package:client/blocs/game/game_bloc.dart';
import 'package:client/blocs/game/game_state.dart';
import 'package:client/services/setup_pre_game_socket_handlers.dart' as pre_game_handlers;
import 'package:client/services/setup_active_game_socket_handlers.dart' as active_game_handlers;

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pre_game_handlers.setupPreGameSocketHandlers(context);
      active_game_handlers.setupActiveGameSocketHandlers(context);
    });
  }

  @override
  void dispose() {
    pre_game_handlers.cleanupPreGameSocketHandlers();
    active_game_handlers.cleanupActiveGameSocketHandlers();
    super.dispose();
  }

  Widget _buildContent(GameState state) {
    final gameData = state.preGameState['gameData'] ?? {};
    final gameStateValue = gameData['gameState'];

    if (gameStateValue == 'activeGameRoom') {
      return const ActiveGameRoomMain();
    } else {
      return const PreGameMain();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: BlocBuilder<GameBloc, GameState>(
          // This condition determines if the builder function should be called
          buildWhen: (previous, current) => previous.preGameState['gameData'] != current.preGameState['gameData'],
          // The builder function is called whenever the state changes and the condition is met
          builder: (context, state) {
            return _buildContent(state); // Builds the content based on the current state
          },
        ),
      ),
    );
  }

}
