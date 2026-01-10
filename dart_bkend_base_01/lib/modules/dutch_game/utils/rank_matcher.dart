/// Rank matching utility for player compatibility checking
class RankMatcher {
  /// Rank hierarchy in order from lowest to highest
  static const List<String> rankHierarchy = [
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

  /// Get rank index in hierarchy (0-9)
  /// Returns -1 if rank is not found
  static int getRankIndex(String rank) {
    final normalized = normalizeRank(rank);
    return rankHierarchy.indexOf(normalized);
  }

  /// Check if two ranks are within ±1 of each other (compatible)
  /// Returns true if ranks are compatible, false otherwise
  /// If either rank is null or invalid, returns false
  static bool areRanksCompatible(String? rank1, String? rank2) {
    if (rank1 == null || rank2 == null) {
      return false;
    }

    final index1 = getRankIndex(rank1);
    final index2 = getRankIndex(rank2);

    if (index1 == -1 || index2 == -1) {
      return false;
    }

    // Check if ranks are within ±1 of each other
    final difference = (index1 - index2).abs();
    return difference <= 1;
  }

  /// Get compatible ranks for a given rank (±1)
  /// Returns list of compatible ranks including the rank itself
  /// Returns empty list if rank is invalid
  static List<String> getCompatibleRanks(String? rank) {
    if (rank == null) {
      return [];
    }

    final index = getRankIndex(rank);
    if (index == -1) {
      return [];
    }

    final compatibleRanks = <String>[];
    
    // Add rank one below (if exists)
    if (index > 0) {
      compatibleRanks.add(rankHierarchy[index - 1]);
    }
    
    // Add the rank itself
    compatibleRanks.add(rankHierarchy[index]);
    
    // Add rank one above (if exists)
    if (index < rankHierarchy.length - 1) {
      compatibleRanks.add(rankHierarchy[index + 1]);
    }

    return compatibleRanks;
  }

  /// Normalize rank string (lowercase, handle variations)
  /// Returns normalized rank or empty string if invalid
  static String normalizeRank(String rank) {
    if (rank.isEmpty) {
      return '';
    }
    
    // Convert to lowercase and trim
    final normalized = rank.toLowerCase().trim();
    
    // Check if it's a valid rank
    if (rankHierarchy.contains(normalized)) {
      return normalized;
    }
    
    // Handle common variations
    final variations = {
      'beginner': 'beginner',
      'novice': 'novice',
      'apprentice': 'apprentice',
      'skilled': 'skilled',
      'advanced': 'advanced',
      'expert': 'expert',
      'veteran': 'veteran',
      'master': 'master',
      'elite': 'elite',
      'legend': 'legend',
    };
    
    return variations[normalized] ?? '';
  }

  /// Check if a rank is valid
  static bool isValidRank(String? rank) {
    if (rank == null) {
      return false;
    }
    return getRankIndex(rank) != -1;
  }
}
