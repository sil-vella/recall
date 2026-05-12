import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/00_base/module_base.dart';
import '../../../core/managers/module_manager.dart';
import '../../../utils/consts/config.dart';
import 'ad_experience_policy.dart';
import 'admob_trace.dart';
import 'banner/banner_ad.dart';

/// Central coordinator for AdMob preload (same role as FMIF `AdvertsPlugin._preLoadAds`).
///
/// Runs after [BannerAdModule], [InterstitialAdModule], and [RewardedAdModule] are
/// registered (see [moduleDependencies]). Interstitial/rewarded already call
/// [InterstitialAdModule.loadAd] / [RewardedAdModule.loadAd] in their own
/// [initialize]; this module eagerly preloads top/bottom banners so the first
/// frame does not depend only on [BaseScreen] hook timing.
class AdvertsModule extends ModuleBase {
  AdvertsModule()
      : super(
          'adverts_module',
          dependencies: const [
            'admobs_banner_ad_module',
            'admobs_interstitial_ad_module',
            'admobs_rewarded_ad_module',
          ],
        );

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    admobTrace('Adverts', 'initialize coordinator');
    if (kIsWeb) return;
    if (!AdExperiencePolicy.showMonetizedAds) {
      admobTrace('Adverts', 'skip preload: monetized ads off');
      return;
    }
    final banner = moduleManager.getModuleByType<BannerAdModule>();
    if (banner == null) {
      admobTrace('Adverts', 'no BannerAdModule instance');
      return;
    }
    admobTrace('Adverts', 'preload banners top+bottom');
    banner.loadBannerAd(Config.admobsTopBanner, slot: 'top');
    banner.loadBannerAd(Config.admobsBottomBanner, slot: 'bottom');
  }
}
