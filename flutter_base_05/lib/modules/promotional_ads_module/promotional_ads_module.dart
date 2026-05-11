import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/00_base/module_base.dart';
import '../../core/managers/app_manager.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../utils/consts/config.dart';
import '../../utils/dbg.dart';
import '../admobs/ad_experience_policy.dart';
import 'ad_registry.dart';
import 'models/ad_event_type_config.dart';
import 'widgets/switch_screen_ad_overlay.dart';

/// Promotional ads: navigation-gated interstitial (AdMob) + shared [AdRegistry] from server/bundled YAML.
class PromotionalAdsModule extends ModuleBase {
  PromotionalAdsModule() : super('promotional_ads_module', dependencies: []);

  static bool _switchOverlayOpen = false;

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
    dbgAdMob('promotional switch_screen_ad hook fired');
    if (Config.admobsInterstitial01.trim().isEmpty) {
      dbgAdMob('promotional switch_screen_ad skip: no interstitial unit (ADMOBS_INTERSTITIAL01)');
      return;
    }
    if (!AdExperiencePolicy.showMonetizedAds) {
      dbgAdMob(
        'promotional switch_screen_ad skip: ${AdExperiencePolicy.monetizedAdsDebugLabel()}',
      );
      return;
    }
    final ctx = data['context'];
    if (ctx is! BuildContext || !ctx.mounted) {
      dbgAdMob('promotional switch_screen_ad skip: bad or unmounted context');
      return;
    }
    if (_switchOverlayOpen) {
      dbgAdMob('promotional switch_screen_ad skip: overlay already open');
      return;
    }
    final AdEventTypeConfig? typeCfg = AdRegistry.instance.typeById('switch_screen');
    if (typeCfg == null) {
      dbgAdMob('promotional switch_screen_ad skip: no switch_screen in AdRegistry');
      return;
    }

    final delay = typeCfg.delayBeforeSkipSeconds ?? 0;

    _switchOverlayOpen = true;
    dbgAdMob('promotional opening SwitchScreenAdOverlay delayBeforeSkipSeconds=$delay');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ctx.mounted) {
        dbgAdMob('promotional overlay postFrame: context unmounted');
        _switchOverlayOpen = false;
        return;
      }
      SwitchScreenAdOverlay.show(
        ctx,
        delayBeforeSkipSeconds: delay,
      ).whenComplete(() {
        dbgAdMob('promotional SwitchScreenAdOverlay closed');
        _switchOverlayOpen = false;
      });
    });
  }
}
