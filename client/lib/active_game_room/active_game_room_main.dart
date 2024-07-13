import 'package:flutter/material.dart';
import 'game_play/game_play_main.dart';
import 'user_section/user_section_main.dart';

class ActiveGameRoomMain extends StatelessWidget {
  const ActiveGameRoomMain({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Active Game Room Screen'),
        Expanded(
          child: GamePlayMain(),
        ),
        Expanded(
          child: UserSectionMain(),
        ),
      ],
    );
  }
}
