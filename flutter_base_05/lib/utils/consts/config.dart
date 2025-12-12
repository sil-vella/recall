// lib/config/config.dart

class Config {

  static const bool loggerOn = true;

  static const String appTitle = "Cleco";

  // API URL
  static const String apiUrl = String.fromEnvironment(
    'API_URL_LOCAL',
    defaultValue: 'http://10.0.2.2:8081',
  );

  // API Key
  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: '',
  );

  // WebSocket URL for external app
  static const String wsUrl = String.fromEnvironment(
    'WS_URL_LOCAL',
    defaultValue: 'ws://127.0.0.1:8080', // Changed from 8081 to 8080 (Dart server)
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

  // AdMob IDs
  static const String admobsTopBanner = String.fromEnvironment(
    'ADMOBS_TOP_BANNER01',
    defaultValue: '',
  );
  // AdMob IDs
  static const String admobsBottomBanner = String.fromEnvironment(
    'ADMOBS_BOTTOM_BANNER01',
    defaultValue: '',
  );

  static const String admobsInterstitial01 = String.fromEnvironment(
    'ADMOBS_INTERSTITIAL01',
    defaultValue: '',
  );

  static const String admobsRewarded01 = String.fromEnvironment(
    'ADMOBS_REWARDED01',
    defaultValue: '',
  );

  // Remote logging toggle
  static const bool enableRemoteLogging = bool.fromEnvironment(
    'ENABLE_REMOTE_LOGGING',
    defaultValue: true,
  );

  // Google Sign-In Client ID (Web)
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '907176907209-q53b29haj3t690ol7kbtqrqo0hkt9ku7.apps.googleusercontent.com',
  );

  // Diagnostics
  static const String platform = String.fromEnvironment('APP_PLATFORM', defaultValue: 'flutter');
  static const String buildMode = String.fromEnvironment('BUILD_MODE', defaultValue: 'debug');
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');
}