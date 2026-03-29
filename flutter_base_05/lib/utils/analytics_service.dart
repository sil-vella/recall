import 'package:firebase_analytics/firebase_analytics.dart';

import '../tools/logging/logger.dart';
import 'firebase_runtime_config.dart';

class AnalyticsService {
  static const bool LOGGING_SWITCH = false;

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// GA4 screen view (separate from custom [logEvent]).
  static Future<void> logScreenView(String screenName) async {
    if (!FirebaseRuntimeConfig.isEnabled) {
      return;
    }
    try {
      await _analytics.logScreenView(
        screenName: screenName,
        screenClass: screenName,
      );
      if (LOGGING_SWITCH) {
        Logger().info('AnalyticsService: logScreenView $screenName');
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        Logger().error(
          'AnalyticsService: logScreenView failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Clears analytics user id on logout when [id] is null.
  static Future<void> setUserId(String? id) async {
    if (!FirebaseRuntimeConfig.isEnabled) {
      return;
    }
    try {
      await _analytics.setUserId(id: id);
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        Logger().error(
          'AnalyticsService: setUserId failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  static Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    if (!FirebaseRuntimeConfig.isEnabled) {
      if (LOGGING_SWITCH) {
        Logger().info(
          'AnalyticsService: skipped event $name because FIREBASE_SWITCH=false',
        );
      }
      return;
    }

    try {
      final Map<String, Object> mergedParameters = <String, Object>{
        // App context (from FIREBASE_APP_* dart-defines / env). Do NOT use a `firebase_`
        // prefix here — GA4 rejects reserved prefixes and returns error 14.
        'app_environment': FirebaseRuntimeConfig.appEnvironment,
        'app_platform': FirebaseRuntimeConfig.appPlatform,
        // Keep passing through caller parameters next.
        if (parameters != null) ...parameters,
      };

      // GA4 debug flag: non-production only (`FIREBASE_APP_ENVIRONMENT` ≠ production).
      // Production → standard reports only; dev/staging → DebugView + same event params.
      if (FirebaseRuntimeConfig.includeAnalyticsDebugParameter &&
          !mergedParameters.containsKey('debug_mode')) {
        mergedParameters['debug_mode'] = 1;
      }

      await _analytics.logEvent(name: name, parameters: mergedParameters);
      if (LOGGING_SWITCH) {
        Logger().info(
          'AnalyticsService: logged event $name'
          ' params=$mergedParameters',
        );
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        Logger().error(
          'AnalyticsService: failed to log event $name',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }
}
