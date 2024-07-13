import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client/utilities/utility.dart';
import 'package:client/game_state.dart';

class UserSectionActions extends StatefulWidget {
  @override
  _UserSectionActionsState createState() => _UserSectionActionsState();
}

class _UserSectionActionsState extends State<UserSectionActions> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final callWindow = context.read<GameState>().callWindow;

      if (callWindow['active'] ?? false) {
        Future.delayed(Duration(seconds: 5), () {
          if (mounted) {
            context
                .read<GameState>()
                .updateSection('callWindow', {'active': false});
          }
        });
      }
    });
  }

  void handleCallGameClick() {
    final gameId = context.read<GameState>().gameId;
    Utility.emitEvent('userCalledGame', {'game_id': gameId});
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        final callWindowActive = gameState.callWindow['active'] ?? false;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Column(
            children: [
              if (callWindowActive)
                ElevatedButton(
                  onPressed: handleCallGameClick,
                  child: Text('Call Game'),
                ),
            ],
          ),
        );
      },
    );
  }
}
