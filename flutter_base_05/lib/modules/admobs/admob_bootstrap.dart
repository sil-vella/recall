import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../utils/consts/config.dart';
import 'admob_trace.dart';

bool _mobileAdsInitialized = false;

Future<void> _initializeMobileAdsSdk() async {
  if (_mobileAdsInitialized) {
    return;
  }
  await MobileAds.instance.initialize();
  const cdt = Config.admobTagForChildDirectedTreatment;
  const uac = Config.admobTagForUnderAgeOfConsentRequest;
  MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(
      tagForChildDirectedTreatment: cdt < 0 ? null : cdt,
      tagForUnderAgeOfConsent: uac < 0 ? null : uac,
    ),
  );
  _mobileAdsInitialized = true;
}

/// UMP consent update + optional form, then [MobileAds.instance.initialize] and request targeting.
/// No-op on web. Idempotent.
Future<void> bootstrapConsentAndMobileAds() async {
  if (kIsWeb) {
    return;
  }
  if (_mobileAdsInitialized) {
    return;
  }

  final done = Completer<void>();

  Future<void> completeChain() async {
    await _initializeMobileAdsSdk();
    if (!done.isCompleted) done.complete();
  }

  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(
      tagForUnderAgeOfConsent: Config.admobConsentTagUnderAgeOfConsent ? true : false,
    ),
    () {
      ConsentForm.loadAndShowConsentFormIfRequired((formError) {}).whenComplete(() {
        unawaited(completeChain());
      });
    },
    (error) {
      unawaited(completeChain());
    },
  );

  await done.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () async {
      await completeChain();
    },
  );
  admobTrace(
    'Bootstrap',
    'banner top len=${Config.admobsTopBanner.length} bottom len=${Config.admobsBottomBanner.length}',
  );
  admobTrace(
    'Bootstrap',
    'Android manifest APPLICATION_ID must match the same AdMob app as these ad unit ids.',
  );
}
