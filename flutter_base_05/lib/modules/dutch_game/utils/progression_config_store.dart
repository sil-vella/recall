import 'package:flutter/foundation.dart';

/// In-memory progression rules from server declarative catalog (hydrated from prefs / init).
class ProgressionConfigStore {
  ProgressionConfigStore._();

  static final ValueNotifier<int> changeVersion = ValueNotifier<int>(0);

  static List<String> _rankHierarchy = List.from(_builtinRankHierarchy);
  static List<int> _levelsPerRankSpans = List.filled(_builtinRankHierarchy.length, 5);
  static int _userLevelMin = 1;
  static int _winsPerUserLevel = 37;
  static List<int> _winsPerLevelSteps = List.from(_builtinWinsPerLevelSteps);
  static List<int> _cumulativeWinsForUserLevel =
      List.from(_builtinCumulativeWinsForUserLevel);
  static int _maxRankDelta = 1;
  static final Map<String, String> _rankToDifficulty = Map.from(_builtinRankToDifficulty);

  static const List<String> _builtinRankHierarchy = [
    'beginner',
    'novice',
    'apprentice',
    'skilled',
    'advanced',
    'expert',
    'veteran',
    'master',
    'elite',
    'legend',
  ];

  static const Map<String, String> _builtinRankToDifficulty = {
    'beginner': 'easy',
    'novice': 'medium',
    'apprentice': 'medium',
    'skilled': 'hard',
    'advanced': 'hard',
    'expert': 'hard',
    'veteran': 'expert',
    'master': 'expert',
    'elite': 'expert',
    'legend': 'expert',
  };

  /// Wins for each +1 user level after level 1 (54 steps → level 55 @ 2000 wins).
  static const List<int> _builtinWinsPerLevelSteps = [
    ...[10, 10, 10, 10, 10, 10, 10, 10, 10],
    ...[18, 18, 18, 18, 18, 18, 18, 18, 18],
    ...[28, 28, 28, 28, 28, 28, 28, 28, 28],
    ...[40, 40, 40, 40, 40, 40, 40, 40, 40],
    ...[55, 55, 55, 55, 55, 55, 55, 55, 55],
    ...[71, 71, 71, 71, 71, 71, 71, 71, 73],
  ];

  static final List<int> _builtinCumulativeWinsForUserLevel =
      _buildCumulativeWinsForUserLevel(_builtinWinsPerLevelSteps);

  static List<String> get rankHierarchy => List.unmodifiable(_rankHierarchy);
  static List<int> get levelsPerRankSpans => List.unmodifiable(_levelsPerRankSpans);
  /// First rank span (legacy); prefer [levelsPerRankFor] or [levelsPerRankSpans].
  static int get levelsPerRank =>
      _levelsPerRankSpans.isEmpty ? 5 : _levelsPerRankSpans.first;
  static int get userLevelMin => _userLevelMin;
  static int get winsPerUserLevel => _winsPerUserLevel;
  static List<int> get winsPerLevelSteps => List.unmodifiable(_winsPerLevelSteps);
  static List<int> get cumulativeWinsForUserLevel =>
      List.unmodifiable(_cumulativeWinsForUserLevel);
  static int get maxRankDelta => _maxRankDelta;

  static bool get hasServerDocument => _hasServerDocument;
  static bool _hasServerDocument = false;

  static int levelsPerRankFor(String rank) {
    final n = rank.trim().toLowerCase();
    final i = _rankHierarchy.indexOf(n);
    if (i >= 0 && i < _levelsPerRankSpans.length) {
      return _levelsPerRankSpans[i];
    }
    return levelsPerRank;
  }

  static int userLevelToRankIndex(int? userLevel) {
    if (userLevel == null || _rankHierarchy.isEmpty) return 0;
    var lv = userLevel;
    if (lv < userLevelMin) lv = userLevelMin;
    final maxIdx = _rankHierarchy.length - 1;
    var offset = 0;
    for (var i = 0; i < _levelsPerRankSpans.length; i++) {
      final step = _levelsPerRankSpans[i] < 1 ? 1 : _levelsPerRankSpans[i];
      if (lv <= offset + step) return i > maxIdx ? maxIdx : i;
      offset += step;
    }
    return maxIdx;
  }

  static String userLevelToRank(int? userLevel) {
    if (_rankHierarchy.isEmpty) return 'beginner';
    return _rankHierarchy[userLevelToRankIndex(userLevel)];
  }

  /// Lifetime wins → user progression level (accelerating steps from catalog).
  static int winsToUserLevel(int? wins) {
    final w = wins == null ? 0 : (wins < 0 ? 0 : wins);
    if (_cumulativeWinsForUserLevel.length > 1) {
      for (var i = _cumulativeWinsForUserLevel.length - 1; i >= 0; i--) {
        if (w >= _cumulativeWinsForUserLevel[i]) {
          final lv = i + 1;
          return lv < userLevelMin ? userLevelMin : lv;
        }
      }
      return userLevelMin < 1 ? 1 : userLevelMin;
    }
    final step = winsPerUserLevel < 1 ? 1 : winsPerUserLevel;
    final lv = 1 + w ~/ step;
    return lv < userLevelMin ? userLevelMin : lv;
  }

  static List<int> _buildCumulativeWinsForUserLevel(List<int> steps) {
    final cum = <int>[0];
    var total = 0;
    for (final step in steps) {
      total += step < 1 ? 1 : step;
      cum.add(total);
    }
    return cum;
  }

  static void applyDocument(Map<String, dynamic>? doc) {
    if (doc == null || doc.isEmpty) {
      ensureBuiltinFallback();
      return;
    }
    final ranksRaw = doc['rank_hierarchy'];
    final ranks = <String>[];
    if (ranksRaw is List) {
      for (final e in ranksRaw) {
        final s = e.toString().trim().toLowerCase();
        if (s.isNotEmpty) ranks.add(s);
      }
    }
    if (ranks.isEmpty) {
      ensureBuiltinFallback();
      return;
    }

    final prog = doc['progression'];
    var defaultSpan = 5;
    if (prog is Map) {
      _userLevelMin = _readInt(prog['user_level_min'], _userLevelMin, min: 0);
      _winsPerUserLevel = _readInt(prog['wins_per_user_level'], _winsPerUserLevel, min: 1);
      defaultSpan = _readLevelsPerRankDefault(prog['levels_per_rank'], defaultSpan);
    }

    _rankHierarchy = ranks;
    _levelsPerRankSpans = _parseLevelsPerRankSpans(
      prog is Map ? prog['levels_per_rank'] : null,
      ranks,
      defaultSpan: defaultSpan,
    );

    if (prog is Map) {
      _applyWinsProgressionFromProg(prog, ranks);
    }

    final matchmaking = doc['rank_matchmaking'];
    if (matchmaking is Map) {
      _maxRankDelta = _readInt(matchmaking['max_rank_delta'], _maxRankDelta, min: 0);
    }

    _rankToDifficulty.clear();
    final rtd = doc['rank_to_difficulty'];
    if (rtd is Map) {
      for (final rank in ranks) {
        final d = rtd[rank]?.toString().trim().toLowerCase() ?? '';
        _rankToDifficulty[rank] = _validDifficulty(d) ? d : 'medium';
      }
    }
    for (final rank in ranks) {
      _rankToDifficulty.putIfAbsent(rank, () => _builtinRankToDifficulty[rank] ?? 'medium');
    }

    _hasServerDocument = true;
    changeVersion.value++;
  }

  static void ensureBuiltinFallback() {
    _rankHierarchy = List.from(_builtinRankHierarchy);
    _levelsPerRankSpans = List.filled(_builtinRankHierarchy.length, 5);
    _userLevelMin = 1;
    _winsPerUserLevel = 37;
    _winsPerLevelSteps = List.from(_builtinWinsPerLevelSteps);
    _cumulativeWinsForUserLevel = List.from(_builtinCumulativeWinsForUserLevel);
    _maxRankDelta = 1;
    _rankToDifficulty
      ..clear()
      ..addAll(_builtinRankToDifficulty);
    _hasServerDocument = false;
    changeVersion.value++;
  }

  static String rankToDifficulty(String normalizedRank) {
    if (normalizedRank.isEmpty) return 'medium';
    return _rankToDifficulty[normalizedRank] ??
        _builtinRankToDifficulty[normalizedRank] ??
        'medium';
  }

  static int _readLevelsPerRankDefault(dynamic raw, int fallback) {
    if (raw is int) return raw < 1 ? 1 : raw;
    if (raw is Map && raw.isNotEmpty) {
      final first = raw.values.first;
      return _readInt(first, fallback, min: 1);
    }
    return fallback;
  }

  static List<int> _parseLevelsPerRankSpans(
    dynamic raw,
    List<String> ranks, {
    required int defaultSpan,
  }) {
    final span = defaultSpan < 1 ? 1 : defaultSpan;
    if (raw is int) {
      final n = raw < 1 ? 1 : raw;
      return List.filled(ranks.length, n);
    }
    if (raw is Map) {
      return [
        for (final rank in ranks)
          _readInt(raw[rank], span, min: 1),
      ];
    }
    return List.filled(ranks.length, span);
  }

  static int _readInt(dynamic raw, int fallback, {required int min}) {
    if (raw is int) return raw < min ? min : raw;
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed == null) return fallback;
    return parsed < min ? min : parsed;
  }

  static bool _validDifficulty(String d) =>
      d == 'easy' || d == 'medium' || d == 'hard' || d == 'expert';

  static void _applyWinsProgressionFromProg(Map prog, List<String> ranks) {
    final maxUserLevel = _levelsPerRankSpans.fold<int>(
      0,
      (a, b) => a + (b < 1 ? 1 : b),
    );
    final expectedSteps = maxUserLevel > 1 ? maxUserLevel - 1 : 54;

    final cumRaw = prog['cumulative_wins_for_user_level'];
    if (cumRaw is List && cumRaw.isNotEmpty) {
      final parsed = <int>[];
      for (final item in cumRaw) {
        final n = item is int ? item : int.tryParse('$item');
        if (n != null && n >= 0) parsed.add(n);
      }
      if (parsed.isNotEmpty && parsed.first == 0) {
        _cumulativeWinsForUserLevel = parsed;
        if (parsed.length > 1) {
          _winsPerLevelSteps = [
            for (var i = 1; i < parsed.length; i++) parsed[i] - parsed[i - 1],
          ];
        }
        return;
      }
    }

    final stepsRaw = prog['wins_per_level_steps'];
    if (stepsRaw is List && stepsRaw.isNotEmpty) {
      final parsed = <int>[];
      for (final item in stepsRaw) {
        final n = item is int ? item : int.tryParse('$item');
        if (n != null && n >= 1) parsed.add(n);
      }
      if (parsed.length == expectedSteps) {
        _winsPerLevelSteps = parsed;
        _cumulativeWinsForUserLevel = _buildCumulativeWinsForUserLevel(parsed);
        return;
      }
    }

    _winsPerLevelSteps = List.from(_builtinWinsPerLevelSteps);
    _cumulativeWinsForUserLevel = List.from(_builtinCumulativeWinsForUserLevel);
  }
}
