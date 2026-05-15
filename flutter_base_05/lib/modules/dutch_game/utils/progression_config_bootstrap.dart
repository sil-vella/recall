import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'progression_config_store.dart';

/// Persists declarative Dutch progression config from get-init-data / public init-config.
class ProgressionConfigBootstrap {
  ProgressionConfigBootstrap._();

  static const String prefRevisionKey = 'dutch_progression_config_revision';
  static const String prefDocKey = 'dutch_progression_config_doc_json';

  static Map<String, dynamic> _cachedDoc = <String, dynamic>{};

  static Future<void> hydrateFromPrefsBeforeStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefDocKey)?.trim();
      if (raw == null || raw.isEmpty) {
        _cachedDoc = <String, dynamic>{};
        ProgressionConfigStore.ensureBuiltinFallback();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cachedDoc = Map<String, dynamic>.from(decoded);
        ProgressionConfigStore.applyDocument(_cachedDoc);
      } else {
        _cachedDoc = <String, dynamic>{};
        ProgressionConfigStore.ensureBuiltinFallback();
      }
    } catch (_) {
      _cachedDoc = <String, dynamic>{};
      ProgressionConfigStore.ensureBuiltinFallback();
    }
  }

  static Future<String?> getStoredRevisionForApi() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getString(prefRevisionKey)?.trim();
    return (r != null && r.isNotEmpty) ? r : null;
  }

  static Future<void> mergeEnvelope(Map<String, dynamic> envelope) async {
    final prefs = await SharedPreferences.getInstance();
    final revision = envelope['progression_config_revision']?.toString().trim();
    final payload = envelope['progression_config'];

    if (payload is Map<String, dynamic>) {
      final typed = Map<String, dynamic>.from(payload);
      _cachedDoc = typed;
      ProgressionConfigStore.applyDocument(typed);
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
      ProgressionConfigStore.applyDocument(_cachedDoc);
    }
  }

  /// Alias for authenticated get-init-data responses.
  static Future<void> mergeStatsEnvelope(Map<String, dynamic> envelope) =>
      mergeEnvelope(envelope);

  /// Public init-config uses the same prefs keys.
  static Future<void> mergePublicConfigEnvelope(Map<String, dynamic> envelope) =>
      mergeEnvelope(envelope);
}
