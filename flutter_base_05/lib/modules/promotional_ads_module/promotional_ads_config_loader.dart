import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import 'ad_registry.dart';
import 'models/ad_event_type_config.dart';
import 'models/ad_registration.dart';
import '../../tools/logging/logger.dart';

const bool _LOGGING_SWITCH = false;

/// Loads [assets/promotional_ads.yaml] into [AdRegistry].
class PromotionalAdsConfigLoader {
  static final Logger _logger = Logger();
  static bool _loaded = false;

  /// Idempotent: safe to call from [main] and again from tests.
  static Future<void> loadFromAsset(String assetPath) async {
    if (_loaded) {
      return;
    }
    AdRegistry.instance.clear();
    try {
      final yamlString = await rootBundle.loadString(assetPath);
      final dynamic root = loadYaml(yamlString);
      if (root is! Map) {
        return;
      }
      final types = root['ad_event_types'];
      if (types is List) {
        for (final raw in types) {
          if (raw is Map) {
            final cfg = AdEventTypeConfig.fromYamlMap(raw);
            if (cfg.id.isNotEmpty && cfg.hookName.isNotEmpty) {
              AdRegistry.instance.registerType(cfg);
            }
          }
        }
      }
      final ads = root['ads'];
      if (ads is List) {
        for (final raw in ads) {
          if (raw is Map) {
            final ad = AdRegistration.fromYamlMap(raw);
            if (ad.id.isNotEmpty && ad.adTypeId.isNotEmpty && ad.link.isNotEmpty) {
              AdRegistry.instance.registerAd(ad);
            }
          }
        }
      }
      if (_LOGGING_SWITCH) {
        _logger.info(
          'PromotionalAdsConfigLoader: loaded types=${AdRegistry.instance.typeById('switch_screen') != null}',
        );
      }
      _loaded = true;
    } catch (e, st) {
      _logger.error('PromotionalAdsConfigLoader: failed to load $assetPath', error: e, stackTrace: st);
    }
  }

  /// For tests / hot-restart scenarios.
  static void resetLoadedFlagForTests() {
    _loaded = false;
  }
}
