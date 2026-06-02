import 'app_version_helper.dart';
import 'notification_inbox_merge.dart';

/// `data.target_version` — show app-update style globals only while installed version is lower.
const String kGlobalBroadcastTargetVersionKey = 'target_version';

/// Reads [kGlobalBroadcastTargetVersionKey] from message `data`.
String? targetVersionFromMessage(Map<String, dynamic> message) {
  final data = message['data'];
  if (data is! Map) return null;
  final v = data[kGlobalBroadcastTargetVersionKey]?.toString().trim();
  if (v == null || v.isEmpty) return null;
  return v;
}

/// True when an instant modal should still be shown (read flags + optional version gate).
bool shouldShowInstantModalMessage(
  Map<String, dynamic> message, {
  required String currentAppVersion,
}) {
  if (message['user_read'] == true || message['read'] == true) return false;

  final type = message['type']?.toString() ?? '';
  if (type != 'instant' && type != 'instant_ws') return false;

  if (type != 'instant_ws') {
    final readAt = message['read_at'];
    if (readAt != null && readAt.toString().isNotEmpty) return false;
  }

  final target = targetVersionFromMessage(message);
  if (target != null) {
    if (compareSemanticVersions(currentAppVersion, target) >= 0) {
      return false;
    }
  }

  return true;
}

/// Filters merged inbox rows before [InstantMessageModal.showUnreadInstantModals].
Future<List<Map<String, dynamic>>> filterInstantModalMessages(
  List<Map<String, dynamic>> messages, {
  String? currentAppVersion,
}) async {
  final version = currentAppVersion ?? await AppVersionHelper.resolve();
  return messages
      .where((m) => shouldShowInstantModalMessage(m, currentAppVersion: version))
      .toList();
}

/// Dedupe key for session modal guard ([InstantMessageModal._shownIds]).
String instantModalSessionKey(Map<String, dynamic> message) {
  return notificationModalDedupeKey(message) ??
      'id:${message['id']?.toString() ?? 'ws_${message['timestamp'] ?? message.hashCode}'}';
}
