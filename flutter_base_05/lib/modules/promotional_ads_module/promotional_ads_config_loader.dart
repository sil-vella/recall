import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../tools/logging/logger.dart';
import '../../utils/consts/config.dart';
import 'ad_registry.dart';
import 'models/ad_event_type_config.dart';
import 'models/ad_registration.dart';

/// enable-logging-switch.mdc — set false after debugging promotional load/network.
const bool LOGGING_SWITCH = true;

/// Loads promotional ads from `${Config.apiUrl}/sponsors/promotional_ads.json` only (no bundled fallback).
class PromotionalAdsConfigLoader {
  static final Logger _logger = Logger();
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
    if (LOGGING_SWITCH) {
      final hasSwitch = AdRegistry.instance.typeById('switch_screen') != null;
      final hasBottom = AdRegistry.instance.typeById('bottom_banner_promo') != null;
      _logger.info(
        'PromotionalAdsConfigLoader: initialize() finished '
        '(types: switch_screen=$hasSwitch bottom_banner_promo=$hasBottom)',
      );
    }
  }

  static Future<void> _tryLoadFromNetwork() async {
    AdRegistry.instance.clear();
    final base = Config.apiUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/sponsors/promotional_ads.json').replace(
      queryParameters: {'v': clientManifestQueryVersion.toString()},
    );
    if (LOGGING_SWITCH) {
      _logger.info('PromotionalAdsConfigLoader: GET $uri (apiUrl=$base)');
    }
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        if (LOGGING_SWITCH) {
          _logger.info(
            'PromotionalAdsConfigLoader: HTTP ${response.statusCode} for manifest — no ads',
          );
        }
        return;
      }
      final dynamic root = json.decode(response.body);
      if (root is! Map) {
        if (LOGGING_SWITCH) {
          _logger.info('PromotionalAdsConfigLoader: JSON root is not a Map — no ads');
        }
        return;
      }
      final map = Map<dynamic, dynamic>.from(root);
      final remoteBase = '$base/sponsors/adverts';
      final counts = _applyRootMap(map, remoteMediaBaseUrl: remoteBase);
      if (LOGGING_SWITCH) {
        _logger.info(
          'PromotionalAdsConfigLoader: registered types=${counts.$1} ads=${counts.$2} '
          'remoteMediaBase=$remoteBase',
        );
      }
    } catch (e, st) {
      if (LOGGING_SWITCH) {
        _logger.error(
          'PromotionalAdsConfigLoader: network load failed (no ads registered)',
          error: e,
          stackTrace: st,
        );
      }
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
