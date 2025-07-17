// lib/config/config.dart

class Config {

  static const bool loggerOn = true;

  static const String appTitle = "recall";

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
    defaultValue: 'ws://10.0.2.2:8081',
  );

  // JWT Configuration
  static const int jwtAccessTokenExpires = int.fromEnvironment(
    'JWT_ACCESS_TOKEN_EXPIRES',
    defaultValue: 3600, // 1 hour in seconds
  );

  static const int jwtRefreshTokenExpires = int.fromEnvironment(
    'JWT_REFRESH_TOKEN_EXPIRES',
    defaultValue: 604800, // 7 days in seconds
  );

  static const int jwtTokenRefreshCooldown = int.fromEnvironment(
    'JWT_TOKEN_REFRESH_COOLDOWN',
    defaultValue: 300, // 5 minutes in seconds
  );

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
}