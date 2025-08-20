import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import 'message_board_widget.dart';
import '../../../../../tools/logging/logger.dart';

class RoomMessageBoardWidget extends StatelessWidget {
  static final Logger _log = Logger();
  
  const RoomMessageBoardWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final wsState = StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
        final currentRoomId = (wsState['currentRoomId'] ?? '') as String;
        
        _log.info('📨 RoomMessageBoardWidget: Current room ID: $currentRoomId');
        
        if (currentRoomId.isEmpty) {
          _log.info('📨 RoomMessageBoardWidget: No current room, hiding widget');
          return const SizedBox.shrink();
        }
        
        _log.info('📨 RoomMessageBoardWidget: Showing message board for room: $currentRoomId');
        return MessageBoardWidget(roomId: currentRoomId);
      },
    );
  }
}
