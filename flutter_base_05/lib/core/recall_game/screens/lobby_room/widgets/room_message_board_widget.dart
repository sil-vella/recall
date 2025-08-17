import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import 'message_board_widget.dart';

class RoomMessageBoardWidget extends StatelessWidget {
  const RoomMessageBoardWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final wsState = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
        final currentRoomId = (wsState['currentRoomId'] ?? '') as String;
        
        if (currentRoomId.isEmpty) {
          return const SizedBox.shrink();
        }
        
        return MessageBoardWidget(roomId: currentRoomId);
      },
    );
  }
}
