import '../../utils/progression_config_store.dart';
import 'level_matcher.dart';
import 'rank_matcher.dart';

/// Wins → user level → rank (Dutch progression). Rules from [ProgressionConfigStore].
class WinsLevelRankMatcher {
  WinsLevelRankMatcher._();

  static int get userLevelMin => ProgressionConfigStore.userLevelMin;
  static int get winsPerUserLevel => ProgressionConfigStore.winsPerUserLevel;
  static int get levelsPerRank => ProgressionConfigStore.levelsPerRank;

  static int get tableLevelMin =>
      LevelMatcher.levelOrder.isEmpty ? 1 : LevelMatcher.levelOrder.first;
  static int get tableLevelMax =>
      LevelMatcher.levelOrder.isEmpty ? 4 : LevelMatcher.levelOrder.last;

  static int winsToUserLevel(int? wins) {
    final w = wins == null ? 0 : (wins < 0 ? 0 : wins);
    final step = winsPerUserLevel < 1 ? 1 : winsPerUserLevel;
    final lv = 1 + w ~/ step;
    return lv < userLevelMin ? userLevelMin : lv;
  }

  static int userLevelToRankIndex(int? userLevel) =>
      ProgressionConfigStore.userLevelToRankIndex(userLevel);

  static String userLevelToRank(int? userLevel) =>
      ProgressionConfigStore.userLevelToRank(userLevel);

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
