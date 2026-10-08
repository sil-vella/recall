import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Last leaderboard bundle on device, so a screen can paint before the network refresh.
class LeaderboardBundleStore {
  LeaderboardBundleStore._();

  /// Rows requested from the public bundle (wins periods + mastery) on the main leaderboard.
  static const int maxEntries = 100;

  static String scopeFor({String? gameType}) {
    final gt = (gameType ?? '').trim();
    return gt.isEmpty ? 'board_all' : 'board_$gt';
  }

  static const String historyScope = 'history';

  static String _prefKey(String scope) => 'dutch_lb_bundle_v1_$scope';

  static Future<Map<String, dynamic>?> read(String scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey(scope));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<void> write(String scope, Map<String, dynamic> bundle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey(scope), jsonEncode(bundle));
    } catch (_) {
      return;
    }
  }
}
