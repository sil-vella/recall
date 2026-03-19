import '../../../../utils/config.dart';
import 'dart:convert';

/// Room **game table** tier (1–4): titles and coin entry fees.
///
/// This is the room's `game_level`, not the user's progression level in `modules.dutch_game`.
/// Fees are tied to the table only (indirectly related to which tables a user may unlock).
class LevelMatcher {
  static Map<int, Map<String, dynamic>> _parseTablesConfig() {
    final raw = Config.DUTCH_TABLES_JSON.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final out = <int, Map<String, dynamic>>{};
          decoded.forEach((k, v) {
            final lvl = int.tryParse(k.toString());
            if (lvl == null || v is! Map) return;
            final title = (v['title'] ?? '').toString().trim();
            final fee = int.tryParse((v['coin_fee'] ?? '').toString());
            final minUserLevel = int.tryParse((v['min_user_level'] ?? lvl).toString());
            if (title.isEmpty || fee == null || minUserLevel == null) return;
            out[lvl] = {
              'title': title,
              'coin_fee': fee,
              'min_user_level': minUserLevel,
            };
          });
          if (out.isNotEmpty) return out;
        }
      } catch (_) {
        // fallback below
      }
    }
    return <int, Map<String, dynamic>>{
      1: {'title': 'Home Table', 'coin_fee': 25, 'min_user_level': 1},
      2: {'title': 'Local Table', 'coin_fee': 50, 'min_user_level': 2},
      3: {'title': 'Town Table', 'coin_fee': 100, 'min_user_level': 3},
      4: {'title': 'City Table', 'coin_fee': 200, 'min_user_level': 4},
    };
  }

  static final Map<int, Map<String, dynamic>> _tablesConfig = _parseTablesConfig();

  /// Map level number to display title
  static Map<int, String> get levelToTitleMap => {
        for (final e in _tablesConfig.entries) e.key: e.value['title'] as String,
      };

  /// Map level number to coin fee (entry cost)
  static Map<int, int> get levelToCoinFeeMap => {
        for (final e in _tablesConfig.entries) e.key: e.value['coin_fee'] as int,
      };

  static Map<int, int> get tableLevelToMinUserLevelMap => {
        for (final e in _tablesConfig.entries) e.key: e.value['min_user_level'] as int,
      };

  /// All valid level numbers in order
  static List<int> get levelOrder => (levelToTitleMap.keys.toList()..sort());

  /// Get display title for a level number.
  /// Returns [defaultTitle] (or empty string if null) when level is null or invalid.
  static String levelToTitle(int? level, {String? defaultTitle}) {
    if (level == null) {
      return defaultTitle ?? '';
    }
    return levelToTitleMap[level] ?? defaultTitle ?? '';
  }

  /// Get level number for a title (case-insensitive match).
  /// Returns null when title is null or not found.
  static int? titleToLevel(String? title) {
    if (title == null || title.isEmpty) {
      return null;
    }
    final normalized = title.trim().toLowerCase();
    for (final entry in levelToTitleMap.entries) {
      if (entry.value.toLowerCase() == normalized) {
        return entry.key;
      }
    }
    return null;
  }

  /// Get coin fee for a **room table** tier (1–4).
  /// Returns [defaultFee] (or 0 if null) when level is null or invalid.
  static int levelToCoinFee(int? level, {int? defaultFee}) {
    if (level == null) {
      return defaultFee ?? 0;
    }
    return levelToCoinFeeMap[level] ?? defaultFee ?? 0;
  }

  /// Alias: entry cost for room **table** tier — same as [levelToCoinFee].
  static int tableLevelToCoinFee(int? roomTableLevel, {int? defaultFee}) {
    return levelToCoinFee(roomTableLevel, defaultFee: defaultFee);
  }

  static int tableLevelToRequiredUserLevel(int? roomTableLevel, {int? defaultLevel}) {
    if (roomTableLevel == null) {
      return defaultLevel ?? 1;
    }
    return tableLevelToMinUserLevelMap[roomTableLevel] ?? defaultLevel ?? 1;
  }

  /// Check if a level number is valid (1–4).
  static bool isValidLevel(int? level) {
    return level != null && levelToTitleMap.containsKey(level);
  }

  /// All titles in level order (1..4).
  static List<String> get allTitles =>
      levelOrder.map((l) => levelToTitleMap[l]!).toList();
}
