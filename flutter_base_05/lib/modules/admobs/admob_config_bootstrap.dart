import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/consts/config.dart';
import '../../utils/dev_logger.dart';
import 'admob_config_store.dart';

// ignore: constant_identifier_names — set false when not debugging AdMob remote config.
const bool LOGGING_SWITCH = true;

/// Persists declarative AdMob config from get-init-data / public init-config.
class AdmobConfigBootstrap {
  AdmobConfigBootstrap._();

  static const String prefRevisionKey = 'dutch_admob_config_revision';
  static const String prefDocKey = 'dutch_admob_config_doc_json';

  static Map<String, dynamic> _cachedDoc = <String, dynamic>{};

  static Future<void> hydrateFromPrefsBeforeStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefDocKey)?.trim();
      final storedRev = prefs.getString(prefRevisionKey)?.trim();
      if (raw == null || raw.isEmpty) {
        _cachedDoc = <String, dynamic>{};
        AdmobConfigStore.ensureBuiltinFallback();
        if (LOGGING_SWITCH) {
          customlog(
            'AdmobConfigBootstrap: hydrate prefs empty — builtin fallback '
            'top=${AdmobConfigStore.topBanner} rewarded=${AdmobConfigStore.rewarded}',
          );
        }
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cachedDoc = Map<String, dynamic>.from(decoded);
        AdmobConfigStore.applyDocument(_cachedDoc);
        if (LOGGING_SWITCH) {
          customlog(
            'AdmobConfigBootstrap: hydrate from prefs revision=$storedRev '
            'top=${AdmobConfigStore.topBanner} interstitial=${AdmobConfigStore.interstitial} '
            'rewarded=${AdmobConfigStore.rewarded} coins=${AdmobConfigStore.rewardedCoinsPerClaim} '
            'cap=${AdmobConfigStore.rewardedDailyCap}',
          );
        }
      } else {
        _cachedDoc = <String, dynamic>{};
        AdmobConfigStore.ensureBuiltinFallback();
        if (LOGGING_SWITCH) {
          customlog('AdmobConfigBootstrap: hydrate prefs decode not a map — builtin fallback');
        }
      }
    } catch (e) {
      _cachedDoc = <String, dynamic>{};
      AdmobConfigStore.ensureBuiltinFallback();
      if (LOGGING_SWITCH) {
        customlog('AdmobConfigBootstrap: hydrate failed $e — builtin fallback');
      }
    }
  }

  static Future<String?> getStoredRevisionForApi() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getString(prefRevisionKey)?.trim();
    return (r != null && r.isNotEmpty) ? r : null;
  }

  static Future<void> mergeEnvelope(Map<String, dynamic> envelope) async {
    final prefs = await SharedPreferences.getInstance();
    final revision = envelope['admob_config_revision']?.toString().trim();
    final payload = envelope['admob_config'];

    if (payload is Map<String, dynamic>) {
      final typed = Map<String, dynamic>.from(payload);
      _cachedDoc = typed;
      AdmobConfigStore.applyDocument(typed);
      await prefs.setString(prefDocKey, jsonEncode(typed));
      if (revision != null && revision.isNotEmpty) {
        await prefs.setString(prefRevisionKey, revision);
      }
      if (LOGGING_SWITCH) {
        customlog(
          'AdmobConfigBootstrap: merge payload revision=$revision '
          'top=${AdmobConfigStore.topBanner} interstitial=${AdmobConfigStore.interstitial} '
          'rewarded=${AdmobConfigStore.rewarded}',
        );
      }
      return;
    }

    if (revision != null && revision.isNotEmpty) {
      await prefs.setString(prefRevisionKey, revision);
    }
    if (_cachedDoc.isNotEmpty) {
      AdmobConfigStore.applyDocument(_cachedDoc);
    }
    if (LOGGING_SWITCH) {
      customlog(
        'AdmobConfigBootstrap: merge revision-only revision=$revision '
        'payloadAbsent=${payload == null} cachedDocKeys=${_cachedDoc.keys.toList()}',
      );
    }
  }

  /// Alias for authenticated get-init-data responses.
  static Future<void> mergeStatsEnvelope(Map<String, dynamic> envelope) =>
      mergeEnvelope(envelope);

  /// Public init-config uses the same prefs keys.
  static Future<void> mergePublicConfigEnvelope(Map<String, dynamic> envelope) =>
      mergeEnvelope(envelope);

  /// Early startup fetch (before [ConnectionsApiModule] is registered).
  static Future<bool> fetchPublicConfigIfNeeded() async {
    try {
      final queryParts = <String>[];
      final admobRev = await getStoredRevisionForApi();
      if (admobRev != null && admobRev.isNotEmpty) {
        queryParts.add(
          'client_admob_config_revision=${Uri.encodeQueryComponent(admobRev)}',
        );
      }
      final base = Config.apiUrl.replaceAll(RegExp(r'/$'), '');
      final route = queryParts.isEmpty
          ? '$base/public/dutch/init-config'
          : '$base/public/dutch/init-config?${queryParts.join('&')}';

      if (LOGGING_SWITCH) {
        customlog('AdmobConfigBootstrap: fetch GET $route clientRev=$admobRev');
      }

      final response = await http.get(Uri.parse(route)).timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode != 200) {
        if (LOGGING_SWITCH) {
          customlog(
            'AdmobConfigBootstrap: fetch failed status=${response.statusCode} '
            'bodyLen=${response.body.length}',
          );
        }
        return false;
      }
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        if (LOGGING_SWITCH) {
          customlog('AdmobConfigBootstrap: fetch body not a JSON object');
        }
        return false;
      }
      final envelope = Map<String, dynamic>.from(decoded);
      if (LOGGING_SWITCH) {
        customlog(
          'AdmobConfigBootstrap: fetch ok serverRevision=${envelope['admob_config_revision']} '
          'hasPayload=${envelope.containsKey('admob_config')}',
        );
      }
      await mergePublicConfigEnvelope(envelope);
      return true;
    } catch (e) {
      if (LOGGING_SWITCH) {
        customlog('AdmobConfigBootstrap: fetch exception $e');
      }
      return false;
    }
  }
}
