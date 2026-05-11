import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'dbg.dart';

/// Loads [assets/dutch_coin_catalog.json] — SSOT shared with Python `utils/coin_catalog.py`.
class CoinCatalog {
  CoinCatalog._();

  /// Play/App Store product id → coins (for future native IAP; catalog key `in_app_products`).
  static Map<String, int>? _inAppProducts;
  static List<Map<String, dynamic>>? _recommendedUi;
  static List<Map<String, dynamic>>? _playRecommendedUi;
  static bool _loadFailed = false;

  static Map<String, int> get inAppProducts =>
      Map<String, int>.unmodifiable(_inAppProducts ?? const {});

  static List<Map<String, dynamic>> get recommendedUiPackages =>
      List<Map<String, dynamic>>.unmodifiable(_recommendedUi ?? const []);

  /// Google Play product rows from [play_recommended_packages] (product_id must exist in in_app_products).
  static List<Map<String, dynamic>> get playRecommendedPackages =>
      List<Map<String, dynamic>>.unmodifiable(_playRecommendedUi ?? const []);

  static Future<void> ensureLoaded() async {
    if (_inAppProducts != null || _loadFailed) return;
    try {
      final raw = await rootBundle.loadString('assets/dutch_coin_catalog.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ip = map['in_app_products'] as Map<String, dynamic>? ??
          map['revenuecat_products'] as Map<String, dynamic>? ??
          {};
      _inAppProducts = ip.map((k, v) => MapEntry(k, (v as num).toInt()));
      final rec = map['recommended_ui_packages'] as List<dynamic>? ?? [];
      _recommendedUi = rec.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final playRec = map['play_recommended_packages'] as List<dynamic>? ?? [];
      final built = <Map<String, dynamic>>[];
      for (final e in playRec) {
        if (e is! Map) continue;
        final row = Map<String, dynamic>.from(e);
        final pid = row['product_id']?.toString() ?? '';
        if (pid.isEmpty || !(_inAppProducts!.containsKey(pid))) continue;
        row['coins'] = _inAppProducts![pid];
        built.add(row);
      }
      _playRecommendedUi = built;
      dbg(
        'CoinCatalog',
        'loaded in_app_products=${_inAppProducts!.length} recommended_ui=${_recommendedUi!.length} play_recommended=${_playRecommendedUi!.length}',
      );
    } catch (e, st) {
      _loadFailed = true;
      _inAppProducts = {};
      _recommendedUi = [];
      _playRecommendedUi = [];
      dbg('CoinCatalog', 'load failed', error: e, stackTrace: st);
    }
  }
}
