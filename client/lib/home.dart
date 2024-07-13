import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pregame/pregame_main.dart';
import 'active_game_room/active_game_room_main.dart';
import 'game_state.dart';
import 'services/setup_pre_game_socket_handlers.dart' as pre_game_handlers;
import 'services/setup_active_game_socket_handlers.dart'
    as active_game_handlers;

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

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, _) {
        final gameData = gameState.preGameState['gameData'] ?? {};
        final gameStateValue = gameData['gameState'];

        return Scaffold(
          body: Center(
            child: gameStateValue == 'activeGameRoom'
                ? const ActiveGameRoomMain()
                : const PreGameMain(), // Default to showing PreGameMain
          ),
        );
      },
    );
  }
}
