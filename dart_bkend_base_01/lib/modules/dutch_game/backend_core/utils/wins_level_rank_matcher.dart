import 'rank_matcher.dart';

/// Wins → user level → rank. Mirrors Python / Flutter [WinsLevelRankMatcher].
///
/// Table `T` in 1..4: user must have `userLevel >= T` to join/create at that game level.
class WinsLevelRankMatcher {
  WinsLevelRankMatcher._();

  static const int userLevelMin = 1;
  static const int tableLevelMin = 1;
  static const int tableLevelMax = 4;

  static const int winsPerUserLevel = 10;
  static const int levelsPerRank = 5;

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
    if (gameTableLevel < tableLevelMin || gameTableLevel > tableLevelMax) {
      return true;
    }
    final ul = userLevel < userLevelMin ? userLevelMin : userLevel;
    return ul >= gameTableLevel;
  }
}
