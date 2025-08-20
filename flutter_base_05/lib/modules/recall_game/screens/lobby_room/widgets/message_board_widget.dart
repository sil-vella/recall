import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../../../../tools/logging/logger.dart';

class MessageBoardWidget extends StatelessWidget {
  static final Logger _log = Logger();
  final String? roomId; // null => session board

  const MessageBoardWidget({Key? key, this.roomId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final data = StateManager().getModuleState<Map<String, dynamic>>('recall_messages') ?? {};
        final sessionList = (data['session'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final rooms = (data['rooms'] as Map?)?.cast<String, List>() ?? const {};
        final list = roomId == null
            ? sessionList
            : (rooms[roomId] ?? const []).cast<Map<String, dynamic>>();

        _log.info('📨 MessageBoardWidget: ${roomId == null ? 'Session' : 'Room $roomId'} has ${list.length} messages');

        if (list.isEmpty) {
          return Container(
            padding: AppPadding.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.lightGray.withOpacity(0.3)),
            ),
            child: Text('No messages', style: AppTextStyles.bodyMedium),
          );
        }

        return Container(
          padding: AppPadding.cardPadding,
          decoration: BoxDecoration(
            color: AppColors.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.lightGray.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(roomId == null ? 'Session Messages' : 'Room Messages (${roomId})', style: AppTextStyles.headingSmall()),
              const SizedBox(height: 8),
              ...list.reversed.take(20).map((e) => _MessageTile(entry: e)).toList(),
            ],
          ),
        );
      },
    );
  }
}

class _MessageTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _MessageTile({required this.entry});

  Color _levelColor(String level) {
    switch (level) {
      case 'success':
        return AppColors.accentColor;
      case 'warning':
        return AppColors.accentColor2;
      case 'error':
        return AppColors.redAccent;
      default:
        return AppColors.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = (entry['level'] ?? 'info').toString();
    final title = (entry['title'] ?? '').toString();
    final message = (entry['message'] ?? '').toString();
    final ts = (entry['timestamp'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _levelColor(level),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (message.isNotEmpty)
                  Text(
                    message,
                    style: AppTextStyles.bodyMedium,
                  ),
                if (ts.isNotEmpty)
                  Text(
                    ts,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 12,
                      color: AppColors.lightGray,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


