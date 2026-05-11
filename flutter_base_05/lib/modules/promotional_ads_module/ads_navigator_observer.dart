import 'package:flutter/material.dart';

import '../../core/managers/hooks_manager.dart';
import '../../utils/consts/config.dart';
import '../../utils/dbg.dart';
import '../admobs/ad_experience_policy.dart';
import 'ad_registry.dart';
import 'route_path_utils.dart';

/// Fires [switch_screen_ad] on real screen transitions only — not dialogs, sheets, or
/// other [PopupRoute]s. Those use [ModalRoute] branches that are not [PageRoute].
///
/// The interstitial runs only every [AdEventTypeConfig.showAfterScreenChanges] qualifying
/// [PageRoute] transitions (from YAML `switch_screen` type, default 3), not on every navigation.
class AdsSwitchScreenNavigatorObserver extends NavigatorObserver {
  static const int _defaultShowAfterScreenChanges = 3;

  static int _screenChangeCount = 0;

  int _threshold() {
    final cfg = AdRegistry.instance.typeById('switch_screen');
    final n = cfg?.showAfterScreenChanges;
    if (n == null || n < 1) {
      return _defaultShowAfterScreenChanges;
    }
    return n;
  }

  void _maybeFire(Route<dynamic> route) {
    if (Config.admobsInterstitial01.trim().isEmpty) {
      return;
    }
    if (!AdExperiencePolicy.showMonetizedAds) {
      dbgAdMob(
        'navObserver _maybeFire skip: ads off (${AdExperiencePolicy.monetizedAdsDebugLabel()})',
      );
      return;
    }
    if (route is! PageRoute) {
      dbgAdMob('navObserver _maybeFire skip: not PageRoute (${route.runtimeType})');
      return;
    }
    final ctx = route.navigator?.context;
    if (ctx == null) {
      dbgAdMob('navObserver _maybeFire skip: no navigator context');
      return;
    }
    final cfg = AdRegistry.instance.typeById('switch_screen');
    final excludes = cfg?.excludeFromScreenChangeCount ?? const <String>[];
    if (excludes.isNotEmpty &&
        routeDestinationMatchesExcludeList(route, excludes)) {
      dbgAdMob('navObserver _maybeFire skip: route excluded from count');
      return;
    }
    final need = _threshold();
    _screenChangeCount++;
    if (_screenChangeCount < need) {
      dbgAdMob('navObserver screen change $_screenChangeCount/$need (no hook yet)');
      return;
    }
    _screenChangeCount = 0;
    dbgAdMob('navObserver firing switch_screen_ad hook');
    HooksManager().triggerHookWithData('switch_screen_ad', {
      'context': ctx,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) {
      return;
    }
    _maybeFire(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) {
      return;
    }
    _maybeFire(newRoute);
  }
}
