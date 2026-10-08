import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android system UI for Dutch: keep the status bar (AppBar + AdMob close),
/// hide the navigation bar for full usable height.
///
/// Do not use [SystemUiMode.immersiveSticky] here — it hides the status bar,
/// leaves a strip of the Android window background at the top, and makes
/// interstitial/rewarded close controls untappable.
void applyAndroidImmersiveBottomBar() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const [SystemUiOverlay.top],
    );
  } catch (_) {
    // Best-effort; some embedders may not support manual UI mode.
  }
}

/// Show status + nav bars so AdMob fullscreen creatives can place a tappable close.
void restoreAndroidSystemUiForFullscreenAd() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  } catch (_) {
    // Best-effort.
  }
}
