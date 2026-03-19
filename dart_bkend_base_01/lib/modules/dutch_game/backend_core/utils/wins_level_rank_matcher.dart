import 'rank_matcher.dart';
import '../../../../utils/config.dart';
import 'level_matcher.dart';

/// Wins → user level → rank. Mirrors Python / Flutter [WinsLevelRankMatcher].
///
/// Table `T` in 1..4: user must have `userLevel >= T` to join/create at that game level.
class WinsLevelRankMatcher {
  WinsLevelRankMatcher._();

  static int get userLevelMin => Config.DUTCH_USER_LEVEL_MIN;
  static int get tableLevelMin =>
      LevelMatcher.levelOrder.isEmpty ? 1 : LevelMatcher.levelOrder.first;
  static int get tableLevelMax =>
      LevelMatcher.levelOrder.isEmpty ? 4 : LevelMatcher.levelOrder.last;

  static int get winsPerUserLevel => Config.DUTCH_WINS_PER_USER_LEVEL;
  static int get levelsPerRank => Config.DUTCH_LEVELS_PER_RANK;

  static int winsToUserLevel(int? wins) {
    final w = wins == null ? 0 : (wins < 0 ? 0 : wins);
    final step = winsPerUserLevel < 1 ? 1 : winsPerUserLevel;
    final lv = 1 + w ~/ step;
    return lv < userLevelMin ? userLevelMin : lv;
  }

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
