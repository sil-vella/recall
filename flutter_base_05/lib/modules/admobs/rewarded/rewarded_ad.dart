import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../utils/dbg.dart';
import '../ad_experience_policy.dart';

/// Rewarded AdMob unit: preload, [isReady], [showAd] with earn + dismiss callbacks.
class RewardedAdModule extends ModuleBase {
  RewardedAdModule(this.adUnitId) : super('admobs_rewarded_ad_module', dependencies: []);

  final String adUnitId;
  RewardedAd? _rewardedAd;
  bool _isAdReady = false;

  /// Bumps when load state changes so UI can enable/disable the watch-ad control.
  final ValueNotifier<int> stateTick = ValueNotifier<int>(0);

  void _bump() => stateTick.value++;

  bool get isReady =>
      !kIsWeb &&
      adUnitId.trim().isNotEmpty &&
      AdExperiencePolicy.showMonetizedAds &&
      _isAdReady &&
      _rewardedAd != null;

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    loadAd();
  }

  /// Preloads the next rewarded ad (no-op on web or empty unit id).
  Future<void> loadAd() async {
    if (kIsWeb) {
      dbgAdMob('rewarded loadAd skip: web');
      await _rewardedAd?.dispose();
      _rewardedAd = null;
      _isAdReady = false;
      _bump();
      return;
    }
    if (adUnitId.trim().isEmpty) {
      dbgAdMob('rewarded loadAd skip: empty adUnitId');
      await _rewardedAd?.dispose();
      _rewardedAd = null;
      _isAdReady = false;
      _bump();
      return;
    }
    if (!AdExperiencePolicy.showMonetizedAds) {
      dbgAdMob(
        'rewarded loadAd skip: ${AdExperiencePolicy.monetizedAdsDebugLabel()}',
      );
      await _rewardedAd?.dispose();
      _rewardedAd = null;
      _isAdReady = false;
      _bump();
      return;
    }

    await _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdReady = false;
    _bump();

    dbgAdMob('rewarded RewardedAd.load start unitId=$adUnitId');
    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          dbgAdMob('rewarded onAdLoaded unitId=$adUnitId');
          _rewardedAd = ad;
          _isAdReady = true;
          _bump();
        },
        onAdFailedToLoad: (LoadAdError error) {
          dbgAdMob(
            'rewarded onAdFailedToLoad code=${error.code} domain=${error.domain} message=${error.message}',
          );
          _rewardedAd = null;
          _isAdReady = false;
          _bump();
        },
      ),
    );
  }

  /// Shows the rewarded ad. [onUserEarnedReward] runs when the SDK reports a reward (before dismiss).
  /// [onAdClosed] runs after dismiss or failed show, or immediately if not ready.
  Future<void> showAd(
    BuildContext context, {
    required VoidCallback onUserEarnedReward,
    VoidCallback? onAdClosed,
  }) async {
    if (kIsWeb || adUnitId.trim().isEmpty || !AdExperiencePolicy.showMonetizedAds) {
      dbgAdMob(
        'rewarded showAd no-op (web=$kIsWeb empty=${adUnitId.trim().isEmpty} policy=${AdExperiencePolicy.showMonetizedAds})',
      );
      onAdClosed?.call();
      return;
    }

    final sharedPref = _sharedPrefOrNull(context);
    if (!isReady || _rewardedAd == null) {
      dbgAdMob('rewarded showAd not ready → onAdClosed + reload');
      onAdClosed?.call();
      unawaited(loadAd());
      return;
    }

    final ad = _rewardedAd!;
    _rewardedAd = null;
    _isAdReady = false;
    _bump();

    final completer = Completer<void>();

    dbgAdMob('rewarded show()');
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (Ad a) {
        dbgAdMob('rewarded onAdShowedFullScreenContent');
      },
      onAdDismissedFullScreenContent: (Ad dismissed) {
        dbgAdMob('rewarded onAdDismissedFullScreenContent');
        dismissed.dispose();
        unawaited(loadAd());
        if (!completer.isCompleted) completer.complete();
        onAdClosed?.call();
      },
      onAdFailedToShowFullScreenContent: (Ad failed, AdError error) {
        dbgAdMob(
          'rewarded onAdFailedToShowFullScreenContent code=${error.code} domain=${error.domain} message=${error.message}',
        );
        failed.dispose();
        unawaited(loadAd());
        if (!completer.isCompleted) completer.complete();
        onAdClosed?.call();
      },
    );

    ad.show(
      onUserEarnedReward: (AdWithoutView adView, RewardItem reward) {
        dbgAdMob('rewarded onUserEarnedReward type=${reward.type} amount=${reward.amount}');
        onUserEarnedReward();
        _recordRewardViewBestEffort(sharedPref);
      },
    );

    await completer.future;
  }

  SharedPrefManager? _sharedPrefOrNull(BuildContext context) {
    try {
      final servicesManager = Provider.of<ServicesManager>(context, listen: false);
      return servicesManager.getService<SharedPrefManager>('shared_pref');
    } catch (_) {
      return null;
    }
  }

  void _recordRewardViewBestEffort(SharedPrefManager? sharedPref) {
    if (sharedPref == null) return;
    try {
      final rewardedViews = sharedPref.getInt('rewarded_ad_views') ?? 0;
      sharedPref.setInt('rewarded_ad_views', rewardedViews + 1);
    } catch (_) {}
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdReady = false;
    stateTick.dispose();
    super.dispose();
  }
}
