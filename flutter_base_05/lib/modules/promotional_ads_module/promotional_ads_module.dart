import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/00_base/module_base.dart';
import '../../core/managers/app_manager.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../tools/logging/logger.dart';
import 'ad_registry.dart';
import 'models/ad_event_type_config.dart';
import 'models/ad_registration.dart';
import 'widgets/switch_screen_ad_overlay.dart';

/// Promotional ads (hooks + overlay). Config is loaded in [main] from the server or bundled YAML.
class PromotionalAdsModule extends ModuleBase {
  PromotionalAdsModule() : super('promotional_ads_module', dependencies: []);

  static final Logger _logger = Logger();
  /// enable-logging-switch.mdc — set false after debugging.
  static const bool LOGGING_SWITCH = true;

  static bool _switchOverlayOpen = false;

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    if (!StateManager().isModuleStateRegistered('promotional_ads')) {
      StateManager().registerModuleState('promotional_ads', <String, dynamic>{
        'bottom': null,
      });
    }

    final appManager = Provider.of<AppManager>(context, listen: false);
    final hooks = appManager.hooksManager;

    hooks.registerHookWithData('bottom_banner_bar_loaded', _onBottomBannerHook, priority: 20);
    hooks.registerHookWithData('switch_screen_ad', _onSwitchScreenHook, priority: 20);

    if (LOGGING_SWITCH) {
      _logger.info('PromotionalAdsModule: hooks registered');
    }
  }

  void _onBottomBannerHook(Map<String, dynamic> data) {
    final typeCfg = AdRegistry.instance.typeById('bottom_banner_promo');
    final source = (typeCfg?.bannerSwitch ?? 'sponsors').trim().toLowerCase();
    if (LOGGING_SWITCH) {
      _logger.info(
        'PromotionalAdsModule: bottom_banner_bar_loaded typeCfg=${typeCfg != null} switch=$source',
      );
    }
    if (source == 'admob' || source == 'admobs') {
      if (LOGGING_SWITCH) {
        _logger.info('PromotionalAdsModule: bottom strip skipped (AdMob path)');
      }
      StateManager().updateModuleState('promotional_ads', <String, dynamic>{
        'bottom': null,
      });
      return;
    }
    final ad = AdRegistry.instance.pickNextForType('bottom_banner_promo');
    if (ad == null) {
      if (LOGGING_SWITCH) {
        _logger.info('PromotionalAdsModule: no bottom_banner_promo ad in registry');
      }
      return;
    }
    if (LOGGING_SWITCH) {
      _logger.info('PromotionalAdsModule: bottom strip ad id=${ad.id} networkImg=${ad.networkImageUrl}');
    }
    StateManager().updateModuleState('promotional_ads', <String, dynamic>{
      'bottom': ad.toMap(),
    });
  }

  void _onSwitchScreenHook(Map<String, dynamic> data) {
    final ctx = data['context'];
    if (ctx is! BuildContext || !ctx.mounted) {
      if (LOGGING_SWITCH) {
        _logger.info('PromotionalAdsModule: switch_screen_ad skipped (no context)');
      }
      return;
    }
    if (_switchOverlayOpen) {
      if (LOGGING_SWITCH) {
        _logger.info('PromotionalAdsModule: switch_screen_ad skipped (overlay already open)');
      }
      return;
    }
    final AdEventTypeConfig? typeCfg = AdRegistry.instance.typeById('switch_screen');
    final AdRegistration? ad = AdRegistry.instance.pickNextForType('switch_screen');
    if (typeCfg == null || ad == null) {
      if (LOGGING_SWITCH) {
        _logger.info(
          'PromotionalAdsModule: switch_screen_ad no overlay typeCfg=$typeCfg ad=$ad',
        );
      }
      return;
    }
    if (LOGGING_SWITCH) {
      _logger.info(
        'PromotionalAdsModule: showing switch_screen overlay ad=${ad.id} delay=${typeCfg.delayBeforeSkipSeconds}',
      );
    }
    final delay = typeCfg.delayBeforeSkipSeconds ?? 0;

    // Showing a route/dialog from [NavigatorObserver.didPush] in the same synchronous
    // turn trips Navigator assertions (HeroControllerScope / navigator.dart ~5048).
    // Defer until after the push frame completes.
    _switchOverlayOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ctx.mounted) {
        _switchOverlayOpen = false;
        return;
      }
      SwitchScreenAdOverlay.show(
        ctx,
        ad: ad,
        delayBeforeSkipSeconds: delay,
      ).whenComplete(() {
        _switchOverlayOpen = false;
      });
    });
  }
}
