import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;


/// Coin catalog + native store ID tracing (enable-logging-switch.mdc).

/// Loads [assets/dutch_coin_catalog.json] — SSOT shared with Python `utils/coin_catalog.py`.
class CoinCatalog {
  CoinCatalog._();

  static Map<String, int>? _revenuecatProducts;
  static List<Map<String, dynamic>>? _recommendedUi;
  static bool _loadFailed = false;

  static Map<String, int> get revenuecatProducts =>
      Map<String, int>.unmodifiable(_revenuecatProducts ?? const {});

  static List<Map<String, dynamic>> get recommendedUiPackages =>
      List<Map<String, dynamic>>.unmodifiable(_recommendedUi ?? const []);

  static Future<void> ensureLoaded() async {
    if (_revenuecatProducts != null || _loadFailed) return;
    try {
      final raw = await rootBundle.loadString('assets/dutch_coin_catalog.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final rp = map['revenuecat_products'] as Map<String, dynamic>? ?? {};
      _revenuecatProducts = rp.map((k, v) => MapEntry(k, (v as num).toInt()));
      final rec = map['recommended_ui_packages'] as List<dynamic>? ?? [];
      _recommendedUi = rec.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e, st) {
      _loadFailed = true;
      _revenuecatProducts = {};
      _recommendedUi = [];
    }
  }
}
