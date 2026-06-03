import 'app_version_helper.dart';
import 'notification_inbox_merge.dart';
import '../../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';

/// `data.target_version` — show app-update style globals only while installed version is lower.
const String kGlobalBroadcastTargetVersionKey = 'target_version';

/// Instants with these [subtype] values only auto-show modals on home (`/`) or account (`/account`).
const Set<String> kInstantModalHomeOrAccountOnlySubtypes = {
  'lobby_special_event',
  'app_update',
  'customize_promo',
};

/// Normalizes a route path for host-screen checks (leading slash, no query).
String normalizeInstantModalRoutePath(String raw) {
  var t = raw.trim();
  final q = t.indexOf('?');
  if (q >= 0) {
    t = t.substring(0, q);
  }
  if (!t.startsWith('/')) {
    t = '/$t';
  }
  if (t.length > 1 && t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

/// True when [routePath] is the home or account screen (modal host for gated subtypes).
bool isInstantModalHostScreen(String? routePath) {
  if (routePath == null || routePath.trim().isEmpty) return false;
  final path = normalizeInstantModalRoutePath(routePath);
  return path == '/' || path == '/account';
}

bool isHomeOrAccountGatedInstantSubtype(String? subtype) {
  final s = subtype?.trim().toLowerCase();
  if (s == null || s.isEmpty) return false;
  return kInstantModalHomeOrAccountOnlySubtypes.contains(s);
}

/// Resolves subtype from explicit field, deeplink shape, or [msg_id] (API may omit subtype).
String? effectiveInstantModalSubtype(Map<String, dynamic> message) {
  final explicit = message['subtype']?.toString().trim();
  if (explicit != null && explicit.isNotEmpty) {
    return explicit.toLowerCase();
  }
  if (targetVersionFromMessage(message) != null) return 'app_update';
  final data = message['data'];
  if (data is Map) {
    final deeplink = data['deeplink'];
    if (deeplink is Map) {
      final path = normalizeInstantModalRoutePath(
        deeplink['path']?.toString() ?? '',
      );
      if (path == '/dutch-customize') return 'customize_promo';
      if (path == '/dutch/lobby' &&
          deeplink['event_id']?.toString().trim().isNotEmpty == true) {
        return 'lobby_special_event';
      }
    }
  }
  final msgId = message['msg_id']?.toString().toLowerCase() ?? '';
  if (msgId.contains('customize')) return 'customize_promo';
  if (msgId.contains('lobby_special') || msgId.contains('special_event')) {
    return 'lobby_special_event';
  }
  if (msgId.contains('app_update')) return 'app_update';
  return null;
}

/// Route gate for promo/update/lobby globals (welcome and other subtypes are not gated).
///
/// When [currentRoutePath] is omitted, the gate is not applied (callers that auto-show
/// modals must pass [NavigationManager.getCurrentRoute]).
bool shouldShowInstantModalOnCurrentRoute(
  Map<String, dynamic> message, {
  String? currentRoutePath,
}) {
  if (!isHomeOrAccountGatedInstantSubtype(effectiveInstantModalSubtype(message))) {
    return true;
  }
  final route = currentRoutePath?.trim();
  if (route == null || route.isEmpty) return true;
  return isInstantModalHostScreen(route);
}

/// Reads [kGlobalBroadcastTargetVersionKey] from message `data`.
String? targetVersionFromMessage(Map<String, dynamic> message) {
  final data = message['data'];
  if (data is! Map) return null;
  final v = data[kGlobalBroadcastTargetVersionKey]?.toString().trim();
  if (v == null || v.isEmpty) return null;
  return v;
}

/// App-update globals: modal visibility follows installed vs [target_version] only (not read state).
bool isVersionGatedInstantModal(Map<String, dynamic> message) {
  return targetVersionFromMessage(message) != null;
}

/// Whether a global [instant] row should be merged into the instant-modal inbox.
bool includeGlobalInInstantModalMerge(Map<String, dynamic> message) {
  final t = message['type']?.toString() ?? '';
  if (t != 'instant') return false;
  if (isVersionGatedInstantModal(message)) return true;
  return message['user_read'] != true;
}

/// True when an instant modal should still be shown.
///
/// Rows with [target_version] ignore read/unread; all other instants require unread.
bool shouldShowInstantModalMessage(
  Map<String, dynamic> message, {
  required String currentAppVersion,
  String? currentRoutePath,
}) {
  final versionGated = isVersionGatedInstantModal(message);

  if (!versionGated) {
    if (message['user_read'] == true || message['read'] == true) return false;
  }

  final type = message['type']?.toString() ?? '';
  if (type != 'instant' && type != 'instant_ws') return false;

  if (!versionGated && type != 'instant_ws') {
    final readAt = message['read_at'];
    if (readAt != null && readAt.toString().isNotEmpty) return false;
  }

  final target = targetVersionFromMessage(message);
  if (target != null) {
    if (compareSemanticVersions(currentAppVersion, target) >= 0) {
      return false;
    }
  }

  if (!shouldShowInstantModalOnCurrentRoute(message, currentRoutePath: currentRoutePath)) {
    return false;
  }

  return true;
}

String _versionGateReason(Map<String, dynamic> message, String currentAppVersion) {
  final target = targetVersionFromMessage(message);
  if (target == null) return '';
  if (compareSemanticVersions(currentAppVersion, target) >= 0) {
    return 'installed $currentAppVersion >= target $target';
  }
  return '';
}

/// Filters merged inbox rows before [InstantMessageModal.showUnreadInstantModals].
Future<List<Map<String, dynamic>>> filterInstantModalMessages(
  List<Map<String, dynamic>> messages, {
  String? currentAppVersion,
  String? currentRoutePath,
}) async {
  final version = currentAppVersion ?? await AppVersionHelper.resolve();
  final out = <Map<String, dynamic>>[];
  for (final m in messages) {
    final msgId = m['msg_id'] ?? m['id'];
    final target = targetVersionFromMessage(m);
    if (shouldShowInstantModalMessage(
      m,
      currentAppVersion: version,
      currentRoutePath: currentRoutePath,
    )) {
      out.add(m);
      if (LOGGING_SWITCH) {
        customlog(
          'InstantModalFilter: show $msgId'
          '${target != null ? ' (installed $version < target $target)' : ''}',
        );
      }
      continue;
    }
    if (LOGGING_SWITCH) {
      final gate = _versionGateReason(m, version);
      customlog(
        'InstantModalFilter: hide $msgId'
        '${target != null ? ' target=$target' : ''}'
        '${gate.isNotEmpty ? ' ($gate)' : ''}',
      );
    }
  }
  if (LOGGING_SWITCH) {
    customlog('InstantModalFilter: installed=$version in=${messages.length} show=${out.length}');
  }
  return out;
}

/// Dedupe key for session modal guard ([InstantMessageModal._shownIds]).
String instantModalSessionKey(Map<String, dynamic> message) {
  return notificationModalDedupeKey(message) ??
      'id:${message['id']?.toString() ?? 'ws_${message['timestamp'] ?? message.hashCode}'}';
}
