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
import '../admob_trace.dart';

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
    admobTrace(
      'Banner',
      'initialize module=$moduleKey showMonetizedAds=${AdExperiencePolicy.showMonetizedAds} '
      '${AdExperiencePolicy.monetizedAdsDebugLabel()}',
    );
    admobTrace(
      'Banner',
      'compile-time ADMOBS_TOP len=${Config.admobsTopBanner.length} '
      'ADMOBS_BOTTOM len=${Config.admobsBottomBanner.length} '
      '(empty top skips load; use Google sample IDs in .env.local for dev)',
    );
    _registerBannerCallbacks(appManager.hooksManager);
  }

  void _registerBannerCallbacks(HooksManager hooksManager) {
    hooksManager.registerHookWithData('top_banner_bar_loaded', (data) {
      admobTrace('Banner', 'hook top_banner_bar_loaded → loadBannerAd(top)');
      loadBannerAd(Config.admobsTopBanner);
    }, priority: 10);

    hooksManager.registerHookWithData('bottom_banner_bar_loaded', (data) {
      if (kIsWeb) return;
      admobTrace('Banner', 'hook bottom_banner_bar_loaded → loadBannerAd(bottom)');
      loadBannerAd(Config.admobsBottomBanner);
    }, priority: 10);
    admobTrace('Banner', 'registered top+bottom hooks (priority 10; AppManager stubs at 1)');
  }

  /// Preloads a banner for [adUnitId] (native only). Idempotent when already loaded.
  Future<void> loadBannerAd(String adUnitId) async {
    if (kIsWeb) {
      admobTrace('Banner', 'loadBannerAd skip: web');
      dbgAdMob('banner loadBannerAd skip: web');
      return;
    }
    if (adUnitId.trim().isEmpty) {
      admobTrace('Banner', 'loadBannerAd skip: empty adUnitId (check ADMOBS_TOP/BOTTOM dart-define)');
      dbgAdMob('banner loadBannerAd skip: empty adUnitId');
      return;
    }
    if (!AdExperiencePolicy.showMonetizedAds) {
      admobTrace(
        'Banner',
        'loadBannerAd skip: monetized ads off (${AdExperiencePolicy.monetizedAdsDebugLabel()})',
      );
      dbgAdMob(
        'banner loadBannerAd skip: monetized ads off (${AdExperiencePolicy.monetizedAdsDebugLabel()})',
      );
      return;
    }
    if (_bannerByUnitId[adUnitId] != null || _loadsInFlight.contains(adUnitId)) {
      admobTrace(
        'Banner',
        'loadBannerAd skip: already loaded or inFlight=${_loadsInFlight.contains(adUnitId)}',
      );
      dbgAdMob(
        'banner loadBannerAd skip: already loaded or in flight (inFlight=${_loadsInFlight.contains(adUnitId)})',
      );
      return;
    }
    _loadsInFlight.add(adUnitId);
    admobTrace(
      'Banner',
      'BannerAd.load() start unitId=$adUnitId size=AdSize.banner — '
      'Android app id must match this unit (local.properties admob.application_id)',
    );
    dbgAdMob('banner load start unitId=$adUnitId');

    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          final b = ad as BannerAd;
          admobTrace(
            'Banner',
            'onAdLoaded unitId=$adUnitId widget=${b.size.width}x${b.size.height}',
          );
          dbgAdMob('banner onAdLoaded unitId=$adUnitId size=${b.size.width}x${b.size.height}');
          _bannerByUnitId[adUnitId] = b;
          _notifyFrame();
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          admobTrace(
            'Banner',
            'onAdFailedToLoad unitId=$adUnitId code=${error.code} message=${error.message}',
          );
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
      admobTrace('Banner', 'await load() returned for unitId=$adUnitId (callbacks may still be pending)');
      dbgAdMob('banner load() completed unitId=$adUnitId');
    } finally {
      _loadsInFlight.remove(adUnitId);
    }
  }

  Widget _slotFor(BuildContext context, String adUnitId) {
    if (kIsWeb || adUnitId.trim().isEmpty || !AdExperiencePolicy.showMonetizedAds) {
      if (!kIsWeb && kDebugMode && adUnitId.trim().isEmpty) {
        admobTrace('Banner', '_slotFor shrink: empty unitId for this slot');
      }
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
