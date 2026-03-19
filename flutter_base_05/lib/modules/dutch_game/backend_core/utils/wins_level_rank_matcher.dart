import 'rank_matcher.dart';
import 'level_matcher.dart';

/// Wins → user level → rank (Dutch progression).
///
/// - Every [winsPerUserLevel] wins increases **user level** by 1 (starts at 1).
/// - Every [levelsPerRank] user levels bumps **rank** one step on [RankMatcher.rankHierarchy].
/// - Game tables 1–4: joining table `T` requires `userLevel >= T` ([userMayJoinGameTable]).
///
/// User **level** in `modules.dutch_game.level` is this progression level (not the same
/// as coin-fee titles in [LevelMatcher], which describe the **room** tier).
class WinsLevelRankMatcher {
  WinsLevelRankMatcher._();

  static const int userLevelMin = int.fromEnvironment(
    'DUTCH_USER_LEVEL_MIN',
    defaultValue: 1,
  );
  static int get tableLevelMin =>
      LevelMatcher.levelOrder.isEmpty ? 1 : LevelMatcher.levelOrder.first;
  static int get tableLevelMax =>
      LevelMatcher.levelOrder.isEmpty ? 4 : LevelMatcher.levelOrder.last;

  /// Wins per +1 user level (matches Python).
  static const int winsPerUserLevel = int.fromEnvironment(
    'DUTCH_WINS_PER_USER_LEVEL',
    defaultValue: 10,
  );

  /// User levels per +1 rank tier (matches Python).
  static const int levelsPerRank = int.fromEnvironment(
    'DUTCH_LEVELS_PER_RANK',
    defaultValue: 5,
  );

  /// Lifetime wins → user level: `1 + wins ~/ step`.
  static int winsToUserLevel(int? wins) {
    final w = wins == null ? 0 : (wins < 0 ? 0 : wins);
    final step = winsPerUserLevel < 1 ? 1 : winsPerUserLevel;
    final lv = 1 + w ~/ step;
    return lv < userLevelMin ? userLevelMin : lv;
  }

  /// Rank index from user level; capped at legend.
  static int userLevelToRankIndex(int? userLevel) {
    if (userLevel == null) return 0;
    var lv = userLevel;
    if (lv < userLevelMin) lv = userLevelMin;
    final step = levelsPerRank < 1 ? 1 : levelsPerRank;
    var idx = (lv - 1) ~/ step;
    final maxIdx = RankMatcher.rankHierarchy.length - 1;
    if (idx < 0) idx = 0;
    if (idx > maxIdx) idx = maxIdx;
    return idx;
  }

  static String userLevelToRank(int? userLevel) {
    return RankMatcher.rankHierarchy[userLevelToRankIndex(userLevel)];
  }

  static String winsToRank(int? wins) {
    return userLevelToRank(winsToUserLevel(wins));
  }

  /// Table access rule is configured by LevelMatcher.tableLevelToRequiredUserLevel.
  /// Unknown table levels: allow.
  static bool userMayJoinGameTable(int userLevel, int gameTableLevel) {
    if (!LevelMatcher.isValidLevel(gameTableLevel)) {
      return true;
    }
    final ul = userLevel < userLevelMin ? userLevelMin : userLevel;
    final required = LevelMatcher.tableLevelToRequiredUserLevel(
      gameTableLevel,
      defaultLevel: gameTableLevel,
    );
    return ul >= required;
  }
}
