import 'dutch_achievement_catalog.dart';

/// Progress toward a locked achievement from user stats + catalog ``unlock`` rule.
class AchievementProgress {
  const AchievementProgress({
    required this.current,
    required this.required,
    required this.label,
  });

  final int current;
  final int required;
  final String label;

  double get fraction =>
      required > 0 ? (current / required).clamp(0.0, 1.0) : 0.0;

  bool get isComplete => required > 0 && current >= required;
}

/// Resolves display progress for an achievement row (null when unlocked or unknown rule).
AchievementProgress? achievementProgressFor({
  required DutchAchievementEntry entry,
  required bool unlocked,
  Map<String, dynamic>? stats,
}) {
  if (unlocked) return null;
  final unlock = entry.unlock;
  if (unlock == null || unlock.isEmpty) return null;

  final type = (unlock['type'] ?? '').toString().trim().toLowerCase();
  switch (type) {
    case 'win_streak':
      final required = _positiveInt(unlock['min'], fallback: 1);
      final current = _intFromStats(stats, 'win_streak_current');
      return AchievementProgress(
        current: current > required ? required : current,
        required: required,
        label: 'Win streak',
      );
    case 'total_wins':
      final required = _positiveInt(unlock['min'], fallback: 1);
      final current = _intFromStats(stats, 'wins');
      return AchievementProgress(
        current: current > required ? required : current,
        required: required,
        label: 'Total wins',
      );
    case 'event_win':
      final required = _positiveInt(unlock['min'], fallback: 1);
      final eventId = (unlock['special_event_id'] ?? '').toString().trim();
      final current = _specialEventWins(stats, eventId);
      return AchievementProgress(
        current: current > required ? required : current,
        required: required,
        label: 'Event wins',
      );
    case 'match_flag':
      return const AchievementProgress(
        current: 0,
        required: 1,
        label: 'Complete in a match',
      );
    default:
      return null;
  }
}

int _positiveInt(dynamic raw, {required int fallback}) {
  if (raw is int && raw >= 1) return raw;
  final parsed = int.tryParse('$raw');
  if (parsed != null && parsed >= 1) return parsed;
  return fallback;
}

int _intFromStats(Map<String, dynamic>? stats, String key) {
  if (stats == null) return 0;
  final v = stats[key];
  if (v is int) return v < 0 ? 0 : v;
  if (v is double) return v.round().clamp(0, 1 << 30);
  final parsed = int.tryParse(v?.toString() ?? '');
  if (parsed == null || parsed < 0) return 0;
  return parsed;
}

int _specialEventWins(Map<String, dynamic>? stats, String eventId) {
  if (stats == null || eventId.isEmpty) return 0;
  final raw = stats['special_event_wins'];
  if (raw is! Map) return 0;
  final v = raw[eventId];
  if (v is int) return v < 0 ? 0 : v;
  if (v is double) return v.round().clamp(0, 1 << 30);
  final parsed = int.tryParse(v?.toString() ?? '');
  if (parsed == null || parsed < 0) return 0;
  return parsed;
}
