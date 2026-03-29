import 'package:flutter/material.dart';

import '../../core/managers/hooks_manager.dart';
import '../../tools/logging/logger.dart';
import 'ad_registry.dart';
import 'route_path_utils.dart';

/// enable-logging-switch.mdc — set false after debugging.
const bool LOGGING_SWITCH = true;

/// Fires [switch_screen_ad] on real screen transitions only — not dialogs, sheets, or
/// other [PopupRoute]s. Those use [ModalRoute] branches that are not [PageRoute].
///
/// The interstitial runs only every [AdEventTypeConfig.showAfterScreenChanges] qualifying
/// [PageRoute] transitions (from YAML `switch_screen` type, default 3), not on every navigation.
class AdsSwitchScreenNavigatorObserver extends NavigatorObserver {
  static const int _defaultShowAfterScreenChanges = 3;

  static final Logger _logger = Logger();

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
    if (route is! PageRoute) {
      if (LOGGING_SWITCH) {
        _logger.info('AdsNavObserver: skip (not PageRoute)');
      }
      return;
    }
    final ctx = route.navigator?.context;
    if (ctx == null) {
      if (LOGGING_SWITCH) {
        _logger.info('AdsNavObserver: skip (no navigator context)');
      }
      return;
    }
    final cfg = AdRegistry.instance.typeById('switch_screen');
    final excludes = cfg?.excludeFromScreenChangeCount ?? const <String>[];
    if (excludes.isNotEmpty &&
        routeDestinationMatchesExcludeList(route, excludes)) {
      if (LOGGING_SWITCH) {
        _logger.info('AdsNavObserver: skip (destination in exclude list)');
      }
      return;
    }
    final need = _threshold();
    _screenChangeCount++;
    if (_screenChangeCount < need) {
      if (LOGGING_SWITCH) {
        _logger.info(
          'AdsNavObserver: screen change $_screenChangeCount/$need (need more before interstitial)',
        );
      }
      return;
    }
    _screenChangeCount = 0;
    if (LOGGING_SWITCH) {
      _logger.info('AdsNavObserver: firing switch_screen_ad hook');
    }
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
