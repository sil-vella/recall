import 'achievements_catalog_store.dart';

/// Client-side Dutch achievements: titles/descriptions come from
/// [AchievementsCatalogStore] (hydrated from server `achievements_catalog` JSON).
class DutchAchievementCatalog {
  DutchAchievementCatalog._();

  static List<DutchAchievementEntry> get all {
    return AchievementsCatalogStore.rawEntries
        .map(
          (m) => DutchAchievementEntry(
            id: m['id'] ?? '',
            title: m['title'] ?? '',
            description: m['description'] ?? '',
          ),
        )
        .toList();
  }

  /// Resolved title for an achievement [id] (catalog or humanized fallback).
  static String displayTitle(String id) => AchievementsCatalogStore.displayTitle(id);
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
