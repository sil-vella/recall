import 'achievements_catalog_store.dart';

/// Client-side Dutch achievements: titles/descriptions come from
/// [AchievementsCatalogStore] (hydrated from server `achievements_catalog` JSON).
class DutchAchievementCatalog {
  DutchAchievementCatalog._();

  static List<DutchAchievementEntry> get all {
    return AchievementsCatalogStore.rawEntries
        .map(
          (m) => DutchAchievementEntry(
            id: m['id']?.toString() ?? '',
            title: m['title']?.toString() ?? '',
            description: m['description']?.toString() ?? '',
            unlock: m['unlock'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(m['unlock'] as Map)
                : null,
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
    this.unlock,
  });

  final String id;
  final String title;
  final String description;
  final Map<String, dynamic>? unlock;

  static DutchAchievementEntry? byId(String id) {
    for (final e in DutchAchievementCatalog.all) {
      if (e.id == id) return e;
    }
    return null;
  }
}
