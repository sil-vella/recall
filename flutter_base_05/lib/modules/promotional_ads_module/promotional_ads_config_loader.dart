import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/consts/config.dart';
import 'ad_registry.dart';
import 'models/ad_event_type_config.dart';
import 'models/ad_registration.dart';

/// Loads promotional ads from `${Config.apiUrl}/sponsors/promotional_ads.json` only (no bundled fallback).
class PromotionalAdsConfigLoader {
  static bool _loaded = false;

  /// Bump to force clients to re-request the manifest (cache bust query param).
  static const int clientManifestQueryVersion = 1;

  /// Idempotent: safe to call from [main] and again from tests.
  static Future<void> initialize() async {
    if (_loaded) {
      return;
    }
    await _tryLoadFromNetwork();
    _loaded = true;
    
  }

  static Future<void> _tryLoadFromNetwork() async {
    AdRegistry.instance.clear();
    final base = Config.apiUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/sponsors/promotional_ads.json').replace(
      queryParameters: {'v': clientManifestQueryVersion.toString()},
    );
    
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        
        return;
      }
      final dynamic root = json.decode(response.body);
      if (root is! Map) {
        
        return;
      }
      final map = Map<dynamic, dynamic>.from(root);
      final remoteBase = '$base/sponsors/adverts';
      final counts = _applyRootMap(map, remoteMediaBaseUrl: remoteBase);
      AdRegistry.instance.shuffleAdsPerType();
      
    } catch (e, st) {
      
    }
  }

  /// Returns (registered_event_types, registered_ads).
  static (int, int) _applyRootMap(
    Map<dynamic, dynamic> root, {
    required String? remoteMediaBaseUrl,
  }) {
    int typeCount = 0;
    int adCount = 0;
    final types = root['ad_event_types'];
    if (types is List) {
      for (final raw in types) {
        if (raw is Map) {
          final cfg = AdEventTypeConfig.fromYamlMap(Map<dynamic, dynamic>.from(raw));
          if (cfg.id.isNotEmpty && cfg.hookName.isNotEmpty) {
            AdRegistry.instance.registerType(cfg);
            typeCount++;
          }
        }
      }
    }
    final ads = root['ads'];
    if (ads is List) {
      for (final raw in ads) {
        if (raw is Map) {
          final ad = AdRegistration.fromYamlMap(
            Map<dynamic, dynamic>.from(raw),
            remoteMediaBaseUrl: remoteMediaBaseUrl,
          );
          if (ad.id.isNotEmpty && ad.adTypeId.isNotEmpty && ad.link.isNotEmpty) {
            AdRegistry.instance.registerAd(ad);
            adCount++;
          }
        }
      }
    }
    return (typeCount, adCount);
  }

  /// For tests / hot-restart scenarios.
  static void resetLoadedFlagForTests() {
    _loaded = false;
  }
}
