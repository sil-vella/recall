import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../utils/consts/config.dart';
import '../../utils/dbg.dart';

bool _mobileAdsInitialized = false;

Future<void> _initializeMobileAdsSdk() async {
  if (_mobileAdsInitialized) {
    dbgAdMob('MobileAds.initialize skipped (already done)');
    return;
  }
  dbgAdMob('MobileAds.instance.initialize() …');
  await MobileAds.instance.initialize();
  const cdt = Config.admobTagForChildDirectedTreatment;
  const uac = Config.admobTagForUnderAgeOfConsentRequest;
  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(
      tagForChildDirectedTreatment: cdt < 0 ? null : cdt,
      tagForUnderAgeOfConsent: uac < 0 ? null : uac,
    ),
  );
  dbgAdMob(
    'RequestConfiguration updated (childDirected=$cdt underAgeConsentRequest=$uac)',
  );
  _mobileAdsInitialized = true;
  dbgAdMob('MobileAds SDK ready');
}

/// UMP consent update + optional form, then [MobileAds.instance.initialize] and request targeting.
/// No-op on web. Idempotent.
Future<void> bootstrapConsentAndMobileAds() async {
  if (kIsWeb) {
    dbgAdMob('bootstrapConsentAndMobileAds: skip (web)');
    return;
  }
  if (_mobileAdsInitialized) {
    dbgAdMob('bootstrapConsentAndMobileAds: skip (SDK already initialized)');
    return;
  }

  final done = Completer<void>();

  Future<void> completeChain() async {
    await _initializeMobileAdsSdk();
    if (!done.isCompleted) done.complete();
  }

  dbgAdMob(
    'UMP requestConsentInfoUpdate (tagUnderAgeOfConsent=${Config.admobConsentTagUnderAgeOfConsent})',
  );
  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(
      tagForUnderAgeOfConsent: Config.admobConsentTagUnderAgeOfConsent ? true : false,
    ),
    () {
      dbgAdMob('UMP consent info update success → loadAndShowConsentFormIfRequired');
      ConsentForm.loadAndShowConsentFormIfRequired((formError) {
        if (formError != null) {
          dbgAdMob('consent form callback', error: formError);
        } else {
          dbgAdMob('consent form callback (no error)');
        }
      }).whenComplete(() {
        dbgAdMob('consent form whenComplete → initialize SDK');
        unawaited(completeChain());
      });
    },
    (error) {
      dbgAdMob('UMP consent info update failed (continuing to SDK init)', error: error);
      unawaited(completeChain());
    },
  );

  await done.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () async {
      dbgAdMob('bootstrapConsentAndMobileAds: timeout 30s → forcing SDK init');
      await completeChain();
    },
  );
  dbgAdMob('bootstrapConsentAndMobileAds: finished');
}
