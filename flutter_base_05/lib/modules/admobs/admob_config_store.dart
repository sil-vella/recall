import 'package:flutter/foundation.dart';

import '../../../utils/consts/config.dart';
import '../../../utils/dev_logger.dart';

// ignore: constant_identifier_names — set false when not debugging AdMob remote config.
const bool LOGGING_SWITCH = true;

/// In-memory AdMob unit IDs and rewarded UI knobs from server init-config.
class AdmobConfigStore {
  AdmobConfigStore._();

  static final ValueNotifier<int> changeVersion = ValueNotifier<int>(0);

  static String _topBanner = Config.admobsTopBannerForPlatform;
  static String _bottomBanner = Config.admobsBottomBannerForPlatform;
  static String _interstitial = Config.admobsInterstitialForPlatform;
  static String _rewarded = Config.admobsRewardedForPlatform;
  static int _rewardedCoinsPerClaim = Config.admobRewardedCoinsPerClaim;
  static int _rewardedDailyCap = Config.admobRewardedDailyCap;

  static String get topBanner => _topBanner;
  static String get bottomBanner => _bottomBanner;
  static String get interstitial => _interstitial;
  static String get rewarded => _rewarded;
  static int get rewardedCoinsPerClaim => _rewardedCoinsPerClaim;
  static int get rewardedDailyCap => _rewardedDailyCap;

  static void ensureBuiltinFallback() {
    _topBanner = Config.admobsTopBannerForPlatform;
    _bottomBanner = Config.admobsBottomBannerForPlatform;
    _interstitial = Config.admobsInterstitialForPlatform;
    _rewarded = Config.admobsRewardedForPlatform;
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
    final platformDoc = _resolvePlatformDoc(doc);
    if (LOGGING_SWITCH) {
      customlog(
        'AdmobConfigStore: applyDocument platform=${defaultTargetPlatform.name} '
        'nestedIos=${doc['ios'] != null} nestedAndroid=${doc['android'] != null} '
        'flatLegacy=${doc.containsKey('top_banner')} resolvedKeys=${platformDoc.keys.toList()}',
      );
    }
    if (platformDoc.isEmpty) {
      if (LOGGING_SWITCH) {
        customlog('AdmobConfigStore: applyDocument skip — no platform block for this device');
      }
      return;
    }
    final top = platformDoc['top_banner']?.toString().trim();
    final bottom = platformDoc['bottom_banner']?.toString().trim();
    final interstitial = platformDoc['interstitial']?.toString().trim();
    final rewarded = platformDoc['rewarded']?.toString().trim();
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

  /// Picks `android` / `ios` nested block. Flat legacy docs apply on Android only.
  static Map<String, dynamic> _resolvePlatformDoc(Map<String, dynamic> doc) {
    if (kIsWeb) {
      return const <String, dynamic>{};
    }
    final platformKey =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    final nested = doc[platformKey];
    if (nested is Map<String, dynamic>) {
      return Map<String, dynamic>.from(nested);
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const <String, dynamic>{};
    }
    if (doc.containsKey('top_banner') ||
        doc.containsKey('bottom_banner') ||
        doc.containsKey('interstitial') ||
        doc.containsKey('rewarded')) {
      return Map<String, dynamic>.from(doc);
    }
    return const <String, dynamic>{};
  }

  /// True when prefs hold pre-platform-split flat doc (often Android/test ids).
  static bool isStaleFlatDocument(Map<String, dynamic> doc) {
    final hasNested = doc['ios'] is Map || doc['android'] is Map;
    if (hasNested) return false;
    return doc.containsKey('top_banner') ||
        doc.containsKey('bottom_banner') ||
        doc.containsKey('interstitial') ||
        doc.containsKey('rewarded');
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
