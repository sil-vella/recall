import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

class FirebaseRuntimeConfig {
  static const bool isEnabled =
      String.fromEnvironment('FIREBASE_SWITCH', defaultValue: 'true') == 'true';

  static const String appEnvironment = String.fromEnvironment(
    'FIREBASE_APP_ENVIRONMENT',
    defaultValue: 'development',
  );

  /// Whether this build is treated as **production** for Analytics tagging.
  ///
  /// [appEnvironment] comes from `--dart-define=FIREBASE_APP_ENVIRONMENT=...`
  /// (e.g. `development` in `.env.local`, `production` in `.env.prod`).
  static bool get isProductionAnalyticsEnvironment {
    final e = appEnvironment.toLowerCase().trim();
    return e == 'production' || e == 'prod';
  }

  /// When true, [AnalyticsService] adds GA4 `debug_mode` on events so they show in DebugView.
  /// **Production** builds omit it so traffic is normal dashboard reporting only.
  /// This is driven only by [appEnvironment], not app logging switches.
  static bool get includeAnalyticsDebugParameter =>
      !isProductionAnalyticsEnvironment;

  /// Returns one of: `web`, `android`, `ios`, or `other`.
  static String get appPlatform {
    if (kIsWeb) return 'web';
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.android) return 'android';
    if (platform == TargetPlatform.iOS) return 'ios';
    // For desktop/other: keep it generic.
    return platform.toString().replaceFirst('TargetPlatform.', '');
  }
}
