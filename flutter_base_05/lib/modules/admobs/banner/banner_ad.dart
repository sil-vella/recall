import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/app_manager.dart';
import '../../../../core/managers/hooks_manager.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../utils/consts/config.dart';

class BannerAdModule extends ModuleBase {
  final Map<String, BannerAd> _banners = {};
  final Map<String, bool> _adLoaded = {};
  late HooksManager _hooksManager;

  BannerAdModule() : super('admobs_banner_ad_module', dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);

    final appManager = Provider.of<AppManager>(context, listen: false);
    _hooksManager = appManager.hooksManager;

    _registerBannerCallbacks();
  }

  void _registerBannerCallbacks() {
    _hooksManager.registerHookWithData('top_banner_bar_loaded', (data) {
      loadBannerAd(Config.admobsTopBanner);
    }, priority: 10);

    _hooksManager.registerHookWithData('bottom_banner_bar_loaded', (data) {
      if (kIsWeb) return;
      loadBannerAd(Config.admobsBottomBanner);
    }, priority: 10);
  }

  Future<void> loadBannerAd(String adUnitId) async {
    if (kIsWeb || adUnitId.trim().isEmpty) {
      return;
    }
    if (_adLoaded[adUnitId] == true) {
      return;
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

  Widget getBannerWidget(BuildContext context, String adUnitId) {
    if (kIsWeb || adUnitId.trim().isEmpty || _adLoaded[adUnitId] != true) {
      return const SizedBox.shrink();
    }

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

    bannerAd.load();

    return Container(
      key: ValueKey('banner_ad_${DateTime.now().millisecondsSinceEpoch}'),
      alignment: Alignment.center,
      width: bannerAd.size.width.toDouble(),
      height: bannerAd.size.height.toDouble(),
      child: AdWidget(ad: bannerAd),
    );
  }

  Widget getTopBannerWidget(BuildContext context) {
    return getBannerWidget(context, Config.admobsTopBanner);
  }

  Widget getBottomBannerWidget(BuildContext context) {
    return getBannerWidget(context, Config.admobsBottomBanner);
  }

  void disposeBannerAd(String adUnitId) {
    if (_banners.containsKey(adUnitId)) {
      _banners[adUnitId]?.dispose();
      _banners.remove(adUnitId);
      _adLoaded.remove(adUnitId);
    }
  }

  @override
  void dispose() {
    for (final ad in _banners.values) {
      ad.dispose();
    }
    _banners.clear();
    _adLoaded.clear();
    super.dispose();
  }
}
