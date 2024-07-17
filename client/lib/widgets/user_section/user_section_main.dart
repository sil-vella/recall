import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:client/blocs/game/game_bloc.dart';
import 'package:client/blocs/game/game_state.dart';
import 'package:client/widgets/user_section/user_section_actions.dart';
import 'package:client/widgets/user_section/user_section_hand.dart';

class UserSectionMain extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameBloc, GameState>(
      builder: (context, gameState) {
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
