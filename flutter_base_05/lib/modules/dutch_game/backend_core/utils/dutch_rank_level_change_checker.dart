import 'rank_matcher.dart';
import 'wins_level_rank_matcher.dart';

/// Stored rank/level trend vs prior snapshot.
enum StoredTrend {
  same,
  progression,
  regression,
}

/// Wins-only matcher trend (expected rank from win totals).
enum MatcherTrend {
  same,
  progression,
  regression,
}

/// Result of comparing Dutch `userStats` before and after a match refresh.
class DutchRankLevelChangeResult {
  const DutchRankLevelChangeResult({
    required this.hadBeforeSnapshot,
    required this.rankChanged,
    required this.levelChanged,
    required this.storedRankTrend,
    required this.storedLevelTrend,
    required this.matcherTrend,
    this.rankBefore,
    this.rankAfter,
    this.levelBefore,
    this.levelAfter,
    this.winsBefore,
    this.winsAfter,
    this.matcherRankBefore,
    this.matcherRankAfter,
  });

  final bool hadBeforeSnapshot;
  final bool rankChanged;
  final bool levelChanged;
  final StoredTrend storedRankTrend;
  final StoredTrend storedLevelTrend;
  final MatcherTrend matcherTrend;

  final String? rankBefore;
  final String? rankAfter;
  final int? levelBefore;
  final int? levelAfter;
  final int? winsBefore;
  final int? winsAfter;
  final String? matcherRankBefore;
  final String? matcherRankAfter;

  static DutchRankLevelChangeResult inconclusive() {
    return const DutchRankLevelChangeResult(
      hadBeforeSnapshot: false,
      rankChanged: false,
      levelChanged: false,
      storedRankTrend: StoredTrend.same,
      storedLevelTrend: StoredTrend.same,
      matcherTrend: MatcherTrend.same,
    );
  }

  /// Whether stored rank or table level differs (only meaningful if [hadBeforeSnapshot]).
  bool get anyStoredFieldChanged => rankChanged || levelChanged;
}

/// Compare rank/level/wins across two `userStats` maps; uses [WinsLevelRankMatcher] for matcher trend.
class DutchRankLevelChangeChecker {
  DutchRankLevelChangeChecker._();

  /// Shallow snapshot of fields needed for post-match comparison.
  static Map<String, dynamic>? snapshotRankLevelWins(Map<String, dynamic>? userStats) {
    if (userStats == null) return null;
    return {
      'rank': userStats['rank'],
      'level': userStats['level'],
      'wins': userStats['wins'],
    };
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static String _normalizedRank(Map<String, dynamic>? m) {
    if (m == null) return '';
    final r = m['rank']?.toString() ?? '';
    return RankMatcher.normalizeRank(r);
  }

  static int? _level(Map<String, dynamic>? m) => _parseInt(m?['level']);

  static int? _wins(Map<String, dynamic>? m) => _parseInt(m?['wins']);

  static int _rankIndexOrBeginner(String normalized) {
    if (normalized.isEmpty) return 0;
    final i = RankMatcher.getRankIndex(normalized);
    return i >= 0 ? i : 0;
  }

  static StoredTrend _rankTrend(String before, String after) {
    final i1 = _rankIndexOrBeginner(before);
    final i2 = _rankIndexOrBeginner(after);
    if (i2 > i1) return StoredTrend.progression;
    if (i2 < i1) return StoredTrend.regression;
    return StoredTrend.same;
  }

  static StoredTrend _levelTrend(int? before, int? after) {
    if (before == null || after == null) return StoredTrend.same;
    if (after > before) return StoredTrend.progression;
    if (after < before) return StoredTrend.regression;
    return StoredTrend.same;
  }

  static MatcherTrend _matcherTrend(int? winsBefore, int? winsAfter) {
    final wb = winsBefore ?? 0;
    final wa = winsAfter ?? 0;
    final rb = WinsLevelRankMatcher.winsToRank(wb);
    final ra = WinsLevelRankMatcher.winsToRank(wa);
    final ib = RankMatcher.getRankIndex(rb);
    final ia = RankMatcher.getRankIndex(ra);
    if (ib < 0 || ia < 0) return MatcherTrend.same;
    if (ia > ib) return MatcherTrend.progression;
    if (ia < ib) return MatcherTrend.regression;
    return MatcherTrend.same;
  }

  /// Compare API `userStats`-shaped maps (or snapshots from [snapshotRankLevelWins]).
  static DutchRankLevelChangeResult analyze({
    Map<String, dynamic>? statsBefore,
    Map<String, dynamic>? statsAfter,
  }) {
    if (statsAfter == null) return DutchRankLevelChangeResult.inconclusive();
    if (statsBefore == null) return DutchRankLevelChangeResult.inconclusive();

    final rankB = _normalizedRank(statsBefore);
    final rankA = _normalizedRank(statsAfter);
    final lvlB = _level(statsBefore);
    final lvlA = _level(statsAfter);
    final winsB = _wins(statsBefore);
    final winsA = _wins(statsAfter);

    final rankChanged = rankB != rankA;
    final levelChanged = lvlB != lvlA;

    final mRankB = WinsLevelRankMatcher.winsToRank(winsB);
    final mRankA = WinsLevelRankMatcher.winsToRank(winsA);

    return DutchRankLevelChangeResult(
      hadBeforeSnapshot: true,
      rankChanged: rankChanged,
      levelChanged: levelChanged,
      storedRankTrend: _rankTrend(rankB, rankA),
      storedLevelTrend: _levelTrend(lvlB, lvlA),
      matcherTrend: _matcherTrend(winsB, winsA),
      rankBefore: rankB.isEmpty ? null : rankB,
      rankAfter: rankA.isEmpty ? null : rankA,
      levelBefore: lvlB,
      levelAfter: lvlA,
      winsBefore: winsB,
      winsAfter: winsA,
      matcherRankBefore: mRankB,
      matcherRankAfter: mRankA,
    );
  }
}
