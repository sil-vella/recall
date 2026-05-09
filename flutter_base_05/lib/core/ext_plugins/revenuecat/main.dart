import 'dart:io';

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../tools/logging/logger.dart';
import '../../../utils/consts/config.dart';
import 'store_config.dart';

/// Set `true` to trace SDK configure / store selection (enable-logging-switch.mdc).
const bool LOGGING_SWITCH = false;

/// RevenueCat SDK Configuration
/// This file contains the essential RevenueCat initialization logic
/// that can be integrated into your main app

Future<void> configureRevenueCatSDK() async {
  final log = Logger();
  // Configure store based on platform
  if (kIsWeb) {
    if (LOGGING_SWITCH) {
      log.info('RevenueCatSDK: store=rcBilling web key configured=${Config.revenueCatWebApiKey.isNotEmpty}');
    }
    StoreConfig(
      store: Store.rcBilling,
      apiKey: Config.revenueCatWebApiKey,
    );
  } else if (Platform.isIOS || Platform.isMacOS) {
    if (LOGGING_SWITCH) {
      log.info('RevenueCatSDK: store=appStore apple key configured=${Config.revenueCatAppleApiKey.isNotEmpty}');
    }
    StoreConfig(
      store: Store.appStore,
      apiKey: Config.revenueCatAppleApiKey,
    );
  } else if (Platform.isAndroid) {
    // Run the app passing --dart-define=AMAZON=true
    const useAmazon = bool.fromEnvironment("amazon");
    if (LOGGING_SWITCH) {
      log.info(
        'RevenueCatSDK: store=${useAmazon ? "amazon" : "playStore"} '
        'key configured=${(useAmazon ? Config.revenueCatAmazonApiKey : Config.revenueCatGoogleApiKey).isNotEmpty}',
      );
    }
    StoreConfig(
      store: useAmazon ? Store.amazon : Store.playStore,
      apiKey: useAmazon
          ? Config.revenueCatAmazonApiKey
          : Config.revenueCatGoogleApiKey,
    );
  }

  await _configureSDK();
}

Future<void> _configureSDK() async {
  final log = Logger();
  await Purchases.setLogLevel(LOGGING_SWITCH ? LogLevel.debug : LogLevel.warn);
  if (LOGGING_SWITCH) {
    log.info('RevenueCatSDK: Purchases.configure starting (SDK logLevel=debug)');
  }

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
  if (LOGGING_SWITCH) {
    log.info('RevenueCatSDK: Purchases.configure completed');
  }
}
