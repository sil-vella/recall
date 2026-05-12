import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/consts/theme_consts.dart';

/// Reads [modal_background_enabled] (or legacy [modal_background_image]) from [message] `data`.
/// Default is off unless explicitly true and a URL is present (see [modalBackgroundUrlFromMessage]).
bool modalBackgroundEnabledFromMessage(Map<String, dynamic> message) {
  final data = message['data'];
  if (data is! Map) return false;
  final map = Map<String, dynamic>.from(data);
  final raw = map['modal_background_enabled'] ?? map['modal_background_image'];
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final s = raw?.toString().toLowerCase().trim();
  return s == 'true' || s == '1' || s == 'yes';
}

/// URL for modal backdrop image; from [message] `data` keys [modal_background_url] or [background_image_url].
String? modalBackgroundUrlFromMessage(Map<String, dynamic> message) {
  final data = message['data'];
  if (data is! Map) return null;
  final map = Map<String, dynamic>.from(data);
  final url = (map['modal_background_url'] ?? map['background_image_url'])?.toString().trim();
  if (url == null || url.isEmpty) return null;
  return url;
}

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
    this.useModalBackgroundImage,
    this.modalBackgroundImageUrl,
  }) : super(key: key);

  final Map<String, dynamic> message;
  final VoidCallback onDismiss;
  final String dismissLabel;
  /// Single core endpoint: called with messageId and actionIdentifier. Returns true if success.
  final Future<bool> Function(String messageId, String actionIdentifier)? onSendResponse;
  final Future<void> Function(String messageId)? onMarkAsRead;
  /// When non-null, overrides [modalBackgroundEnabledFromMessage]. When false, never shows backdrop image.
  final bool? useModalBackgroundImage;
  /// When non-null and non-empty, used as image URL; otherwise URL is read from [message] `data`.
  final String? modalBackgroundImageUrl;

  bool get _showBackdropImage {
    final urlFromMessage = modalBackgroundUrlFromMessage(message);
    final explicitUrl = modalBackgroundImageUrl?.trim();
    final url = (explicitUrl != null && explicitUrl.isNotEmpty) ? explicitUrl : urlFromMessage;
    if (url == null || url.isEmpty) return false;
    if (useModalBackgroundImage == false) return false;
    if (useModalBackgroundImage == true) return true;
    return modalBackgroundEnabledFromMessage(message);
  }

  String? get _backdropImageUrl {
    final explicitUrl = modalBackgroundImageUrl?.trim();
    if (explicitUrl != null && explicitUrl.isNotEmpty) return explicitUrl;
    return modalBackgroundUrlFromMessage(message);
  }

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
    final showBg = _showBackdropImage;
    final bgUrl = _backdropImageUrl;
    final contentLayerColor =
        showBg ? AppColors.surface.withValues(alpha: 0.9) : AppColors.surface;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) return;
        _onInstantModalClosed();
      },
      child: AlertDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        contentPadding: EdgeInsets.zero,
        insetPadding: EdgeInsets.symmetric(
          horizontal: AppPadding.defaultPadding.horizontal,
          vertical: AppPadding.defaultPadding.vertical,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ClipRRect(
            borderRadius: AppBorderRadius.mediumRadius,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (showBg && bgUrl != null)
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: bgUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      errorWidget: (_, __, ___) => ColoredBox(color: AppColors.surface),
                    ),
                  ),
                Material(
                  color: contentLayerColor,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppPadding.cardPadding.horizontal,
                      AppPadding.cardPadding.vertical,
                      AppPadding.cardPadding.horizontal,
                      AppPadding.smallPadding.top,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _title,
                          style: AppTextStyles.headingSmall(color: AppColors.textOnSurface),
                        ),
                        SizedBox(height: AppPadding.smallPadding.top),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              _body,
                              style: AppTextStyles.bodyMedium(color: AppColors.textOnSurface),
                            ),
                          ),
                        ),
                        SizedBox(height: AppPadding.cardPadding.vertical),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: AppPadding.smallPadding.left,
                            children: hasResponseButtons
                                ? responses
                                    .map((r) {
                                      return TextButton(
                                        onPressed: () => _onResponseTap(context, r),
                                        style: TextButton.styleFrom(foregroundColor: AppColors.primaryColor),
                                        child: Text(
                                          r.label,
                                          style: AppTextStyles.bodyMedium(color: AppColors.primaryColor),
                                        ),
                                      );
                                    })
                                    .toList()
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
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    bool? useModalBackgroundImage,
    String? modalBackgroundImageUrl,
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
        useModalBackgroundImage: useModalBackgroundImage,
        modalBackgroundImageUrl: modalBackgroundImageUrl,
      ),
    );
  }

  static final Set<String> _shownIds = {};

  /// Shows a frontend-only instant modal (no backend). Predefined structure: title, body, data, responses.
  /// [responses] defaults to required 'Close'; pass optional [actionLabel] and [actionIdentifier] for an extra button.
  /// [onAction] is called when the optional action button is pressed (if provided).
  ///
  /// Optional backdrop: set [modalBackgroundEnabled] to true and pass [modalBackgroundUrl] (merged into [data]
  /// as `modal_background_enabled` / `modal_background_url` for the shared modal layout).
  static Future<void> showFrontendOnlyInstant(
    BuildContext context, {
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String actionLabel = 'Action',
    String actionIdentifier = 'action',
    VoidCallback? onAction,
    bool modalBackgroundEnabled = false,
    String? modalBackgroundUrl,
  }) {
    final merged = Map<String, dynamic>.from(data ?? {});
    if (modalBackgroundEnabled &&
        modalBackgroundUrl != null &&
        modalBackgroundUrl.trim().isNotEmpty) {
      merged['modal_background_enabled'] = true;
      merged['modal_background_url'] = modalBackgroundUrl.trim();
    }
    final responses = <Map<String, dynamic>>[
      {'label': 'Close', 'action_identifier': 'close'},
      if (onAction != null) {'label': actionLabel, 'action_identifier': actionIdentifier},
    ];
    final message = <String, dynamic>{
      'type': kNotificationTypeInstantFrontendOnly,
      'title': title,
      'body': body,
      'data': merged,
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
