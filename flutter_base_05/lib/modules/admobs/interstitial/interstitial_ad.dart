import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';

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
    loadAd();
  }

  /// Loads the next interstitial when the unit id is set (no-op on web or empty id).
  Future<void> loadAd() async {
    if (kIsWeb || adUnitId.trim().isEmpty) {
      return;
    }
    if (_interstitialAd != null) {
      return;
    }
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdReady = true;
        },
        onAdFailedToLoad: (_) {
          _interstitialAd = null;
          _isAdReady = false;
        },
      ),
    );
  }

  /// If an ad is ready, shows it and invokes [onClosed] after dismiss or show failure; otherwise [onClosed] runs immediately.
  void showOrFinish(BuildContext context, VoidCallback onClosed) {
    if (kIsWeb || adUnitId.trim().isEmpty || !isReady) {
      onClosed();
      return;
    }

    final ad = _interstitialAd!;
    _interstitialAd = null;
    _isAdReady = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
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
