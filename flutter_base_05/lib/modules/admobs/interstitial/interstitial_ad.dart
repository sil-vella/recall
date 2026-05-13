import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../ad_experience_policy.dart';
import '../admob_trace.dart';

/// Preloads and shows AdMob interstitials (e.g. after navigation gate in [PromotionalAdsModule]).
class InterstitialAdModule extends ModuleBase {
  InterstitialAdModule(this.adUnitId) : super('admobs_interstitial_ad_module', dependencies: []);

  final String adUnitId;
  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;

  bool get isReady => _isAdReady && _interstitialAd != null;

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    if (adUnitId.trim().isEmpty) {
      admobTrace('Interstitial', 'initialize: empty adUnitId — skip loadAd()');
      return;
    }
    loadAd();
  }

  /// Loads the next interstitial when the unit id is set (no-op on web or empty id).
  Future<void> loadAd() async {
    if (kIsWeb) {
      return;
    }
    if (adUnitId.trim().isEmpty) {
      await _interstitialAd?.dispose();
      _interstitialAd = null;
      _isAdReady = false;
      return;
    }
    if (!AdExperiencePolicy.showMonetizedAds) {
      await _interstitialAd?.dispose();
      _interstitialAd = null;
      _isAdReady = false;
      return;
    }
    if (_isAdReady && _interstitialAd != null) {
      return;
    }

    await _interstitialAd?.dispose();
    _interstitialAd = null;
    _isAdReady = false;

    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdReady = true;
        },
        onAdFailedToLoad: (LoadAdError error) {
          _interstitialAd = null;
          _isAdReady = false;
        },
      ),
    );
  }

  /// If an ad is ready, shows it and invokes [onClosed] after dismiss or show failure; otherwise [onClosed] runs immediately.
  void showOrFinish(BuildContext context, VoidCallback onClosed) {
    if (kIsWeb || adUnitId.trim().isEmpty || !AdExperiencePolicy.showMonetizedAds || !isReady) {
      onClosed();
      return;
    }

    final ad = _interstitialAd!;
    _interstitialAd = null;
    _isAdReady = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (Ad a) {},
      onAdDismissedFullScreenContent: (Ad dismissed) {
        dismissed.dispose();
        _recordViewBestEffort(context);
        loadAd();
        onClosed();
      },
      onAdFailedToShowFullScreenContent: (Ad failed, AdError error) {
        failed.dispose();
        loadAd();
        onClosed();
      },
    );

    ad.show();
  }

  void _recordViewBestEffort(BuildContext context) {
    try {
      final servicesManager = Provider.of<ServicesManager>(context, listen: false);
      final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');
      if (sharedPref == null) return;
      final adViews = sharedPref.getInt('interstitial_ad_views') ?? 0;
      sharedPref.setInt('interstitial_ad_views', adViews + 1);
    } catch (_) {
      // Optional analytics
    }
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isAdReady = false;
    super.dispose();
  }
}
