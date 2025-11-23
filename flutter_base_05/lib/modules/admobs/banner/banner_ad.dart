import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/hooks_manager.dart';
import '../../../../core/managers/app_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/config.dart';

class BannerAdModule extends ModuleBase {
  static final Logger _logger = Logger();
  final Map<String, BannerAd> _banners = {};
  final Map<String, bool> _adLoaded = {};
  late HooksManager _hooksManager;

  /// ✅ Constructor with module key and dependencies
  BannerAdModule() : super("admobs_banner_ad_module", dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    
    // Get HooksManager from AppManager
    final appManager = Provider.of<AppManager>(context, listen: false);
    _hooksManager = appManager.hooksManager;
    
    _logger.info('📢 BannerAdModule initialized with context.');
    
    // Register callbacks to global hooks
    _registerBannerCallbacks();
  }

  /// ✅ Register callbacks to global hooks
  void _registerBannerCallbacks() {
    _logger.info('🔗 Registering banner ad callbacks to global hooks...');
    
    // Register callback for top banner bar hook
    _hooksManager.registerHookWithData('top_banner_bar_loaded', (data) {
      _logger.info('📢 Top banner bar callback triggered');
      // Load the top banner ad when global hook is triggered
      loadBannerAd(Config.admobsTopBanner);
    }, priority: 10); // Lower priority so it runs after the global hook
    
    // Register callback for bottom banner bar hook
    _hooksManager.registerHookWithData('bottom_banner_bar_loaded', (data) {
      _logger.info('📢 Bottom banner bar callback triggered');
      // Load the bottom banner ad when global hook is triggered
      loadBannerAd(Config.admobsBottomBanner);
    }, priority: 10); // Lower priority so it runs after the global hook
    
    _logger.info('✅ Banner ad callbacks registered to global hooks successfully');
  }

  /// ✅ Loads the banner ad with a specified ad unit ID
  Future<void> loadBannerAd(String adUnitId) async {
    if (_adLoaded[adUnitId] == true) {
      _logger.info('🔄 Banner Ad already loaded for ID: $adUnitId');
      return; // ✅ Prevent reloading if already loaded
    }

    _logger.info('📢 Loading Banner Ad for ID: $adUnitId');

    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _logger.info('✅ Banner Ad Loaded for ID: $adUnitId.');
          _adLoaded[adUnitId] = true;
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          _logger.error('❌ Failed to load Banner Ad for ID: $adUnitId. Error: ${error.message}');
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
    _logger.info('🔄 Creating new Banner Ad instance for Widget.');

    if (_adLoaded[adUnitId] != true) {
      _logger.error('❌ Banner Ad not loaded for ID: $adUnitId');
      return const SizedBox.shrink();
    }

    // Create a new BannerAd instance for this widget
    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => _logger.info('✅ New Banner Ad instance loaded for ID: $adUnitId.'),
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          _logger.error('❌ Failed to load new Banner Ad instance for ID: $adUnitId. Error: ${error.message}');
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

  /// ✅ Get top banner widget (hook callback)
  Widget getTopBannerWidget(BuildContext context) {
    return getBannerWidget(context, Config.admobsTopBanner);
  }

  /// ✅ Get bottom banner widget (hook callback)
  Widget getBottomBannerWidget(BuildContext context) {
    return getBannerWidget(context, Config.admobsBottomBanner);
  }

  /// ✅ Dispose a specific banner ad
  void disposeBannerAd(String adUnitId) {
    if (_banners.containsKey(adUnitId)) {
      _banners[adUnitId]?.dispose();
      _banners.remove(adUnitId);
      _adLoaded.remove(adUnitId);
      _logger.info('🗑 Banner Ad Disposed for ID: $adUnitId.');
    } else {
      _logger.error('⚠️ Tried to dispose non-existing Banner Ad for ID: $adUnitId.');
    }
  }

  /// ✅ Override `dispose()` to clean up all banner ads
  @override
  void dispose() {
    _logger.info('🗑 Disposing all Banner Ads...');
    for (final ad in _banners.values) {
      ad.dispose();
    }
    _banners.clear();
    _adLoaded.clear();
    super.dispose(); // ✅ Calls `ModuleBase.dispose()` for cleanup
  }
}
