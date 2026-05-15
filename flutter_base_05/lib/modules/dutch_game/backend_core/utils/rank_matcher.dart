import '../../utils/progression_config_store.dart';

/// Rank matching utility for player compatibility checking.
class RankMatcher {
  /// Rank hierarchy in order from lowest to highest (from server catalog when hydrated).
  static List<String> get rankHierarchy => ProgressionConfigStore.rankHierarchy;

  /// Get rank index in hierarchy (0..n-1). Returns -1 if rank is not found.
  static int getRankIndex(String rank) {
    final normalized = normalizeRank(rank);
    return rankHierarchy.indexOf(normalized);
  }

  /// Check if two ranks are within configured delta (compatible).
  static bool areRanksCompatible(String? rank1, String? rank2) {
    if (rank1 == null || rank2 == null) {
      return false;
    }

    final index1 = getRankIndex(rank1);
    final index2 = getRankIndex(rank2);

    if (index1 == -1 || index2 == -1) {
      return false;
    }

    final difference = (index1 - index2).abs();
    return difference <= ProgressionConfigStore.maxRankDelta;
  }

  /// Get compatible ranks for a given rank (±delta).
  static List<String> getCompatibleRanks(String? rank) {
    if (rank == null) {
      return [];
    }

    final index = getRankIndex(rank);
    if (index == -1) {
      return [];
    }

    final delta = ProgressionConfigStore.maxRankDelta;
    final compatibleRanks = <String>[];

    for (var i = index - delta; i <= index + delta; i++) {
      if (i >= 0 && i < rankHierarchy.length) {
        compatibleRanks.add(rankHierarchy[i]);
      }
    }

    return compatibleRanks;
  }

  /// Normalize rank string (lowercase). Returns empty string if invalid.
  static String normalizeRank(String rank) {
    if (rank.isEmpty) {
      return '';
    }

    final normalized = rank.toLowerCase().trim();

    if (rankHierarchy.contains(normalized)) {
      return normalized;
    }

    return '';
  }

  static bool isValidRank(String? rank) {
    if (rank == null) {
      return false;
    }
    return getRankIndex(rank) != -1;
  }

  static String rankToDifficulty(String? rank) {
    if (rank == null) {
      return 'medium';
    }

    final normalizedRank = normalizeRank(rank);
    if (normalizedRank.isEmpty) {
      return 'medium';
    }

    return ProgressionConfigStore.rankToDifficulty(normalizedRank);
  }
}
