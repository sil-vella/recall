import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/app_manager.dart';
import '../../../../core/managers/hooks_manager.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../utils/consts/config.dart';
import '../../../../utils/dbg.dart';
import '../ad_experience_policy.dart';

/// Loads banner units via hooks and displays the same [BannerAd] instance with [AdWidget].
class BannerAdModule extends ModuleBase {
  BannerAdModule() : super('admobs_banner_ad_module', dependencies: []);

  final Map<String, BannerAd?> _bannerByUnitId = <String, BannerAd?>{};
  final Set<String> _loadsInFlight = <String>{};
  final ValueNotifier<int> _frameTick = ValueNotifier<int>(0);

  void _notifyFrame() => _frameTick.value++;

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);

    final appManager = Provider.of<AppManager>(context, listen: false);
    _registerBannerCallbacks(appManager.hooksManager);
  }

  void _registerBannerCallbacks(HooksManager hooksManager) {
    hooksManager.registerHookWithData('top_banner_bar_loaded', (data) {
      loadBannerAd(Config.admobsTopBanner);
    }, priority: 10);

    hooksManager.registerHookWithData('bottom_banner_bar_loaded', (data) {
      if (kIsWeb) return;
      loadBannerAd(Config.admobsBottomBanner);
    }, priority: 10);
  }

  /// Preloads a banner for [adUnitId] (native only). Idempotent when already loaded.
  Future<void> loadBannerAd(String adUnitId) async {
    if (kIsWeb) {
      dbgAdMob('banner loadBannerAd skip: web');
      return;
    }
    if (adUnitId.trim().isEmpty) {
      dbgAdMob('banner loadBannerAd skip: empty adUnitId');
      return;
    }
    if (!AdExperiencePolicy.showMonetizedAds) {
      dbgAdMob(
        'banner loadBannerAd skip: monetized ads off (${AdExperiencePolicy.monetizedAdsDebugLabel()})',
      );
      return;
    }
    if (_bannerByUnitId[adUnitId] != null || _loadsInFlight.contains(adUnitId)) {
      dbgAdMob(
        'banner loadBannerAd skip: already loaded or in flight (inFlight=${_loadsInFlight.contains(adUnitId)})',
      );
      return;
    }
    _loadsInFlight.add(adUnitId);
    dbgAdMob('banner load start unitId=$adUnitId');

    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          final b = ad as BannerAd;
          dbgAdMob('banner onAdLoaded unitId=$adUnitId size=${b.size.width}x${b.size.height}');
          _bannerByUnitId[adUnitId] = b;
          _notifyFrame();
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          dbgAdMob(
            'banner onAdFailedToLoad unitId=$adUnitId code=${error.code} domain=${error.domain} message=${error.message}',
          );
          ad.dispose();
          _bannerByUnitId.remove(adUnitId);
          _notifyFrame();
        },
      ),
    );

    try {
      await bannerAd.load();
      dbgAdMob('banner load() completed unitId=$adUnitId');
    } finally {
      _loadsInFlight.remove(adUnitId);
    }
  }

  Widget _slotFor(BuildContext context, String adUnitId) {
    if (kIsWeb || adUnitId.trim().isEmpty || !AdExperiencePolicy.showMonetizedAds) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int>(
      valueListenable: _frameTick,
      builder: (_, __, ___) {
        final ad = _bannerByUnitId[adUnitId];
        if (ad == null) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        );
      },
    );
  }

  Widget getTopBannerWidget(BuildContext context) {
    return _slotFor(context, Config.admobsTopBanner);
  }

  Widget getBottomBannerWidget(BuildContext context) {
    return _slotFor(context, Config.admobsBottomBanner);
  }

  void disposeBannerAd(String adUnitId) {
    final ad = _bannerByUnitId.remove(adUnitId);
    ad?.dispose();
    _notifyFrame();
  }

  @override
  void dispose() {
    _loadsInFlight.clear();
    for (final ad in _bannerByUnitId.values) {
      ad?.dispose();
    }
    _bannerByUnitId.clear();
    _frameTick.dispose();
    super.dispose();
  }
}
