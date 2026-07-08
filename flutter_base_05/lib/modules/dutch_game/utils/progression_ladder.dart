import '../backend_core/utils/level_matcher.dart';
import '../backend_core/utils/wins_level_rank_matcher.dart';
import 'progression_config_store.dart';

/// Whether a ladder row is done, in progress, or not yet reachable.
enum ProgressionLadderStatus {
  completed,
  current,
  locked,
}

/// One row on the progression screen (rank, user level, or table tier).
class ProgressionLadderEntry {
  const ProgressionLadderEntry({
    required this.id,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.status,
    this.progressLabel,
    this.progressCurrent,
    this.progressRequired,
    this.progressFraction,
    this.winsRequired = 0,
    this.userLevelRequired = 1,
  });

  final String id;
  final ProgressionLadderCategory category;
  final String title;
  final String subtitle;
  final ProgressionLadderStatus status;
  final String? progressLabel;
  final int? progressCurrent;
  final int? progressRequired;
  final double? progressFraction;
  final int winsRequired;
  final int userLevelRequired;
}

enum ProgressionLadderCategory {
  ranks,
  levels,
  tables,
}

/// Snapshot for the progression summary header.
class ProgressionSummary {
  const ProgressionSummary({
    required this.wins,
    required this.userLevel,
    required this.rankLabel,
    this.nextLevel,
    this.winsToNextLevel,
    this.winsProgressFraction,
  });

  final int wins;
  final int userLevel;
  final String rankLabel;
  final int? nextLevel;
  final int? winsToNextLevel;
  final double? winsProgressFraction;
}

int _int(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

String _titleCaseRank(String rank) {
  final s = rank.trim().toLowerCase();
  if (s.isEmpty) return 'Beginner';
  return s.split(RegExp(r'[\s_]+')).map((w) {
    if (w.isEmpty) return w;
    return '${w[0].toUpperCase()}${w.substring(1)}';
  }).join(' ');
}

int _winsForUserLevel(int level) {
  final cum = ProgressionConfigStore.cumulativeWinsForUserLevel;
  if (level < 1) return 0;
  if (cum.isEmpty) return 0;
  final idx = level - 1;
  if (idx >= cum.length) return cum.last;
  return cum[idx];
}

int _maxUserLevel() {
  final cum = ProgressionConfigStore.cumulativeWinsForUserLevel;
  return cum.isEmpty ? 55 : cum.length;
}

/// Builds rank tier rows with level spans from [ProgressionConfigStore].
List<ProgressionLadderEntry> buildRankLadderEntries({
  required int userLevel,
  required int wins,
}) {
  final ranks = ProgressionConfigStore.rankHierarchy;
  final spans = ProgressionConfigStore.levelsPerRankSpans;
  final entries = <ProgressionLadderEntry>[];
  var levelStart = 1;
  final currentRankIdx = ProgressionConfigStore.userLevelToRankIndex(userLevel);

  for (var i = 0; i < ranks.length; i++) {
    final span = i < spans.length ? spans[i] : ProgressionConfigStore.levelsPerRank;
    final levelEnd = levelStart + span - 1;
    final rankId = ranks[i];
    final display = _titleCaseRank(rankId);
    final winsRequired = _winsForUserLevel(levelStart);

    ProgressionLadderStatus status;
    if (userLevel > levelEnd) {
      status = ProgressionLadderStatus.completed;
    } else if (i == currentRankIdx) {
      status = ProgressionLadderStatus.current;
    } else {
      status = ProgressionLadderStatus.locked;
    }

    double? fraction;
    String? progressLabel;
    int? progressCurrent;
    int? progressRequired;

    if (status == ProgressionLadderStatus.current) {
      final levelsInRank = levelEnd - levelStart + 1;
      final completedInRank = (userLevel - levelStart + 1).clamp(0, levelsInRank);
      progressCurrent = completedInRank;
      progressRequired = levelsInRank;
      fraction = levelsInRank > 0 ? completedInRank / levelsInRank : 0;
      progressLabel = 'Levels in rank';
    } else if (status == ProgressionLadderStatus.locked) {
      progressCurrent = wins;
      progressRequired = winsRequired;
      if (progressRequired > 0) {
        fraction = (wins / progressRequired).clamp(0.0, 1.0);
      }
      progressLabel = 'Wins to reach';
    }

    entries.add(
      ProgressionLadderEntry(
        id: 'rank_$rankId',
        category: ProgressionLadderCategory.ranks,
        title: display,
        subtitle: 'User levels $levelStart–$levelEnd · $winsRequired+ wins to enter',
        status: status,
        progressLabel: progressLabel,
        progressCurrent: progressCurrent,
        progressRequired: progressRequired,
        progressFraction: fraction,
        winsRequired: winsRequired,
        userLevelRequired: levelStart,
      ),
    );
    levelStart = levelEnd + 1;
  }
  return entries;
}

/// User level milestones (level 2 … max).
List<ProgressionLadderEntry> buildLevelLadderEntries({
  required int userLevel,
  required int wins,
}) {
  final maxLv = _maxUserLevel();
  final entries = <ProgressionLadderEntry>[];
  for (var lv = 2; lv <= maxLv; lv++) {
    final winsRequired = _winsForUserLevel(lv);
    final rank = _titleCaseRank(ProgressionConfigStore.userLevelToRank(lv));

    ProgressionLadderStatus status;
    if (userLevel >= lv) {
      status = ProgressionLadderStatus.completed;
    } else if (userLevel == lv - 1) {
      status = ProgressionLadderStatus.current;
    } else {
      status = ProgressionLadderStatus.locked;
    }

    double? fraction;
    int? progressCurrent;
    int? progressRequired;
    String? progressLabel;

    if (status == ProgressionLadderStatus.current) {
      final prevWins = _winsForUserLevel(lv - 1);
      final step = winsRequired - prevWins;
      progressCurrent = (wins - prevWins).clamp(0, step);
      progressRequired = step < 1 ? 1 : step;
      fraction = progressRequired > 0 ? progressCurrent / progressRequired : 0;
      progressLabel = 'Wins this level';
    } else if (status == ProgressionLadderStatus.locked) {
      progressCurrent = wins;
      progressRequired = winsRequired;
      fraction = winsRequired > 0 ? (wins / winsRequired).clamp(0.0, 1.0) : 0;
      progressLabel = 'Wins needed';
    }

    entries.add(
      ProgressionLadderEntry(
        id: 'level_$lv',
        category: ProgressionLadderCategory.levels,
        title: 'Level $lv',
        subtitle: '$rank · $winsRequired total wins',
        status: status,
        progressLabel: progressLabel,
        progressCurrent: progressCurrent,
        progressRequired: progressRequired,
        progressFraction: fraction,
        winsRequired: winsRequired,
        userLevelRequired: lv,
      ),
    );
  }
  return entries;
}

/// Table tier unlock rows from [LevelMatcher].
List<ProgressionLadderEntry> buildTableTierLadderEntries({
  required int userLevel,
  required int wins,
}) {
  LevelMatcher.ensureHydratedMinimal();
  final order = LevelMatcher.levelOrder;
  final entries = <ProgressionLadderEntry>[];

  for (final tier in order) {
    final title = LevelMatcher.levelToTitleMap[tier] ?? 'Table $tier';
    final minUl = LevelMatcher.tableLevelToRequiredUserLevel(tier, defaultLevel: tier);
    final fee = LevelMatcher.levelToCoinFeeMap[tier] ?? 0;
    final winsRequired = _winsForUserLevel(minUl);

    ProgressionLadderStatus status;
    if (userLevel >= minUl) {
      status = ProgressionLadderStatus.completed;
    } else if (entries.isEmpty || entries.last.status == ProgressionLadderStatus.completed) {
      status = ProgressionLadderStatus.current;
    } else {
      status = ProgressionLadderStatus.locked;
    }

    double? fraction;
    int? progressCurrent;
    int? progressRequired;
    String? progressLabel;

    if (status != ProgressionLadderStatus.completed) {
      progressCurrent = userLevel;
      progressRequired = minUl;
      final span = minUl < 1 ? 1 : minUl;
      fraction = (userLevel / span).clamp(0.0, 1.0);
      progressLabel = 'User level';
    }

    entries.add(
      ProgressionLadderEntry(
        id: 'table_$tier',
        category: ProgressionLadderCategory.tables,
        title: title,
        subtitle: 'User level $minUl · $fee coin fee · ~$winsRequired wins',
        status: status,
        progressLabel: progressLabel,
        progressCurrent: progressCurrent,
        progressRequired: progressRequired,
        progressFraction: fraction,
        winsRequired: winsRequired,
        userLevelRequired: minUl,
      ),
    );
  }
  return entries;
}

ProgressionSummary buildProgressionSummary(Map<String, dynamic>? stats) {
  final wins = _int(stats?['wins']);
  final userLevel = _int(stats?['level'], fallback: 1);
  final rank = stats?['rank']?.toString() ?? ProgressionConfigStore.userLevelToRank(userLevel);
  final maxLv = _maxUserLevel();
  final nextLevel = userLevel < maxLv ? userLevel + 1 : null;
  int? winsToNext;
  double? fraction;
  if (nextLevel != null) {
    final target = _winsForUserLevel(nextLevel);
    final floor = _winsForUserLevel(userLevel);
    winsToNext = (target - wins).clamp(0, target);
    final step = target - floor;
    if (step > 0) {
      fraction = ((wins - floor) / step).clamp(0.0, 1.0);
    }
  }
  return ProgressionSummary(
    wins: wins,
    userLevel: userLevel,
    rankLabel: _titleCaseRank(rank),
    nextLevel: nextLevel,
    winsToNextLevel: winsToNext,
    winsProgressFraction: fraction,
  );
}

/// Derives user level from wins when stats omit an up-to-date level.
int resolveUserLevelFromStats(Map<String, dynamic>? stats) {
  final fromStats = _int(stats?['level'], fallback: 0);
  if (fromStats >= 1) return fromStats;
  return WinsLevelRankMatcher.winsToUserLevel(_int(stats?['wins']));
}
