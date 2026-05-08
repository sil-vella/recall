import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists declarative Dutch consumables catalog from `get-user-stats`.
///
/// Efficient path mirrors table tiers:
/// - send `client_consumables_catalog_revision`
/// - backend returns full `consumables_catalog` only when stale/missing
class ConsumablesCatalogBootstrap {
  ConsumablesCatalogBootstrap._();

  static const String prefRevisionKey = 'dutch_consumables_catalog_revision';
  static const String prefDocKey = 'dutch_consumables_catalog_doc_json';

  static Map<String, dynamic> _cachedDoc = <String, dynamic>{};

  static Future<void> hydrateFromPrefsBeforeStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefDocKey)?.trim();
      if (raw == null || raw.isEmpty) {
        _cachedDoc = <String, dynamic>{};
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cachedDoc = Map<String, dynamic>.from(decoded);
      } else {
        _cachedDoc = <String, dynamic>{};
      }
    } catch (_) {
      _cachedDoc = <String, dynamic>{};
    }
  }

  static Future<String?> getStoredRevisionForApi() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getString(prefRevisionKey)?.trim();
    return (r != null && r.isNotEmpty) ? r : null;
  }

  /// Merge top-level `get-user-stats` response.
  static Future<void> mergeStatsEnvelope(Map<String, dynamic> envelope) async {
    final prefs = await SharedPreferences.getInstance();
    final revision = envelope['consumables_catalog_revision']?.toString().trim();
    final payload = envelope['consumables_catalog'];

    if (payload is Map<String, dynamic>) {
      final typed = Map<String, dynamic>.from(payload);
      _cachedDoc = typed;
      await prefs.setString(prefDocKey, jsonEncode(typed));
      if (revision != null && revision.isNotEmpty) {
        await prefs.setString(prefRevisionKey, revision);
      }
      return;
    }

    if (revision != null && revision.isNotEmpty) {
      await prefs.setString(prefRevisionKey, revision);
    }
  }

  /// Allows fallback caching from `/get-shop-catalog` response.
  static Future<void> mergeCatalogItems({
    required List<Map<String, dynamic>> items,
    String? revision,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final doc = <String, dynamic>{
      'schema_version': 1,
      'items': items,
    };
    _cachedDoc = doc;
    await prefs.setString(prefDocKey, jsonEncode(doc));
    final rev = (revision ?? '').trim();
    if (rev.isNotEmpty) {
      await prefs.setString(prefRevisionKey, rev);
    }
  }

  static List<Map<String, dynamic>> getCachedItems() {
    final raw = _cachedDoc['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Map<String, dynamic>? getCachedItemById(String itemId) {
    final id = itemId.trim();
    if (id.isEmpty) return null;
    for (final item in getCachedItems()) {
      if (item['item_id']?.toString().trim() == id) {
        return item;
      }
    }
    return null;
  }

  static Map<String, dynamic> getStyleForItem(String itemId) {
    final item = getCachedItemById(itemId);
    final style = item?['style'];
    if (style is Map) return Map<String, dynamic>.from(style);
    return const <String, dynamic>{};
  }
}
