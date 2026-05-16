import 'package:flutter/foundation.dart';

/// In-memory achievements catalog from server JSON (hydrated from prefs / init).
class AchievementsCatalogStore {
  AchievementsCatalogStore._();

  static final ValueNotifier<int> changeVersion = ValueNotifier<int>(0);

  static final List<Map<String, String>> _entries = [];

  /// True after at least one successful apply from server or prefs.
  static bool _hasDocument = false;
  static bool get hasDocument => _hasDocument;

  static List<Map<String, String>> get rawEntries => List.unmodifiable(_entries);

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
        _entries.add({
          'id': id,
          'title': item['title']?.toString().trim() ?? id,
          'description': item['description']?.toString().trim() ?? '',
        });
      }
    }
    _hasDocument = _entries.isNotEmpty;
    changeVersion.value++;
  }

  static String displayTitle(String id) {
    if (id.isEmpty) return id;
    for (final e in _entries) {
      if (e['id'] == id) return e['title'] ?? id;
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
