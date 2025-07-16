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