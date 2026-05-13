// lib/config/config.dart

class Config {

  static const String appTitle = "Dutch";

  // API URL
  // Single source of truth – always use API_URL (set per launch config)
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:8081',
  );

  // API Key
  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: '',
  );

  // WebSocket URL for external app
  // Single source of truth – always use WS_URL (set per launch config)
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://127.0.0.1:8080', // Default to local Dart server
  );

  // HTTP Request Timeout Configuration
  static const int httpRequestTimeout = int.fromEnvironment(
    'HTTP_REQUEST_TIMEOUT',
    defaultValue: 600, // 10 minutes in seconds (for debugging)
  );

  // WebSocket Timeout Configuration
  static const int websocketTimeout = int.fromEnvironment(
    'WEBSOCKET_TIMEOUT',
    defaultValue: 5, // 5 seconds
  );

  // Token Refresh Wait Timeout Configuration
  static const int tokenRefreshWaitTimeout = int.fromEnvironment(
    'TOKEN_REFRESH_WAIT_TIMEOUT',
    defaultValue: 1, // 1 second
  );

  // JWT Configuration - Fallback values (will be overridden by backend TTL)
  static const int jwtAccessTokenExpiresFallback = int.fromEnvironment(
    'JWT_ACCESS_TOKEN_EXPIRES',
    defaultValue: 3600, // 1 hour in seconds - fallback only
  );

  static const int jwtRefreshTokenExpiresFallback = int.fromEnvironment(
    'JWT_REFRESH_TOKEN_EXPIRES',
    defaultValue: 604800, // 7 days in seconds - fallback only
  );

  // Removed JWT token refresh cooldown - no longer needed

  static const int jwtTokenRefreshInterval = int.fromEnvironment(
    'JWT_TOKEN_REFRESH_INTERVAL',
    defaultValue: 3600, // 1 hour in seconds
  );

  // Stripe Publishable Key
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  // AdMob IDs (override with --dart-define=ADMOBS_* for staging/other units).
  static const String admobsTopBanner = String.fromEnvironment(
    'ADMOBS_TOP_BANNER01',
    defaultValue: 'ca-app-pub-6524100109992126/3612268528',
  );
  static const String admobsBottomBanner = String.fromEnvironment(
    'ADMOBS_BOTTOM_BANNER01',
    defaultValue: 'ca-app-pub-6524100109992126/3612268528',
  );

  static const String admobsInterstitial01 = String.fromEnvironment(
    'ADMOBS_INTERSTITIAL01',
    defaultValue: '',
  );

  static const String admobsRewarded01 = String.fromEnvironment(
    'ADMOBS_REWARDED01',
    defaultValue: '',
  );

  /// [RequestConfiguration.tagForChildDirectedTreatment]: -1 unspecified, 0 false, 1 true.
  static const int admobTagForChildDirectedTreatment = int.fromEnvironment(
    'ADMOB_TAG_FOR_CHILD_DIRECTED_TREATMENT',
    defaultValue: -1,
  );

  /// [RequestConfiguration.tagForUnderAgeOfConsent]: -1 unspecified; 0/1 per Mobile Ads SDK docs.
  static const int admobTagForUnderAgeOfConsentRequest = int.fromEnvironment(
    'ADMOB_TAG_FOR_UNDER_AGE_OF_CONSENT_REQUEST',
    defaultValue: -1,
  );

  /// UMP [ConsentRequestParameters.tagForUnderAgeOfConsent] when in EEA.
  static const bool admobConsentTagUnderAgeOfConsent = bool.fromEnvironment(
    'ADMOB_CONSENT_TAG_UNDER_AGE_OF_CONSENT',
    defaultValue: false,
  );

  // Google Sign-In Client ID (Web)
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '907176907209-q53b29haj3t690ol7kbtqrqo0hkt9ku7.apps.googleusercontent.com',
  );

  // Google Sign-In Client ID (Android) - Separate OAuth 2.0 Client ID for Android
  static const String googleClientIdAndroid = String.fromEnvironment(
    'GOOGLE_CLIENT_ID_ANDROID',
    defaultValue: '907176907209-u7cjeiousj1dd460730rgspf05u0fhic.apps.googleusercontent.com',
  );

  // Diagnostics
  static const String platform = String.fromEnvironment('APP_PLATFORM', defaultValue: 'flutter');
  static const String buildMode = String.fromEnvironment('BUILD_MODE', defaultValue: 'debug');
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');

  // Dynamic Dutch tables config passed via --dart-define from root .env
  // Example:
  // {"1":{"title":"Home Table","coin_fee":25},"2":{"title":"Local Table","coin_fee":50}}
  static const String dutchTablesJson = String.fromEnvironment(
    'DUTCH_TABLES_JSON',
    defaultValue: '',
  );
}