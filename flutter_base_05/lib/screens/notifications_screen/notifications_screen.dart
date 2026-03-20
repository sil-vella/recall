import 'package:flutter/material.dart';
import '../../core/00_base/screen_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/widgets/instant_message_modal.dart';
import '../../core/widgets/instant_notification_response.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../modules/notifications_module/notifications_module.dart';
import '../../utils/consts/theme_consts.dart';

/// Screen that lists all notifications for the current user (read and unread).
/// Uses [BaseScreen] and [NotificationsModule] to fetch and display messages.
class NotificationsScreen extends BaseScreen {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<NotificationsScreen> createState() => _NotificationsScreenState();

  @override
  String computeTitle(BuildContext context) => 'Notifications';
}

class _NotificationsScreenState extends BaseScreenState<NotificationsScreen> {
  final ModuleManager _moduleManager = ModuleManager();
  NotificationsModule? _notificationsModule;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _messages = [];
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _notificationsModule = _moduleManager.getModuleByType<NotificationsModule>();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (_notificationsModule == null) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Notifications not available';
        _messages = [];
      });
      return;
    }
    if (mounted) setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _notificationsModule!.fetchMessages(
        limit: _pageSize,
        offset: 0,
        unreadOnly: false,
      );
      if (mounted) {
        setState(() {
          _messages = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load notifications';
          _messages = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _markAsRead(String messageId) async {
    if (_notificationsModule == null) return;
    final ok = await _notificationsModule!.markAsRead([messageId]);
    if (ok && mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m['id']?.toString() == messageId);
        if (idx >= 0) {
          _messages = List<Map<String, dynamic>>.from(_messages);
          _messages[idx] = Map<String, dynamic>.from(_messages[idx])
            ..['read'] = true
            ..['read_at'] = DateTime.now().toIso8601String();
        }
      });
    }
  }

  /// Local list only — server already marked read (e.g. after [submitInstantNotificationResponse]).
  void _syncReadInList(String messageId) {
    if (messageId.isEmpty || !mounted) return;
    setState(() {
      final idx = _messages.indexWhere((m) => m['id']?.toString() == messageId);
      if (idx >= 0) {
        _messages = List<Map<String, dynamic>>.from(_messages);
        _messages[idx] = Map<String, dynamic>.from(_messages[idx])
          ..['read'] = true
          ..['read_at'] = DateTime.now().toIso8601String();
      }
    });
  }

  /// Same [InstantMessageModal] as app-wide instant flow: full title/body/responses and Join actions.
  Future<void> _openNotificationInModal(Map<String, dynamic> raw) async {
    final message = Map<String, dynamic>.from(raw);
    final id = message['id']?.toString() ?? '';
    if (!mounted) return;
    final api = _moduleManager.getModuleByType<ConnectionsApiModule>();
    await InstantMessageModal.show(
      context,
      message: message,
      onDismiss: () {},
      dismissLabel: 'Close',
      onSendResponse: api == null
          ? null
          : (String messageId, String actionIdentifier) async {
              final ok = await submitInstantNotificationResponse(
                api: api,
                mod: _notificationsModule,
                messageId: messageId,
                actionIdentifier: actionIdentifier,
                context: context,
                messageRow: message,
              );
              if (ok && mounted) _syncReadInList(messageId);
              return ok;
            },
      onMarkAsRead: id.isEmpty ? null : (mid) => _markAsRead(mid),
    );
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    if (value is String) {
      try {
        final d = DateTime.tryParse(value);
        if (d != null) {
          final now = DateTime.now();
          if (d.year == now.year && d.month == now.month && d.day == now.day) {
            return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
          }
          return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
        }
      } catch (_) {}
      return value;
    }
    return value.toString();
  }

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return buildLoadingIndicator();
    }
    if (_error != null) {
      return buildErrorView(_error!);
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: AppColors.lightGray),
            SizedBox(height: AppPadding.defaultPadding.top),
            Text(
              'No notifications yet',
              style: AppTextStyles.bodyLarge().copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMessages,
      color: AppColors.accentColor,
      child: ListView.builder(
        padding: EdgeInsets.only(
          left: AppPadding.defaultPadding.left,
          right: AppPadding.defaultPadding.right,
          top: AppPadding.smallPadding.top,
          bottom: MediaQuery.of(context).padding.bottom + AppPadding.defaultPadding.bottom,
        ),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final m = _messages[index];
          final title = m['title']?.toString().trim() ?? 'Notification';
          final body = m['body']?.toString().trim() ?? '';
          final read = m['read'] == true || (m['read_at']?.toString().trim().isNotEmpty == true);
          final createdAt = m['created_at'];
          final subtype = m['subtype']?.toString() ?? '';

          return Card(
            margin: EdgeInsets.symmetric(
              horizontal: AppPadding.smallPadding.left,
              vertical: AppPadding.smallPadding.top / 2,
            ),
            color: read ? AppColors.surface : AppColors.surface.withValues(alpha: 0.95),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: AppBorderRadius.smallRadius,
              side: BorderSide(
                color: read ? AppColors.borderDefault : AppColors.accentColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: InkWell(
              onTap: () => _openNotificationInModal(m),
              borderRadius: AppBorderRadius.smallRadius,
              child: Padding(
                padding: AppPadding.cardPadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      read ? Icons.notifications_none : Icons.notifications,
                      size: AppSizes.iconMedium,
                      color: read ? AppColors.lightGray : AppColors.accentColor,
                    ),
                    SizedBox(width: AppPadding.mediumPadding.left),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTextStyles.bodyLarge().copyWith(
                              fontWeight: read ? FontWeight.normal : FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (subtype.isNotEmpty)
                            Text(
                              subtype,
                              style: AppTextStyles.bodySmall().copyWith(color: AppColors.textSecondary),
                            ),
                          if (body.isNotEmpty) ...[
                            SizedBox(height: AppPadding.smallPadding.top / 2),
                            Text(
                              body.length > 120 ? '${body.substring(0, 120)}...' : body,
                              style: AppTextStyles.bodyMedium().copyWith(color: AppColors.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          SizedBox(height: AppPadding.smallPadding.top / 2),
                          Text(
                            _formatDate(createdAt),
                            style: AppTextStyles.bodySmall().copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
