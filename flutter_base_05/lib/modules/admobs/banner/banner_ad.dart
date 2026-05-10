import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/hooks_manager.dart';
import '../../../../core/managers/app_manager.dart';
import '../../../../utils/consts/config.dart';
import '../../promotional_ads_module/ad_registry.dart';

bool _yamlBottomSlotIsAdmob() {
  final cfg = AdRegistry.instance.typeById('bottom_banner_promo');
  final s = (cfg?.bannerSwitch ?? 'sponsors').trim().toLowerCase();
  return s == 'admob' || s == 'admobs';
}

class BannerAdModule extends ModuleBase {
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
    
    // Register callbacks to global hooks
    _registerBannerCallbacks();
  }

  /// ✅ Register callbacks to global hooks
  void _registerBannerCallbacks() {
    // Register callback for top banner bar hook
    _hooksManager.registerHookWithData('top_banner_bar_loaded', (data) {
      // Load the top banner ad when global hook is triggered
      loadBannerAd(Config.admobsTopBanner);
    }, priority: 10); // Lower priority so it runs after the global hook
    
    // Register callback for bottom banner bar hook (only when YAML `switch` is admob — not sponsors strip).
    _hooksManager.registerHookWithData('bottom_banner_bar_loaded', (data) {
      if (!_yamlBottomSlotIsAdmob()) {
        return;
      }
      loadBannerAd(Config.admobsBottomBanner);
    }, priority: 10); // Lower priority so it runs after the global hook
    
  }

  /// ✅ Loads the banner ad with a specified ad unit ID
  Future<void> loadBannerAd(String adUnitId) async {
    if (_adLoaded[adUnitId] == true) {
      return; // ✅ Prevent reloading if already loaded
    }

    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _adLoaded[adUnitId] = true;
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
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
    if (_adLoaded[adUnitId] != true) {
      return const SizedBox.shrink();
    }

    // Create a new BannerAd instance for this widget
    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {},
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
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
    }
  }

  /// ✅ Override `dispose()` to clean up all banner ads
  @override
  void dispose() {
    for (final ad in _banners.values) {
      ad.dispose();
    }
    _banners.clear();
    _adLoaded.clear();
    super.dispose(); // ✅ Calls `ModuleBase.dispose()` for cleanup
  }
}
