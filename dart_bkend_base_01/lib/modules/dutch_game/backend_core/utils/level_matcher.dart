/// Room **game table** tier (1–4): titles and coin entry fees.
///
/// This is the room's `game_level`, not the user's progression level in `modules.dutch_game`.
/// Fees are tied to the table only (indirectly related to which tables a user may unlock).
class LevelMatcher {
  /// Map level number to display title
  static const Map<int, String> levelToTitleMap = {
    1: 'Home Table',
    2: 'Local Table',
    3: 'Town Table',
    4: 'City Table',
  };

  /// Map level number to coin fee (entry cost)
  static const Map<int, int> levelToCoinFeeMap = {
    1: 25,
    2: 50,
    3: 100,
    4: 200,
  };

  /// All valid level numbers in order
  static const List<int> levelOrder = [1, 2, 3, 4];

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

  /// Check if a level number is valid (1–4).
  static bool isValidLevel(int? level) {
    return level != null && levelToTitleMap.containsKey(level);
  }

  /// All titles in level order (1..4).
  static List<String> get allTitles =>
      levelOrder.map((l) => levelToTitleMap[l]!).toList();
}
