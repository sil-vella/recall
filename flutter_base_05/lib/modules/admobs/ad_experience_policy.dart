import 'package:flutter/foundation.dart' show kIsWeb;

import '../dutch_game/utils/dutch_game_helpers.dart';

/// Central rules for when AdMob inventory may load or show.
///
/// **Premium** (`modules.dutch_game.subscription_tier` == `premium`): no banners,
/// interstitials, or rewarded flows. Evaluated from [StateManager] via [DutchGameHelpers]
/// so it updates after `fetchAndUpdateUserDutchGameData` without an app restart.
///
/// Web: always false (ads are not used on web).
abstract final class AdExperiencePolicy {
  /// Normalized subscription tier for logging (empty if unknown). Web: `web`.
  static String monetizedAdsDebugLabel() {
    if (kIsWeb) return 'web';
    final raw = DutchGameHelpers.getUserDutchGameStats()?['subscription_tier'];
    final t = (raw is String ? raw : raw?.toString())?.trim().toLowerCase() ?? '';
    return t.isEmpty ? 'tier=(empty)' : 'tier=$t';
  }

  /// True when we may load/show AdMob monetization on native (non-premium only).
  static bool get showMonetizedAds {
    if (kIsWeb) return false;
    final raw = DutchGameHelpers.getUserDutchGameStats()?['subscription_tier'];
    final t = (raw is String ? raw : raw?.toString())?.trim().toLowerCase() ?? '';
    return t != 'premium';
  }
}
