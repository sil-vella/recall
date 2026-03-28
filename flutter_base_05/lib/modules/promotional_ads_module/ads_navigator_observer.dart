import 'package:flutter/material.dart';

import '../../core/managers/hooks_manager.dart';

/// Fires [switch_screen_ad] after the first route (so cold start does not show an interstitial).
class AdsSwitchScreenNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) {
      return;
    }
    final ctx = route.navigator?.context;
    if (ctx == null) {
      return;
    }
    HooksManager().triggerHookWithData('switch_screen_ad', {
      'context': ctx,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
