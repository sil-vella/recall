import 'package:flutter/foundation.dart';

import '../../../utils/consts/config.dart';
import '../../../utils/dev_logger.dart';

// ignore: constant_identifier_names — set false when not debugging AdMob remote config.
const bool LOGGING_SWITCH = true;

/// In-memory AdMob unit IDs and rewarded UI knobs from server init-config.
class AdmobConfigStore {
  AdmobConfigStore._();

  static final ValueNotifier<int> changeVersion = ValueNotifier<int>(0);

  static String _topBanner = Config.admobsTopBanner;
  static String _bottomBanner = Config.admobsBottomBanner;
  static String _interstitial = Config.admobsInterstitial01;
  static String _rewarded = Config.admobsRewarded01;
  static int _rewardedCoinsPerClaim = Config.admobRewardedCoinsPerClaim;
  static int _rewardedDailyCap = Config.admobRewardedDailyCap;

  static String get topBanner => _topBanner;
  static String get bottomBanner => _bottomBanner;
  static String get interstitial => _interstitial;
  static String get rewarded => _rewarded;
  static int get rewardedCoinsPerClaim => _rewardedCoinsPerClaim;
  static int get rewardedDailyCap => _rewardedDailyCap;

  static void ensureBuiltinFallback() {
    _topBanner = Config.admobsTopBanner;
    _bottomBanner = Config.admobsBottomBanner;
    _interstitial = Config.admobsInterstitial01;
    _rewarded = Config.admobsRewarded01;
    _rewardedCoinsPerClaim = Config.admobRewardedCoinsPerClaim;
    _rewardedDailyCap = Config.admobRewardedDailyCap;
    if (LOGGING_SWITCH) {
      customlog(
        'AdmobConfigStore: ensureBuiltinFallback top=$_topBanner interstitial=$_interstitial '
        'rewarded=$_rewarded coins=$_rewardedCoinsPerClaim cap=$_rewardedDailyCap',
      );
    }
  }

  static void applyDocument(Map<String, dynamic> doc) {
    final top = doc['top_banner']?.toString().trim();
    final bottom = doc['bottom_banner']?.toString().trim();
    final interstitial = doc['interstitial']?.toString().trim();
    final rewarded = doc['rewarded']?.toString().trim();
    final coinsRaw = doc['rewarded_coins_per_claim'];
    final capRaw = doc['rewarded_daily_cap'];

    var changed = false;
    if (top != null && top.isNotEmpty && top != _topBanner) {
      _topBanner = top;
      changed = true;
    }
    if (bottom != null && bottom.isNotEmpty && bottom != _bottomBanner) {
      _bottomBanner = bottom;
      changed = true;
    }
    if (interstitial != null && interstitial.isNotEmpty && interstitial != _interstitial) {
      _interstitial = interstitial;
      changed = true;
    }
    if (rewarded != null && rewarded.isNotEmpty && rewarded != _rewarded) {
      _rewarded = rewarded;
      changed = true;
    }
    final coins = _parsePositiveInt(coinsRaw);
    if (coins != null && coins != _rewardedCoinsPerClaim) {
      _rewardedCoinsPerClaim = coins;
      changed = true;
    }
    final cap = _parsePositiveInt(capRaw);
    if (cap != null && cap != _rewardedDailyCap) {
      _rewardedDailyCap = cap;
      changed = true;
    }
    if (changed) {
      changeVersion.value++;
      if (LOGGING_SWITCH) {
        customlog(
          'AdmobConfigStore: applyDocument changed changeVersion=${changeVersion.value} '
          'top=$_topBanner interstitial=$_interstitial rewarded=$_rewarded',
        );
      }
    } else if (LOGGING_SWITCH) {
      customlog('AdmobConfigStore: applyDocument no effective change');
    }
  }

  static int? _parsePositiveInt(dynamic raw) {
    if (raw is int) {
      return raw > 0 ? raw : null;
    }
    if (raw is num) {
      final v = raw.toInt();
      return v > 0 ? v : null;
    }
    if (raw is String) {
      final v = int.tryParse(raw.trim());
      return (v != null && v > 0) ? v : null;
    }
    return null;
  }
}
