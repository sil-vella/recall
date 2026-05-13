import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:developer' as developer;

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

  /// Listeners notified immediately when a WS instant (e.g. rematch invite) is queued,
  /// so UI can show [InstantMessageModal] without waiting for the periodic poll.
  final List<VoidCallback> _pendingWsInstantListeners = [];

  /// Listeners for Dart [inbox_changed] (Python created a DB notification) — run inbox fetch + modals.
  final List<VoidCallback> _inboxRefreshListeners = [];

  void _notificationsDebug(String message, [Object? error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    if (error != null) {
      developer.log(message, name: 'NotificationsModule', error: error, stackTrace: stackTrace);
    } else {
      developer.log(message, name: 'NotificationsModule');
    }
  }

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _connectionsModule = moduleManager.getModuleByType<ConnectionsApiModule>();
    StateManager().registerModuleState(_stateKey, {
      'messages': <Map<String, dynamic>>[],
      'unreadCount': 0,
      'lastFetchedAt': null,
      'pendingWsInstants': <Map<String, dynamic>>[],
      'globalBroadcasts': <Map<String, dynamic>>[],
    });
  }

  void addPendingWsInstantListener(VoidCallback listener) {
    if (!_pendingWsInstantListeners.contains(listener)) {
      _pendingWsInstantListeners.add(listener);
    }
  }

  void removePendingWsInstantListener(VoidCallback listener) {
    _pendingWsInstantListeners.remove(listener);
  }

  void addInboxRefreshListener(VoidCallback listener) {
    if (!_inboxRefreshListeners.contains(listener)) {
      _inboxRefreshListeners.add(listener);
    }
  }

  void removeInboxRefreshListener(VoidCallback listener) {
    _inboxRefreshListeners.remove(listener);
  }

  /// Called when WebSocket receives [inbox_changed] from Dart (after Python notify).
  void notifyInboxRefreshRequested() {
    for (final l in List<VoidCallback>.from(_inboxRefreshListeners)) {
      l();
    }
  }

  void _notifyPendingWsInstantAdded() {
    for (final l in List<VoidCallback>.from(_pendingWsInstantListeners)) {
      l();
    }
  }

  /// Appends a payload from ws_instant_notification (Dart backend) to be shown on next check.
  void addPendingWsInstant(Map<String, dynamic> payload) {
    final state = StateManager().getModuleState<Map<String, dynamic>>(_stateKey);
    final pending = List<Map<String, dynamic>>.from(
      state?['pendingWsInstants'] is List ? (state!['pendingWsInstants'] as List).cast<Map<String, dynamic>>() : [],
    );
    final message = Map<String, dynamic>.from(payload);
    message['type'] = 'instant_ws';
    pending.add(message);
    StateManager().updateModuleState(_stateKey, {'pendingWsInstants': pending});
    _notifyPendingWsInstantAdded();
  }

  /// Takes and clears pending WS instant notifications so they can be shown once.
  List<Map<String, dynamic>> takePendingWsInstants() {
    final state = StateManager().getModuleState<Map<String, dynamic>>(_stateKey);
    final pending = state?['pendingWsInstants'];
    final list = pending is List
        ? List<Map<String, dynamic>>.from(pending.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e is Map ? e : {})))
        : <Map<String, dynamic>>[];
    StateManager().updateModuleState(_stateKey, {'pendingWsInstants': <Map<String, dynamic>>[]});
    return list;
  }

  /// Replaces global broadcast rows from `get-user-stats` (`global_broadcast_messages`).
  void applyGlobalBroadcastsFromStats(List<Map<String, dynamic>> items) {
    _notificationsDebug('applyGlobalBroadcastsFromStats: count=${items.length}');
    StateManager().updateModuleState(_stateKey, {
      'globalBroadcasts': items.map((e) => Map<String, dynamic>.from(e)).toList(),
    });
  }

  List<Map<String, dynamic>> get globalBroadcasts {
    final state = StateManager().getModuleState<Map<String, dynamic>>(_stateKey);
    final raw = state?['globalBroadcasts'];
    if (raw is! List) return [];
    return raw.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Mark global broadcast(s) read (separate from per-user [markAsRead]).
  Future<bool> markGlobalBroadcastsRead(List<String> ids) async {
    if (_connectionsModule == null || ids.isEmpty) return false;
    try {
      final response = await _connectionsModule!.sendPostRequest(
        '/userauth/notifications/global-mark-read',
        {'global_message_ids': ids},
      );
      if (response is! Map || response['success'] != true) return false;
      final state = StateManager().getModuleState<Map<String, dynamic>>(_stateKey);
      final gb = state?['globalBroadcasts'];
      if (gb is List) {
        final now = DateTime.now().toIso8601String();
        final idSet = ids.toSet();
        final updated = gb.map((e) {
          if (e is! Map) return <String, dynamic>{};
          final m = Map<String, dynamic>.from(e);
          final id = m['id']?.toString() ?? '';
          if (idSet.contains(id)) {
            m['user_read'] = true;
            m['read'] = true;
            m['read_at'] = now;
          }
          return m;
        }).toList();
        StateManager().updateModuleState(_stateKey, {'globalBroadcasts': updated});
      }
      return true;
    } catch (e, st) {
      _notificationsDebug('markGlobalBroadcastsRead failed', e, st);
      return false;
    }
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
      if (response is! Map) {
        _notificationsDebug('fetchMessages: non-Map response type=${response.runtimeType}');
        return [];
      }
      if (response['success'] != true) {
        _notificationsDebug(
          'fetchMessages: success!=true keys=${response.keys.toList()} message=${response['message'] ?? response['error']}',
        );
        return [];
      }
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
    } catch (e, st) {
      _notificationsDebug('fetchMessages failed route=$route', e, st);
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
    } catch (e, st) {
      _notificationsDebug('markAsRead failed', e, st);
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
