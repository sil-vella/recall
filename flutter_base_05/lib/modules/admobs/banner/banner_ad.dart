import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../tools/logging/logger.dart';

class BannerAdModule extends ModuleBase {
  static final Logger _log = Logger();
  final Map<String, BannerAd> _banners = {};
  final Map<String, bool> _adLoaded = {};

  /// ✅ Constructor with module key and dependencies
  BannerAdModule() : super("admobs_banner_ad_module", dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _log.info('📢 BannerAdModule initialized with context.');
  }

  /// ✅ Loads the banner ad with a specified ad unit ID
  Future<void> loadBannerAd(String adUnitId) async {
    if (_adLoaded[adUnitId] == true) {
      _log.info('🔄 Banner Ad already loaded for ID: $adUnitId');
      return; // ✅ Prevent reloading if already loaded
    }

    _log.info('📢 Loading Banner Ad for ID: $adUnitId');

    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _log.info('✅ Banner Ad Loaded for ID: $adUnitId.');
          _adLoaded[adUnitId] = true;
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          _log.error('❌ Failed to load Banner Ad for ID: $adUnitId. Error: ${error.message}');
          ad.dispose();
          _adLoaded[adUnitId] = false;
        },
      ),
    );

    await bannerAd.load();
    _banners[adUnitId] = bannerAd;
  }

  /// ✅ Retrieve a new unique banner ad widget each time
  Widget getBannerWidget(BuildContext context, String adUnitId) {
    _log.info('🔄 Creating new Banner Ad instance for Widget.');

    if (_adLoaded[adUnitId] != true) {
      _log.error('❌ Banner Ad not loaded for ID: $adUnitId');
      return const SizedBox.shrink();
    }

    // Create a new BannerAd instance for this widget
    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => _log.info('✅ New Banner Ad instance loaded for ID: $adUnitId.'),
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          _log.error('❌ Failed to load new Banner Ad instance for ID: $adUnitId. Error: ${error.message}');
          ad.dispose();
        },
      ),
    );

    // Load the new instance
    bannerAd.load();

    return Container(
      key: ValueKey('banner_ad_${DateTime.now().millisecondsSinceEpoch}'),
      alignment: Alignment.center,
      width: bannerAd.size.width.toDouble(),
      height: bannerAd.size.height.toDouble(),
      child: AdWidget(ad: bannerAd),
    );
  }

  /// ✅ Dispose a specific banner ad
  void disposeBannerAd(String adUnitId) {
    if (_banners.containsKey(adUnitId)) {
      _banners[adUnitId]?.dispose();
      _banners.remove(adUnitId);
      _adLoaded.remove(adUnitId);
      _log.info('🗑 Banner Ad Disposed for ID: $adUnitId.');
    } else {
      _log.error('⚠️ Tried to dispose non-existing Banner Ad for ID: $adUnitId.');
    }
  }

  /// ✅ Override `dispose()` to clean up all banner ads
  @override
  void dispose() {
    _log.info('🗑 Disposing all Banner Ads...');
    for (final ad in _banners.values) {
      ad.dispose();
    }
    _banners.clear();
    _adLoaded.clear();
    super.dispose(); // ✅ Calls `ModuleBase.dispose()` for cleanup
  }
}
