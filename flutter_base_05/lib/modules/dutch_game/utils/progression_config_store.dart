import 'package:flutter/foundation.dart';

/// In-memory progression rules from server declarative catalog (hydrated from prefs / init).
class ProgressionConfigStore {
  ProgressionConfigStore._();

  static final ValueNotifier<int> changeVersion = ValueNotifier<int>(0);

  static List<String> _rankHierarchy = List.from(_builtinRankHierarchy);
  static List<int> _levelsPerRankSpans = List.filled(_builtinRankHierarchy.length, 5);
  static int _userLevelMin = 1;
  static int _winsPerUserLevel = 10;
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

  static List<String> get rankHierarchy => List.unmodifiable(_rankHierarchy);
  static List<int> get levelsPerRankSpans => List.unmodifiable(_levelsPerRankSpans);
  /// First rank span (legacy); prefer [levelsPerRankFor] or [levelsPerRankSpans].
  static int get levelsPerRank =>
      _levelsPerRankSpans.isEmpty ? 5 : _levelsPerRankSpans.first;
  static int get userLevelMin => _userLevelMin;
  static int get winsPerUserLevel => _winsPerUserLevel;
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
    _winsPerUserLevel = 10;
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
}
