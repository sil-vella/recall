import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/00_base/module_base.dart';
import '../../core/managers/app_manager.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/navigation_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../utils/consts/config.dart';
import '../admobs/ad_experience_policy.dart';
import '../admobs/interstitial/interstitial_ad.dart';
import 'route_path_utils.dart';
import 'switch_screen_ad_excludes.dart';

/// Promotional ads: navigation-gated AdMob interstitial (no custom pre-roll overlay).
class PromotionalAdsModule extends ModuleBase {
  PromotionalAdsModule() : super('promotional_ads_module', dependencies: []);

  static bool _interstitialShowInFlight = false;

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    if (!StateManager().isModuleStateRegistered('promotional_ads')) {
      StateManager().registerModuleState('promotional_ads', <String, dynamic>{});
    }

    final appManager = Provider.of<AppManager>(context, listen: false);
    final hooks = appManager.hooksManager;

    hooks.registerHookWithData('switch_screen_ad', _onSwitchScreenHook, priority: 20);
  }

  void _onSwitchScreenHook(Map<String, dynamic> data) {
    if (Config.admobsInterstitial01.trim().isEmpty) {
      return;
    }
    if (!AdExperiencePolicy.showMonetizedAds) {
      return;
    }
    final ctx = data['context'];
    if (ctx is! BuildContext || !ctx.mounted) {
      return;
    }
    if (_interstitialShowInFlight) {
      return;
    }
    final excludes = SwitchScreenAdExcludes.resolve();
    final destinationPath = data['destination_path']?.toString();
    if (routeMatchesExcludeList(destinationPath, excludes) ||
        routeMatchesExcludeList(destinationPath, const ['/dutch/game-play*'])) {
      return;
    }

    _interstitialShowInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ctx.mounted) {
        _interstitialShowInFlight = false;
        return;
      }
      final currentPath = NavigationManager().getCurrentRoute();
      if (routeMatchesExcludeList(currentPath, excludes) ||
          routeMatchesExcludeList(currentPath, const ['/dutch/game-play*'])) {
        _interstitialShowInFlight = false;
        return;
      }
      final mod = ModuleManager().getModuleByType<InterstitialAdModule>();
      if (mod == null || kIsWeb) {
        _interstitialShowInFlight = false;
        return;
      }
      mod.loadAd();
      mod.showOrFinish(ctx, () {
        _interstitialShowInFlight = false;
      });
    });
  }
}
