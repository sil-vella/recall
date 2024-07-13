import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client/game_state.dart';
import 'user_section_actions.dart';
import 'user_section_hand.dart';

class UserSectionMain extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        return Column(
          children: [
            UserSectionActions(),
            UserSectionHand(),
          ],
        );
      },
    );
  }
}
