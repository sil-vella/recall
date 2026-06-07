import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/managers/navigation_manager.dart';
import '../../modules/dutch_game/utils/customize_shop_route_hints.dart';
import '../../modules/notifications_module/utils/app_version_helper.dart';
import '../../modules/notifications_module/utils/global_broadcast_modal_filter.dart';
import '../../utils/consts/theme_consts.dart';
import '../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';

/// Reads [modal_background_enabled] (or legacy [modal_background_image]) from [message] `data`.
/// Also enabled when [modalBackgroundUrlFromMessage] resolves (URL or [kCustomizeModalImageItemIdKey]).
bool modalBackgroundEnabledFromMessage(Map<String, dynamic> message) {
  final data = message['data'];
  if (data is! Map) return false;
  final map = Map<String, dynamic>.from(data);
  final raw = map['modal_background_enabled'] ?? map['modal_background_image'];
  if (raw is bool) {
    return raw && modalBackgroundUrlFromMessage(message) != null;
  }
  if (raw is num) return raw != 0 && modalBackgroundUrlFromMessage(message) != null;
  final s = raw?.toString().toLowerCase().trim();
  if (s == 'false' || s == '0' || s == 'no') return false;
  if (s == 'true' || s == '1' || s == 'yes') {
    return modalBackgroundUrlFromMessage(message) != null;
  }
  return modalBackgroundUrlFromMessage(message) != null;
}

/// URL for modal banner image: explicit URL keys or [kCustomizeModalImageItemIdKey] shop preview.
String? modalBackgroundUrlFromMessage(Map<String, dynamic> message) {
  final data = message['data'];
  if (data is! Map) return null;
  final map = Map<String, dynamic>.from(data);
  final url = (map['modal_background_url'] ?? map['background_image_url'])?.toString().trim();
  if (url != null && url.isNotEmpty) return url;
  final itemId = map[kCustomizeModalImageItemIdKey]?.toString().trim();
  if (itemId == null || itemId.isEmpty) return null;
  final version = int.tryParse(map['modal_image_version']?.toString() ?? '') ?? 1;
  return consumableShopItemModalImageUrl(itemId, version: version);
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

  IconData get _headerIcon {
    final subtype = message['subtype']?.toString() ?? '';
    if (subtype == 'app_update') return Icons.system_update_alt;
    if (subtype == 'welcome') return Icons.celebration_outlined;
    return Icons.notifications_active_outlined;
  }

  void _onInstantModalClosed() {
    unawaited(_markReadOnce());
    onDismiss();
  }

  static final Set<String> _markedReadIds = {};

  Future<void> _markReadOnce() async {
    final id = message['id']?.toString() ?? '';
    if (id.isEmpty || onMarkAsRead == null || _markedReadIds.contains(id)) return;
    _markedReadIds.add(id);
    await onMarkAsRead!(id);
  }

  Future<void> _closeAfterMarkRead(BuildContext context) async {
    await _markReadOnce();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  bool _isPrimaryResponse(ResponseAction action) {
    final id = action.actionIdentifier.toLowerCase();
    const secondary = {'decline', 'close', 'dismiss', 'cancel', 'no', 'reject'};
    if (secondary.contains(id)) return false;
    const primary = {'join', 'accept', 'ok', 'yes', 'action', 'confirm'};
    if (primary.contains(id)) return true;
    return true;
  }

  Color _primaryBackgroundFor(ResponseAction action) {
    final id = action.actionIdentifier.toLowerCase();
    if (id == 'join') return AppColors.successColor;
    return AppColors.accentColor;
  }

  Widget _primaryActionButton({
    required ResponseAction action,
    required VoidCallback onPressed,
  }) {
    final bg = _primaryBackgroundFor(action);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: AppColors.textOnAccent,
        padding: AppPadding.cardPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.mediumRadius,
        ),
      ),
      child: Text(
        action.label,
        style: AppTextStyles.buttonText(color: AppColors.textOnAccent),
      ),
    );
  }

  Widget _secondaryActionButton({
    required ResponseAction action,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryColor,
        side: BorderSide(color: AppColors.accentColor, width: 1.5),
        padding: AppPadding.cardPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.mediumRadius,
        ),
      ),
      child: Text(
        action.label,
        style: AppTextStyles.buttonText(color: AppColors.primaryColor),
      ),
    );
  }

  Widget _responseButton({
    required ResponseAction action,
    required VoidCallback onPressed,
  }) {
    if (_isPrimaryResponse(action)) {
      return _primaryActionButton(action: action, onPressed: onPressed);
    }
    return _secondaryActionButton(action: action, onPressed: onPressed);
  }

  List<Widget> _buildResponseButtonRow(
    BuildContext context,
    List<ResponseAction> responses,
  ) {
    final secondary = <ResponseAction>[];
    final primary = <ResponseAction>[];
    for (final action in responses) {
      if (_isPrimaryResponse(action)) {
        primary.add(action);
      } else {
        secondary.add(action);
      }
    }
    final ordered = [...secondary, ...primary];

    if (ordered.length == 1) {
      return [
        SizedBox(
          width: double.infinity,
          child: _responseButton(
            action: ordered.first,
            onPressed: () => _onResponseTap(context, ordered.first),
          ),
        ),
      ];
    }

    if (ordered.length == 2) {
      return [
        Row(
          children: [
            Expanded(
              child: _responseButton(
                action: ordered[0],
                onPressed: () => _onResponseTap(context, ordered[0]),
              ),
            ),
            SizedBox(width: AppPadding.defaultPadding.left),
            Expanded(
              child: _responseButton(
                action: ordered[1],
                onPressed: () => _onResponseTap(context, ordered[1]),
              ),
            ),
          ],
        ),
      ];
    }

    return [
      Wrap(
        alignment: WrapAlignment.end,
        spacing: AppPadding.smallPadding.left,
        runSpacing: AppPadding.smallPadding.top,
        children: [
          for (final action in ordered)
            _responseButton(
              action: action,
              onPressed: () => _onResponseTap(context, action),
            ),
        ],
      ),
    ];
  }

  Widget _filledActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: AppColors.accentColor,
        foregroundColor: AppColors.textOnAccent,
        padding: AppPadding.cardPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.mediumRadius,
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.buttonText(color: AppColors.textOnAccent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responses = _responses;
    final hasResponseButtons = responses.isNotEmpty && onSendResponse != null;
    final showBg = _showBackdropImage;
    final bgUrl = _backdropImageUrl;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) return;
        _onInstantModalClosed();
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(
          horizontal: AppPadding.defaultPadding.horizontal,
          vertical: AppPadding.defaultPadding.vertical,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppBorderRadius.largeRadius,
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: AppOpacity.shadow),
                  blurRadius: AppSizes.shadowBlur,
                  offset: AppSizes.shadowOffset,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: AppBorderRadius.largeRadius,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: AppPadding.defaultPadding,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor,
                      borderRadius: AppBorderRadius.only(
                        topLeft: AppBorderRadius.large,
                        topRight: AppBorderRadius.large,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _headerIcon,
                          color: AppColors.textOnPrimary,
                          size: AppSizes.iconMedium,
                        ),
                        SizedBox(width: AppPadding.smallPadding.left),
                        Expanded(
                          child: Text(
                            _title,
                            style: AppTextStyles.headingSmall(
                              color: AppColors.textOnPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showBg && bgUrl != null)
                    SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: bgUrl,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 150),
                            errorWidget: (_, __, ___) => ColoredBox(
                              color: AppColors.cardVariant,
                            ),
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  AppColors.card.withValues(alpha: 0.92),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                    ),
                    child: SingleChildScrollView(
                      padding: AppPadding.defaultPadding,
                      child: Text(
                        _body,
                        style: AppTextStyles.bodyMedium(
                          color: AppColors.textOnCard,
                        ).copyWith(height: 1.5),
                      ),
                    ),
                  ),
                  Container(
                    padding: AppPadding.defaultPadding,
                    decoration: BoxDecoration(
                      color: AppColors.cardVariant,
                      borderRadius: AppBorderRadius.only(
                        bottomLeft: AppBorderRadius.large,
                        bottomRight: AppBorderRadius.large,
                      ),
                    ),
                    child: hasResponseButtons
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _buildResponseButtonRow(context, responses),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _filledActionButton(
                                label: dismissLabel,
                                onPressed: () => _closeAfterMarkRead(context),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
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
    if (LOGGING_SWITCH) {
      customlog(
        'createMatch: instantModal responseTap msg_id=${message['msg_id']} '
        'notificationId=$id action=${r.actionIdentifier}',
      );
    }
    final ok = await send(id, r.actionIdentifier);
    if (LOGGING_SWITCH) {
      customlog(
        'createMatch: instantModal responseTap done ok=$ok msg_id=${message['msg_id']}',
      );
    }
    if (context.mounted && ok) {
      await _closeAfterMarkRead(context);
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
      useRootNavigator: true,
      barrierColor: AppColors.black.withValues(alpha: AppOpacity.barrier),
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

  static Future<void> _modalShowChain = Future.value();

  static Future<void> showUnreadInstantModals(
    BuildContext context, {
    required List<Map<String, dynamic>> messages,
    required Future<void> Function(String messageId) onMarkAsRead,
    Future<bool> Function(String messageId, String actionIdentifier)? onSendResponse,
  }) {
    _modalShowChain = _modalShowChain.then(
      (_) => _showUnreadInstantModalsImpl(
        context,
        messages: messages,
        onMarkAsRead: onMarkAsRead,
        onSendResponse: onSendResponse,
      ),
    );
    return _modalShowChain;
  }

  static Future<void> _showUnreadInstantModalsImpl(
    BuildContext context, {
    required List<Map<String, dynamic>> messages,
    required Future<void> Function(String messageId) onMarkAsRead,
    Future<bool> Function(String messageId, String actionIdentifier)? onSendResponse,
  }) async {
    if (!context.mounted) return;
    final appVersion = await AppVersionHelper.resolve();
    final instantUnread = messages.where((m) {
      final type = m['type']?.toString() ?? '';
      final isInstant = type == kNotificationTypeInstant || type == kNotificationTypeInstantWs;
      if (!isInstant) return false;
      final idOrKey = instantModalSessionKey(m);
      return !_shownIds.contains(idOrKey);
    }).toList();
    for (final msg in instantUnread) {
      if (!context.mounted) break;
      final idOrKey = instantModalSessionKey(msg);
      if (_shownIds.contains(idOrKey)) continue;
      // Re-check route before each modal: queue may have been built on home, then user navigated (e.g. lobby CTA).
      if (!shouldShowInstantModalMessage(
        msg,
        currentAppVersion: appVersion,
        currentRoutePath: NavigationManager().getCurrentRoute(),
      )) {
        continue;
      }
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
