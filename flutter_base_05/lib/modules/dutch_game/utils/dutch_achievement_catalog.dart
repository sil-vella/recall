/// Client-side catalog for Dutch achievements (ids must match Python
/// [ACHIEVEMENT_CATALOG] in `dutch_achievement_catalog.py`).
class DutchAchievementCatalog {
  DutchAchievementCatalog._();

  static const List<DutchAchievementEntry> all = [
    DutchAchievementEntry(
      id: 'win_streak_2',
      title: 'Hot hand',
      description: 'Win 2 matches in a row.',
    ),
    DutchAchievementEntry(
      id: 'win_streak_5',
      title: 'On a roll',
      description: 'Win 5 matches in a row.',
    ),
  ];
}

class DutchAchievementEntry {
  const DutchAchievementEntry({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;

  static DutchAchievementEntry? byId(String id) {
    for (final e in DutchAchievementCatalog.all) {
      if (e.id == id) return e;
    }
    return null;
  }
}
