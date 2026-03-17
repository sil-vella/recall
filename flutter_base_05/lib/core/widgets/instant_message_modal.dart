import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/consts/theme_consts.dart';

/// Notification type that must be shown as a modal immediately, app-wide (from DB/polling).
const String kNotificationTypeInstant = 'instant';

/// Notification type pushed via WebSocket from Dart backend (event: ws_instant_notification).
const String kNotificationTypeInstantWs = 'instant_ws';

/// Frontend-only instant: predefined structure, no backend; responses: required 'Close', optional 'action'.
const String kNotificationTypeInstantFrontendOnly = 'instant_frontend_only';

/// Server-defined response action: label and action_identifier. Client calls single core endpoint with message_id + action_identifier.
class ResponseAction {
  const ResponseAction({
    required this.label,
    required this.actionIdentifier,
  });
  final String label;
  final String actionIdentifier;
  static List<ResponseAction> fromMessage(Map<String, dynamic> message) {
    final list = message['responses'];
    if (list is! List || list.isEmpty) return [];
    final out = <ResponseAction>[];
    for (final e in list) {
      if (e is! Map) continue;
      final label = e['label']?.toString().trim();
      final actionId = (e['action_identifier'] ?? e['action'])?.toString().trim().toLowerCase();
      if (label != null && label.isNotEmpty && actionId != null && actionId.isNotEmpty) {
        out.add(ResponseAction(label: label, actionIdentifier: actionId));
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
  /// Single core endpoint: called with messageId and actionIdentifier. Returns true if success.
  final Future<bool> Function(String messageId, String actionIdentifier)? onSendResponse;
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
        shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.mediumRadius),
        titlePadding: EdgeInsets.fromLTRB(
          AppPadding.cardPadding.horizontal,
          AppPadding.cardPadding.vertical,
          AppPadding.cardPadding.horizontal,
          AppPadding.smallPadding.top,
        ),
        contentPadding: EdgeInsets.fromLTRB(
          AppPadding.cardPadding.horizontal,
          AppPadding.smallPadding.top,
          AppPadding.cardPadding.horizontal,
          AppPadding.cardPadding.vertical,
        ),
        actionsPadding: EdgeInsets.only(
          right: AppPadding.cardPadding.horizontal,
          bottom: AppPadding.smallPadding.bottom,
          left: AppPadding.smallPadding.left,
        ),
        title: Text(
          _title,
          style: AppTextStyles.headingSmall(color: AppColors.textOnSurface),
        ),
        content: SingleChildScrollView(
          child: Text(
            _body,
            style: AppTextStyles.bodyMedium(color: AppColors.textOnSurface),
          ),
        ),
        actions: hasResponseButtons
            ? responses.map((r) {
                return TextButton(
                  onPressed: () => _onResponseTap(context, r),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primaryColor),
                  child: Text(
                    r.label,
                    style: AppTextStyles.bodyMedium(color: AppColors.primaryColor),
                  ),
                );
              }).toList()
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primaryColor),
                  child: Text(
                    dismissLabel,
                    style: AppTextStyles.bodyMedium(color: AppColors.primaryColor),
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
    final ok = await send(id, r.actionIdentifier);
    if (context.mounted && ok) {
      Navigator.of(context).pop();
    }
  }

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> message,
    required VoidCallback onDismiss,
    String dismissLabel = 'OK',
    Future<bool> Function(String messageId, String actionIdentifier)? onSendResponse,
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

  /// Shows a frontend-only instant modal (no backend). Predefined structure: title, body, data, responses.
  /// [responses] defaults to required 'Close'; pass optional [actionLabel] and [actionIdentifier] for an extra button.
  /// [onAction] is called when the optional action button is pressed (if provided).
  static Future<void> showFrontendOnlyInstant(
    BuildContext context, {
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String actionLabel = 'Action',
    String actionIdentifier = 'action',
    VoidCallback? onAction,
  }) {
    final responses = <Map<String, dynamic>>[
      {'label': 'Close', 'action_identifier': 'close'},
      if (onAction != null) {'label': actionLabel, 'action_identifier': actionIdentifier},
    ];
    final message = <String, dynamic>{
      'type': kNotificationTypeInstantFrontendOnly,
      'title': title,
      'body': body,
      'data': data ?? <String, dynamic>{},
      'responses': responses,
      'id': 'frontend_${DateTime.now().millisecondsSinceEpoch}',
    };
    return show(
      context,
      message: message,
      onDismiss: () {},
      dismissLabel: 'Close',
      onSendResponse: (String id, String actionId) async {
        if (actionId == actionIdentifier) {
          onAction?.call();
        }
        return true; // always close modal on any button
      },
      onMarkAsRead: null,
    );
  }

  static Future<void> showUnreadInstantModals(
    BuildContext context, {
    required List<Map<String, dynamic>> messages,
    required Future<void> Function(String messageId) onMarkAsRead,
    Future<bool> Function(String messageId, String actionIdentifier)? onSendResponse,
  }) async {
    if (!context.mounted) return;
    final instantUnread = messages.where((m) {
      final id = m['id']?.toString() ?? '';
      final type = m['type']?.toString() ?? '';
      final readAt = m['read_at'];
      final isUnread = type == kNotificationTypeInstantWs || (readAt == null || readAt == '');
      final isInstant = type == kNotificationTypeInstant || type == kNotificationTypeInstantWs;
      final idOrKey = id.isNotEmpty ? id : 'ws_${m['timestamp'] ?? m.hashCode}';
      return isInstant && isUnread && !_shownIds.contains(idOrKey);
    }).toList();
    for (final msg in instantUnread) {
      if (!context.mounted) break;
      final id = msg['id']?.toString() ?? '';
      final idOrKey = id.isNotEmpty ? id : 'ws_${msg['timestamp'] ?? msg.hashCode}';
      _shownIds.add(idOrKey);
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
