import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/dev_logger.dart';
import '../backend_core/utils/gameplay_profiles_store.dart';

const bool LOGGING_SWITCH = true;

/// Persists declarative gameplay profiles from init-data for lobby UI labels.
class GameplayProfilesBootstrap {
  GameplayProfilesBootstrap._();

  static const String prefRevisionKey = 'dutch_gameplay_profiles_revision';
  static const String prefDocKey = 'dutch_gameplay_profiles_doc_json';

  static Future<void> hydrateFromPrefsBeforeStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefDocKey)?.trim();
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        GameplayProfilesStore.applyDocument(Map<String, dynamic>.from(decoded));
        if (LOGGING_SWITCH) {
          final profiles = decoded['profiles'];
          final count = profiles is Map ? profiles.length : 0;
          customlog(
            'GameplayProfilesBootstrap.hydrateFromPrefsBeforeStats: '
            'profile_count=$count',
          );
        }
      }
    } catch (_) {}
  }

  static Future<String?> getStoredRevisionForApi() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getString(prefRevisionKey)?.trim();
    return (r != null && r.isNotEmpty) ? r : null;
  }

  static Future<void> mergeStatsEnvelope(Map<String, dynamic> envelope) async {
    final prefs = await SharedPreferences.getInstance();
    final revision = envelope['gameplay_profiles_revision']?.toString().trim();
    final payload = envelope['gameplay_profiles'];
    if (payload is Map<String, dynamic>) {
      final typed = Map<String, dynamic>.from(payload);
      GameplayProfilesStore.applyDocument(
        typed,
        revision: revision,
      );
      await prefs.setString(prefDocKey, jsonEncode(typed));
      if (revision != null && revision.isNotEmpty) {
        await prefs.setString(prefRevisionKey, revision);
      }
      if (LOGGING_SWITCH) {
        final profiles = typed['profiles'];
        final count = profiles is Map ? profiles.length : 0;
        customlog(
          'GameplayProfilesBootstrap.mergeStatsEnvelope: full payload '
          'profile_count=$count revision=${revision ?? "(none)"}',
        );
      }
      return;
    }
    if (revision != null && revision.isNotEmpty) {
      await prefs.setString(prefRevisionKey, revision);
      GameplayProfilesStore.updateRevisionOnly(revision);
      if (LOGGING_SWITCH) {
        customlog(
          'GameplayProfilesBootstrap.mergeStatsEnvelope: revision-only $revision',
        );
      }
    }
  }

  static String? profileLabelForId(String? profileId) {
    final row = GameplayProfilesStore.resolveProfile(profileId);
    final label = row['label']?.toString().trim();
    return (label != null && label.isNotEmpty) ? label : null;
  }

  static String? profileLabelForSpecialEvent(Map<String, dynamic> eventRow) {
    final raw = eventRow['gameplay_profile_id'];
    final pid = raw?.toString().trim();
    if (pid == null || pid.isEmpty) return null;
    return profileLabelForId(pid);
  }
}
