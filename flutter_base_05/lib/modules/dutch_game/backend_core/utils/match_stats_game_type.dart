/// Resolves match rules variant for stats persistence: `classic` | `clear_and_collect`.
String matchStatsGameType({
  required Map<String, dynamic> gameState,
  Map<String, dynamic>? roomState,
}) {
  for (final source in [gameState, if (roomState != null) roomState]) {
    final rawType = source['gameType'] ?? source['game_type'];
    if (rawType != null) {
      final s = rawType.toString().trim().toLowerCase();
      if (s == 'clear_and_collect' || s == 'clearandcollect') {
        return 'clear_and_collect';
      }
      if (s == 'classic') {
        return 'classic';
      }
    }
  }
  for (final source in [gameState, if (roomState != null) roomState]) {
    final rawCc = source['isClearAndCollect'];
    if (rawCc is bool) {
      return rawCc ? 'clear_and_collect' : 'classic';
    }
    if (rawCc is String) {
      return rawCc.trim().toLowerCase() == 'true'
          ? 'clear_and_collect'
          : 'classic';
    }
  }
  return 'classic';
}
