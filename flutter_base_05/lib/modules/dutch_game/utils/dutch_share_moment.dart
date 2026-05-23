/// Celebration context for native share-sheet copy and analytics.
enum DutchShareMoment {
  win,
  levelUp,
  rankUp,
}

extension DutchShareMomentAnalytics on DutchShareMoment {
  /// GA4-safe snake_case value for [AnalyticsService.logEvent].
  String get analyticsValue {
    switch (this) {
      case DutchShareMoment.win:
        return 'win';
      case DutchShareMoment.levelUp:
        return 'level_up';
      case DutchShareMoment.rankUp:
        return 'rank_up';
    }
  }
}
