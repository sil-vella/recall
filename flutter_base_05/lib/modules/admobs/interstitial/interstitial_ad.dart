import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';

class InterstitialAdModule extends ModuleBase {
  final String adUnitId;
  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;

  /// ✅ Constructor with module key and dependencies
  InterstitialAdModule(this.adUnitId) : super("admobs_interstitial_ad_module", dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    loadAd(); // Load ad on initialization
  }

  /// ✅ Loads the interstitial ad
  Future<void> loadAd() async {
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdReady = true;
        },
        onAdFailedToLoad: (error) {
          _isAdReady = false;
        },
      ),
    );
  }

  /// ✅ Shows the interstitial ad
  Future<void> showAd(BuildContext context) async {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      return;
    }

    if (_isAdReady && _interstitialAd != null) {
      _interstitialAd!.show();
      _interstitialAd = null;
      _isAdReady = false;

      // ✅ Save ad view count
      int adViews = sharedPref.getInt('interstitial_ad_views') ?? 0;
      sharedPref.setInt('interstitial_ad_views', adViews + 1);

      // ✅ Preload next ad
      loadAd();
    }
  }

  /// ✅ Disposes of the interstitial ad
  @override
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    super.dispose();
  }
}
