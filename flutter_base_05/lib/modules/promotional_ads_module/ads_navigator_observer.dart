import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/managers/navigation_manager.dart';
import '../../core/managers/hooks_manager.dart';
import '../../utils/consts/config.dart';
import '../admobs/ad_experience_policy.dart';
import 'ad_registry.dart';
import 'route_path_utils.dart';
import 'switch_screen_ad_excludes.dart';

/// Fires [switch_screen_ad] on real screen transitions only — not dialogs, sheets, or
/// other [PopupRoute]s. Those use [ModalRoute] branches that are not [PageRoute].
///
/// The interstitial runs only every [AdEventTypeConfig.showAfterScreenChanges] qualifying
/// [PageRoute] transitions (from YAML `switch_screen` type, default 3), not on every navigation.
class AdsSwitchScreenNavigatorObserver extends NavigatorObserver {
  static const int _defaultShowAfterScreenChanges = 3;
  static const Duration _gameplaySuppressDuration = Duration(seconds: 12);

  static int _screenChangeCount = 0;
  static DateTime? _suppressUntil;
  static String? _lastCountedPath;

  bool _isSuppressedNow() {
    final until = _suppressUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  int _threshold() {
    final cfg = AdRegistry.instance.typeById('switch_screen');
    final n = cfg?.showAfterScreenChanges;
    if (n == null || n < 1) {
      return _defaultShowAfterScreenChanges;
    }
    return n;
  }

  void _maybeFireResolvedPath({
    required BuildContext context,
    required String destinationPath,
  }) {
    if (Config.admobsInterstitial01.trim().isEmpty) {
      return;
    }
    if (_isSuppressedNow()) {
      return;
    }
    if (!AdExperiencePolicy.showMonetizedAds) {
      return;
    }
    final excludes = SwitchScreenAdExcludes.resolve();
    if (routeMatchesExcludeList(destinationPath, excludes)) {
      return;
    }
    // Avoid duplicate counting for the same settled path (multiple observer callbacks).
    if (_lastCountedPath == destinationPath) {
      return;
    }
    _lastCountedPath = destinationPath;
    final need = _threshold();
    _screenChangeCount++;
    if (_screenChangeCount < need) {
      return;
    }
    _screenChangeCount = 0;
    HooksManager().triggerHookWithData('switch_screen_ad', {
      'context': context,
      'destination_path': destinationPath,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _scheduleMaybeFire(Route<dynamic> route) {
    if (route is! PageRoute) {
      return;
    }
    final ctx = route.navigator?.context;
    if (ctx == null) {
      return;
    }
    // Count only after navigation settles and current route is known.
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      final settledPath = normalizeRoutePath(NavigationManager().getCurrentRoute());
      if (settledPath.isEmpty || settledPath == '/') {
        return;
      }
      if (routeMatchesExcludeList(settledPath, const ['/dutch/game-play*'])) {
        // Entering gameplay: deduct one from count (floor 0) and suppress race-triggered interstitials.
        if (_screenChangeCount > 0) {
          _screenChangeCount--;
        }
        _lastCountedPath = settledPath;
        _suppressUntil = DateTime.now().add(_gameplaySuppressDuration);
        return;
      }
      _maybeFireResolvedPath(
        context: ctx,
        destinationPath: settledPath,
      );
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) {
      return;
    }
    _scheduleMaybeFire(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) {
      return;
    }
    _scheduleMaybeFire(newRoute);
  }
}
