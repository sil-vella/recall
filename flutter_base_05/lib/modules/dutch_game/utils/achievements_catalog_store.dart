import 'package:flutter/foundation.dart';

/// In-memory achievements catalog from server JSON (hydrated from prefs / init).
class AchievementsCatalogStore {
  AchievementsCatalogStore._();

  static final ValueNotifier<int> changeVersion = ValueNotifier<int>(0);

  static final List<Map<String, dynamic>> _entries = [];

  /// True after at least one successful apply from server or prefs.
  static bool _hasDocument = false;
  static bool get hasDocument => _hasDocument;

  static List<Map<String, dynamic>> get rawEntries =>
      List<Map<String, dynamic>>.unmodifiable(_entries);

  static void ensureEmptyFallback() {
    _entries.clear();
    _hasDocument = false;
    changeVersion.value++;
  }

  /// Parse declarative document: `{ "schema_version", "achievements": [ { id, title, description, unlock } ] }`.
  static void applyDocument(Map<String, dynamic> doc) {
    _entries.clear();
    final raw = doc['achievements'];
    if (raw is List) {
      final seen = <String>{};
      for (final item in raw) {
        if (item is! Map) continue;
        final id = item['id']?.toString().trim() ?? '';
        if (id.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        final unlockRaw = item['unlock'];
        final unlock = unlockRaw is Map
            ? Map<String, dynamic>.from(
                unlockRaw.map((k, v) => MapEntry(k.toString(), v)),
              )
            : null;
        _entries.add({
          'id': id,
          'title': item['title']?.toString().trim() ?? id,
          'description': item['description']?.toString().trim() ?? '',
          if (unlock != null && unlock.isNotEmpty) 'unlock': unlock,
        });
      }
    }
    _hasDocument = _entries.isNotEmpty;
    changeVersion.value++;
  }

  static String displayTitle(String id) {
    if (id.isEmpty) return id;
    for (final e in _entries) {
      if (e['id']?.toString() == id) {
        return e['title']?.toString() ?? id;
      }
    }
    return _humanizeId(id);
  }

  static String _humanizeId(String id) {
    return id
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }
}
