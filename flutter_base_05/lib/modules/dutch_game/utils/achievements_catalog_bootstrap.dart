import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'achievements_catalog_store.dart';

/// Persists declarative Dutch achievements catalog from get-init-data / public init-config.
class AchievementsCatalogBootstrap {
  AchievementsCatalogBootstrap._();

  static const String prefRevisionKey = 'dutch_achievements_catalog_revision';
  static const String prefDocKey = 'dutch_achievements_catalog_doc_json';

  static Map<String, dynamic> _cachedDoc = <String, dynamic>{};

  static Future<void> hydrateFromPrefsBeforeStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefDocKey)?.trim();
      if (raw == null || raw.isEmpty) {
        _cachedDoc = <String, dynamic>{};
        AchievementsCatalogStore.ensureEmptyFallback();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cachedDoc = Map<String, dynamic>.from(decoded);
        AchievementsCatalogStore.applyDocument(_cachedDoc);
      } else {
        _cachedDoc = <String, dynamic>{};
        AchievementsCatalogStore.ensureEmptyFallback();
      }
    } catch (_) {
      _cachedDoc = <String, dynamic>{};
      AchievementsCatalogStore.ensureEmptyFallback();
    }
  }

  static Future<String?> getStoredRevisionForApi() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getString(prefRevisionKey)?.trim();
    return (r != null && r.isNotEmpty) ? r : null;
  }

  static Future<void> mergeEnvelope(Map<String, dynamic> envelope) async {
    final prefs = await SharedPreferences.getInstance();
    final revision = envelope['achievements_catalog_revision']?.toString().trim();
    final payload = envelope['achievements_catalog'];

    if (payload is Map<String, dynamic>) {
      final typed = Map<String, dynamic>.from(payload);
      _cachedDoc = typed;
      AchievementsCatalogStore.applyDocument(typed);
      await prefs.setString(prefDocKey, jsonEncode(typed));
      if (revision != null && revision.isNotEmpty) {
        await prefs.setString(prefRevisionKey, revision);
      }
      return;
    }

    if (revision != null && revision.isNotEmpty) {
      await prefs.setString(prefRevisionKey, revision);
    }
    if (_cachedDoc.isNotEmpty) {
      AchievementsCatalogStore.applyDocument(_cachedDoc);
    }
  }

  static Future<void> mergeStatsEnvelope(Map<String, dynamic> envelope) =>
      mergeEnvelope(envelope);

  static Future<void> mergePublicConfigEnvelope(Map<String, dynamic> envelope) =>
      mergeEnvelope(envelope);
}
