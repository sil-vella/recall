// msg_board_main.dart
import 'package:flutter/material.dart';
import 'package:client/utilities/utility.dart';

class MsgBoardMain extends StatelessWidget {
  final Map<String, dynamic> msgBoardAndAnim;

  MsgBoardMain({required this.msgBoardAndAnim});

  @override
  Widget build(BuildContext context) {
    final messages = msgBoardAndAnim['messages'] ?? [];

    return Container(
      padding: EdgeInsets.all(10),
      color: Colors.black12,
      child: Column(
        children: messages.map<Widget>((messageData) {
          final msgId = messageData['msg_id'];
          final replacements = Map<String, dynamic>.from(messageData)
            ..remove('msg_id');
          final message = Utility.formatMessage(msgId, replacements);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              message,
              style: TextStyle(color: Colors.white),
            ),
          );
        }).toList(),
      ),
    );
  }
}
