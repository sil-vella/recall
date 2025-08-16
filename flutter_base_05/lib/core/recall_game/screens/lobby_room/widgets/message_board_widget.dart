import 'package:flutter/material.dart';
import '../../../../managers/state_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';

class MessageBoardWidget extends StatefulWidget {
  final String? roomId; // null => session board

  const MessageBoardWidget({Key? key, this.roomId}) : super(key: key);

  @override
  State<MessageBoardWidget> createState() => _MessageBoardWidgetState();
}

class _MessageBoardWidgetState extends State<MessageBoardWidget> {
  final StateManager _stateManager = StateManager(); // ✅ Pattern 1: Widget creates its own instance

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
    final data = _stateManager.getModuleState<Map<String, dynamic>>('recall_messages') ?? {};
    final sessionList = (data['session'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final rooms = (data['rooms'] as Map?)?.cast<String, List>() ?? const {};
    final list = widget.roomId == null
        ? sessionList
        : (rooms[widget.roomId] ?? const []).cast<Map<String, dynamic>>();

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
          Text(widget.roomId == null ? 'Session Messages' : 'Room Messages (${widget.roomId})', style: AppTextStyles.headingSmall()),
          const SizedBox(height: 8),
          ...list.reversed.take(20).map((e) => _MessageTile(entry: e)).toList(),
        ],
      ),
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
            width: 6,
            height: 24,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: _levelColor(level),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? level.toUpperCase() : title, style: AppTextStyles.bodyLarge),
                if (message.isNotEmpty) Text(message, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accentColor2)),
                Text(ts, style: AppTextStyles.headingSmall()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


