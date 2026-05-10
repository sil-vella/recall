import 'dart:io';

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../utils/consts/config.dart';
import 'store_config.dart';

/// RevenueCat SDK Configuration
/// This file contains the essential RevenueCat initialization logic
/// that can be integrated into your main app

Future<void> configureRevenueCatSDK() async {
  // Configure store based on platform
  if (kIsWeb) {
    // Web coin flow may use Stripe only; empty web key is allowed (RC paywall/web IAP need a key).
    StoreConfig(
      store: Store.rcBilling,
      apiKey: Config.revenueCatWebApiKey,
    );
  } else if (Platform.isIOS || Platform.isMacOS) {
    if (Config.revenueCatAppleApiKey.trim().isEmpty) {
      throw StateError(
        'RevenueCat: REVENUECAT_APPLE_API_KEY is empty. Add it to .env.local and pass via dart-defines.',
      );
    }
    StoreConfig(
      store: Store.appStore,
      apiKey: Config.revenueCatAppleApiKey,
    );
  } else if (Platform.isAndroid) {
    // Run the app passing --dart-define=AMAZON=true
    const useAmazon = bool.fromEnvironment("amazon");
    final apiKey = useAmazon ? Config.revenueCatAmazonApiKey : Config.revenueCatGoogleApiKey;
    if (apiKey.trim().isEmpty) {
      throw StateError(
        'RevenueCat: ${useAmazon ? "REVENUECAT_AMAZON_API_KEY" : "REVENUECAT_GOOGLE_API_KEY"} is empty. '
        'Native IAP requires the matching public SDK key from RevenueCat (dart-define from .env.local).',
      );
    }
    StoreConfig(
      store: useAmazon ? Store.amazon : Store.playStore,
      apiKey: apiKey,
    );
  } else {
    throw StateError('RevenueCat: unsupported platform ${Platform.operatingSystem}.');
  }

  await _configureSDK();
}

Future<void> _configureSDK() async {
  await Purchases.setLogLevel(LogLevel.warn);

  /*
    - appUserID is nil, so an anonymous ID will be generated automatically by the Purchases SDK. Read more about Identifying Users here: https://docs.revenuecat.com/docs/user-ids
    - RevenueCat automatically handles finishing transactions
    */
  PurchasesConfiguration configuration;
  if (StoreConfig.isForAmazonAppstore()) {
    configuration = AmazonConfiguration(StoreConfig.instance.apiKey)
      ..appUserID = null;
  } else {
    configuration = PurchasesConfiguration(StoreConfig.instance.apiKey)
      ..appUserID = null;
  }
  await Purchases.configure(configuration);
}
