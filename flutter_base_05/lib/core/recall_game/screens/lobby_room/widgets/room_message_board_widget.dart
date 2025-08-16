import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import 'message_board_widget.dart';

class RoomMessageBoardWidget extends StatefulWidget {
  const RoomMessageBoardWidget({Key? key}) : super(key: key);

  @override
  State<RoomMessageBoardWidget> createState() => _RoomMessageBoardWidgetState();
}

class _RoomMessageBoardWidgetState extends State<RoomMessageBoardWidget> {
  final StateManager _stateManager = StateManager();

  @override
  void initState() {
    super.initState();
    _stateManager.addListener(_onChanged);
  }

  @override
  void dispose() {
    _stateManager.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final wsState = _stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
    final currentRoomId = (wsState['currentRoomId'] ?? '') as String;
    
    if (currentRoomId.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return MessageBoardWidget(roomId: currentRoomId);
  }
}
