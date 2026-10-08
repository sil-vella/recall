import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/managers/navigation_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/services/shared_preferences.dart';
import '../../utils/consts/theme_consts.dart';
import 'ad_experience_policy.dart';

/// After every [threshold] interstitial dismissals, offer Premium to remove ads.
class RemoveAdsOffer {
  RemoveAdsOffer._();

  static const String prefsKey = 'interstitial_ad_views';
  static const int threshold = 2;
  static bool _dialogInFlight = false;

  /// Call after an interstitial is dismissed (not on failed show).
  static Future<void> onInterstitialDismissed(BuildContext? hintContext) async {
    if (!AdExperiencePolicy.showMonetizedAds) return;

    final sharedPref = _sharedPref(hintContext);
    if (sharedPref == null) return;

    final views = (sharedPref.getInt(prefsKey) ?? 0) + 1;
    await sharedPref.setInt(prefsKey, views);
    if (views < threshold) return;

    await sharedPref.setInt(prefsKey, 0);
    await _showPrompt();
  }

  static SharedPrefManager? _sharedPref(BuildContext? hintContext) {
    for (final ctx in [hintContext, NavigationManager().navigatorKey.currentContext]) {
      if (ctx == null || !ctx.mounted) continue;
      try {
        final services = Provider.of<ServicesManager>(ctx, listen: false);
        final pref = services.getService<SharedPrefManager>('shared_pref');
        if (pref != null) return pref;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Future<void> _showPrompt() async {
    if (_dialogInFlight) return;
    final ctx = NavigationManager().navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    if (!AdExperiencePolicy.showMonetizedAds) return;

    _dialogInFlight = true;
    try {
      await showDialog<void>(
        context: ctx,
        useRootNavigator: true,
        barrierDismissible: true,
        builder: (dialogCtx) {
          return AlertDialog(
            backgroundColor: AppColors.scaffoldBackgroundColor.withValues(alpha: 0.95),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.accentContrast.withValues(alpha: 0.45)),
            ),
            title: Text(
              'Remove ads',
              style: AppTextStyles.headingSmall(color: AppColors.white).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              'Subscribe to Premium to play without interrupting ads.',
              style: AppTextStyles.bodyMedium(
                color: AppColors.white.withValues(alpha: 0.88),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                child: Text(
                  'Not now',
                  style: AppTextStyles.bodyMedium(color: AppColors.white),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  NavigationManager().navigateTo('/account');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentColor,
                  foregroundColor: AppColors.textOnAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'View Premium',
                  style: AppTextStyles.bodyMedium(color: AppColors.textOnAccent),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      _dialogInFlight = false;
    }
  }
}
