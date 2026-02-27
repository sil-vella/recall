import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/consts/theme_consts.dart';

/// Notification type that must be shown as a modal immediately, app-wide.
const String kNotificationTypeInstant = 'instant';

/// Server-defined response action: label, endpoint, method, action (sent in body).
class ResponseAction {
  const ResponseAction({
    required this.label,
    required this.endpoint,
    required this.method,
    required this.action,
  });
  final String label;
  final String endpoint;
  final String method;
  final String action;
  static List<ResponseAction> fromMessage(Map<String, dynamic> message) {
    final list = message['responses'];
    if (list is! List || list.isEmpty) return [];
    final out = <ResponseAction>[];
    for (final e in list) {
      if (e is! Map) continue;
      final label = e['label']?.toString().trim();
      final endpoint = e['endpoint']?.toString().trim();
      final method = (e['method']?.toString().toUpperCase() ?? 'POST').trim();
      final action = e['action']?.toString().trim();
      if (label != null && label.isNotEmpty && endpoint != null && endpoint.isNotEmpty && action != null && action.isNotEmpty) {
        out.add(ResponseAction(label: label, endpoint: endpoint, method: method.isEmpty ? 'POST' : method, action: action));
      }
    }
    return out;
  }
}

/// Reusable modal for instant-type notifications. Shown app-wide when unread
/// messages with type [kNotificationTypeInstant] are present.
class InstantMessageModal extends StatelessWidget {
  const InstantMessageModal({
    Key? key,
    required this.message,
    required this.onDismiss,
    this.dismissLabel = 'OK',
    this.onSendResponse,
    this.onMarkAsRead,
  }) : super(key: key);

  final Map<String, dynamic> message;
  final VoidCallback onDismiss;
  final String dismissLabel;
  final Future<bool> Function(String endpoint, String method, Map<String, dynamic> body, Map<String, dynamic> message)? onSendResponse;
  final Future<void> Function(String messageId)? onMarkAsRead;

  String get _title => message['title']?.toString().trim().isNotEmpty == true
      ? message['title'].toString()
      : 'Notification';

  String get _body => message['body']?.toString() ?? '';

  List<ResponseAction> get _responses => ResponseAction.fromMessage(message);

  void _onInstantModalClosed() {
    final id = message['id']?.toString() ?? '';
    if (id.isNotEmpty && onMarkAsRead != null) {
      unawaited(onMarkAsRead!(id));
    }
    onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final responses = _responses;
    final hasResponseButtons = responses.isNotEmpty && onSendResponse != null;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) return;
        _onInstantModalClosed();
      },
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          _title,
          style: AppTextStyles.headingSmall(color: AppColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Text(
            _body,
            style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
          ),
        ),
        actions: hasResponseButtons
            ? responses.map((r) {
                return TextButton(
                  onPressed: () => _onResponseTap(context, r),
                  child: Text(
                    r.label,
                    style: AppTextStyles.bodyMedium(color: AppColors.accentColor),
                  ),
                );
              }).toList()
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    dismissLabel,
                    style: AppTextStyles.bodyMedium(color: AppColors.accentColor),
                  ),
                ),
              ],
      ),
    );
  }

  Future<void> _onResponseTap(BuildContext context, ResponseAction r) async {
    final send = onSendResponse;
    if (send == null) return;
    final id = message['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final body = <String, dynamic>{'message_id': id, 'action': r.action};
    final ok = await send(r.endpoint, r.method, body, message);
    if (context.mounted && ok) {
      Navigator.of(context).pop();
    }
  }

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> message,
    required VoidCallback onDismiss,
    String dismissLabel = 'OK',
    Future<bool> Function(String endpoint, String method, Map<String, dynamic> body, Map<String, dynamic> message)? onSendResponse,
    Future<void> Function(String messageId)? onMarkAsRead,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => InstantMessageModal(
        message: message,
        dismissLabel: dismissLabel,
        onDismiss: onDismiss,
        onSendResponse: onSendResponse,
        onMarkAsRead: onMarkAsRead,
      ),
    );
  }

  static final Set<String> _shownIds = {};

  static Future<void> showUnreadInstantModals(
    BuildContext context, {
    required List<Map<String, dynamic>> messages,
    required Future<void> Function(String messageId) onMarkAsRead,
    Future<bool> Function(String endpoint, String method, Map<String, dynamic> body, Map<String, dynamic> message)? onSendResponse,
  }) async {
    if (!context.mounted) return;
    final instantUnread = messages.where((m) {
      final id = m['id']?.toString() ?? '';
      final type = m['type']?.toString() ?? '';
      final readAt = m['read_at'];
      final isUnread = readAt == null || readAt == '';
      return type == kNotificationTypeInstant && isUnread && id.isNotEmpty && !_shownIds.contains(id);
    }).toList();
    for (final msg in instantUnread) {
      if (!context.mounted) break;
      final id = msg['id']?.toString() ?? '';
      _shownIds.add(id);
      await show(
        context,
        message: msg,
        onDismiss: () {},
        onSendResponse: onSendResponse,
        onMarkAsRead: onMarkAsRead,
      );
    }
  }
}
