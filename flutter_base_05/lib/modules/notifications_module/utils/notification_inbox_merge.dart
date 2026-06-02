/// Dedupe notification rows for instant modals (globals + per-user API).
///
/// Same [msg_id] from a global broadcast and a per-user inbox row must only modal once.
/// Prefer the first occurrence (callers should pass globals before API messages).

String? notificationModalDedupeKey(Map<String, dynamic> message) {
  final msgId = message['msg_id']?.toString().trim();
  if (msgId != null && msgId.isNotEmpty) return 'msg_id:$msgId';
  final globalId = message['global_id']?.toString().trim();
  if (globalId != null && globalId.isNotEmpty) return 'global_id:$globalId';
  final id = message['id']?.toString().trim();
  if (id != null && id.isNotEmpty) return 'id:$id';
  return null;
}

/// Removes duplicate keys; rows without a key are kept (e.g. ephemeral WS instants).
List<Map<String, dynamic>> dedupeNotificationMessages(
  Iterable<Map<String, dynamic>> messages,
) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final raw in messages) {
    final m = Map<String, dynamic>.from(raw);
    final key = notificationModalDedupeKey(m);
    if (key != null && !seen.add(key)) continue;
    out.add(m);
  }
  return out;
}

/// Unread global [instant] rows first, then API list, with [msg_id] dedupe (globals win).
List<Map<String, dynamic>> mergeGlobalAndApiInstantInbox({
  required List<Map<String, dynamic>> globalUnreadInstant,
  required List<Map<String, dynamic>> apiList,
}) {
  return dedupeNotificationMessages([
    ...globalUnreadInstant,
    ...apiList,
  ]);
}
