import 'package:flutter/material.dart';

import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';

/// Core notifications module. Fetches and caches messages via ConnectionsApiModule.
/// Used for app-wide instant modals and messages screen; feature modules create notifications on the backend.
class NotificationsModule extends ModuleBase {
  NotificationsModule()
      : super('notifications_module', dependencies: ['connections_api']);

  ConnectionsApiModule? _connectionsModule;

  static const String _stateKey = 'notifications';

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _connectionsModule = moduleManager.getModuleByType<ConnectionsApiModule>();
    StateManager().registerModuleState(_stateKey, {
      'messages': <Map<String, dynamic>>[],
      'unreadCount': 0,
      'lastFetchedAt': null,
    });
  }

  /// Fetch messages from the core notification API. Updates state on success.
  Future<List<Map<String, dynamic>>> fetchMessages({
    int? limit,
    int? offset,
    bool unreadOnly = true,
  }) async {
    if (_connectionsModule == null) return [];
    final limitVal = limit ?? 50;
    final offsetVal = offset ?? 0;
    final route =
        '/userauth/notifications/messages?limit=$limitVal&offset=$offsetVal&unread_only=$unreadOnly';
    try {
      final response = await _connectionsModule!.sendGetRequest(route);
      if (response is! Map) return [];
      if (response['success'] != true) return [];
      final data = response['data'];
      if (data is! List) return [];
      final list = data
          .map<Map<String, dynamic>>(
            (e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
          )
          .where((e) => e['id'] != null)
          .toList();
      StateManager().updateModuleState(_stateKey, {
        'messages': list,
        'lastFetchedAt': DateTime.now().toIso8601String(),
        'unreadCount': list.where((m) => m['read_at'] == null || m['read_at'] == '').length,
      });
      return list;
    } catch (e) {
      return [];
    }
  }

  /// Mark one or more messages as read.
  Future<bool> markAsRead(List<String> messageIds) async {
    if (_connectionsModule == null || messageIds.isEmpty) return false;
    final ids = messageIds.toSet();
    try {
      final response = await _connectionsModule!.sendPostRequest(
        '/userauth/notifications/mark-read',
        {'message_ids': messageIds},
      );
      if (response is! Map) return false;
      if (response['success'] != true) return false;
      final state = StateManager().getModuleState<Map<String, dynamic>>(_stateKey);
      final messages = state?['messages'];
      if (messages is List && messages.isNotEmpty) {
        final now = DateTime.now().toIso8601String();
        final updated = <Map<String, dynamic>>[];
        for (final e in messages) {
          final m = e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{};
          final id = m['id']?.toString();
          if (id != null && ids.contains(id)) {
            m['read'] = true;
            m['read_at'] = now;
          }
          updated.add(m);
        }
        final unreadCount = updated.where((m) {
          final r = m['read_at'];
          return r == null || r == '';
        }).length;
        StateManager().updateModuleState(_stateKey, {
          'messages': updated,
          'unreadCount': unreadCount,
        });
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  List<Map<String, dynamic>> get lastMessages {
    final state = StateManager().getModuleState<Map<String, dynamic>>(_stateKey);
    final messages = state?['messages'];
    if (messages is List) {
      return messages.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }
}
