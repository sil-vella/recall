import 'rank_matcher.dart';

/// Wins → progression level (1..10) → rank string.
///
/// Mirrors Python `wins_level_rank_matcher.WinsLevelRankMatcher` and is **not**
/// the same as [LevelMatcher] table levels (1–4 / coin fee).
///
/// Rank order matches [RankMatcher.rankHierarchy].
class WinsLevelRankMatcher {
  WinsLevelRankMatcher._();

  static const int progressionLevelMin = 1;
  static int get progressionLevelMax => RankMatcher.rankHierarchy.length;

  /// Same default as Python: wins per tier step after level 1.
  static const int winsPerProgressionLevel = 5;

  /// Non-negative wins → progression level in [progressionLevelMin, progressionLevelMax].
  static int winsToProgressionLevel(int? wins) {
    final w = wins == null ? 0 : (wins < 0 ? 0 : wins);
    final step = winsPerProgressionLevel < 1 ? 1 : winsPerProgressionLevel;
    final raw = w ~/ step + 1;
    if (raw < progressionLevelMin) return progressionLevelMin;
    if (raw > progressionLevelMax) return progressionLevelMax;
    return raw;
  }

  /// 1-based progression level → rank; clamps to hierarchy.
  static String progressionLevelToRank(int? progressionLevel) {
    if (progressionLevel == null) return RankMatcher.rankHierarchy.first;
    final lvl = progressionLevel;
    if (lvl < progressionLevelMin) return RankMatcher.rankHierarchy.first;
    if (lvl > progressionLevelMax) {
      return RankMatcher.rankHierarchy[progressionLevelMax - 1];
    }
    return RankMatcher.rankHierarchy[lvl - 1];
  }

  /// Compose wins → level → rank (expected rank from win count alone).
  static String winsToRank(int? wins) {
    return progressionLevelToRank(winsToProgressionLevel(wins));
  }
}
