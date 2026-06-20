import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/app_manager.dart';
import '../../../../core/managers/hooks_manager.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../utils/consts/config.dart';
import '../ad_experience_policy.dart';
import '../admob_trace.dart';

/// Loads banner units and displays each slot with its own [BannerAd] + [AdWidget].
///
/// Each visible slot uses a unique [hostKey] ([UniqueKey] per [BaseScreenState]).
/// One host loads exactly one [BannerAd] once; never share an ad across two [AdWidget]s.
///
/// Banners use [AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize] so they span
/// the available width (not sure edge on phones/tablets).
class BannerAdModule extends ModuleBase {
  BannerAdModule() : super('admobs_banner_ad_module', dependencies: []);

  /// Typical phone width (dp) for optional SDK warm-up when layout width is unknown.
  static const int warmupAnchorWidthDp = 360;

  static String storageKey(String slot, String adUnitId) =>
      '$slot|${adUnitId.trim()}';

  static String _hostLoadKey(String slot, String adUnitId, Key hostKey) =>
      '${storageKey(slot, adUnitId)}|host:${hostKey.hashCode}';

  static final Set<String> _diagOnce = <String>{};

  static void _diagOnceLog(String key, String message) {
    if (_diagOnce.add(key)) {
      admobTrace('Banner', message);
    }
  }

  /// Anchored adaptive size for [anchorWidthDp] (logical px); falls back to [AdSize.banner].
  static Future<AdSize> adaptiveSizeForWidth(int anchorWidthDp) async {
    if (anchorWidthDp <= 0) return AdSize.banner;
    final adaptive =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(anchorWidthDp);
    return adaptive ?? AdSize.banner;
  }

  /// Optional SDK warm-up inventory (not mounted — hosts always load dedicated ads).
  final Map<String, BannerAd> _preloadedByKey = <String, BannerAd>{};
  final Set<String> _loadsInFlight = <String>{};
  final Set<String> _hostLoadClaimed = <String>{};

  Widget show(
    BuildContext context, {
    required String slot,
    required Key hostKey,
  }) {
    final adUnitId =
        slot == 'bottom' ? Config.admobsBottomBanner : Config.admobsTopBanner;
    if (kIsWeb || adUnitId.trim().isEmpty) {
      _diagOnceLog(
        'shrink|$slot',
        'show shrink slot=$slot web=$kIsWeb empty=${adUnitId.trim().isEmpty}',
      );
      return const SizedBox.shrink();
    }
    return _BannerAdSlotHost(
      key: hostKey,
      module: this,
      slot: slot,
      adUnitId: adUnitId,
    );
  }

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);

    final appManager = Provider.of<AppManager>(context, listen: false);
    admobTrace(
      'Banner',
      'initialize module=$moduleKey showMonetizedAds=${AdExperiencePolicy.showMonetizedAds} '
      '${AdExperiencePolicy.monetizedAdsDebugLabel()}',
    );
    _registerBannerCallbacks(appManager.hooksManager);
  }

  void _registerBannerCallbacks(HooksManager hooksManager) {
    hooksManager.registerHookWithData('top_banner_bar_loaded', (data) {
      admobTrace('Banner', 'hook top_banner_bar_loaded → loadBannerAd(top)');
      loadBannerAd(Config.admobsTopBanner, slot: 'top');
    }, priority: 10);

    hooksManager.registerHookWithData('bottom_banner_bar_loaded', (data) {
      if (kIsWeb) return;
      admobTrace('Banner', 'hook bottom_banner_bar_loaded → loadBannerAd(bottom)');
      loadBannerAd(Config.admobsBottomBanner, slot: 'bottom');
    }, priority: 10);
  }

  /// SDK warm-up only — hosts do not take these (avoids one [BannerAd] / two [AdWidget]s).
  Future<void> loadBannerAd(
    String adUnitId, {
    required String slot,
    int anchorWidthDp = warmupAnchorWidthDp,
  }) async {
    if (kIsWeb) return;
    if (adUnitId.trim().isEmpty || !AdExperiencePolicy.showMonetizedAds) return;

    final key = storageKey(slot, adUnitId);
    if (_preloadedByKey.containsKey(key) || _loadsInFlight.contains(key)) return;

    _loadsInFlight.add(key);
    final size = await adaptiveSizeForWidth(anchorWidthDp);
    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) => _preloadedByKey[key] = ad as BannerAd,
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          ad.dispose();
          _preloadedByKey.remove(key);
        },
      ),
    );

    try {
      await bannerAd.load();
    } finally {
      _loadsInFlight.remove(key);
    }
  }

  /// Loads one [BannerAd] exclusively for [hostKey] at [anchorWidthDp].
  Future<BannerAd?> loadBannerAdForHost({
    required String slot,
    required String adUnitId,
    required Key hostKey,
    required int anchorWidthDp,
  }) async {
    if (kIsWeb || adUnitId.trim().isEmpty || !AdExperiencePolicy.showMonetizedAds) {
      return null;
    }
    final claimKey = _hostLoadKey(slot, adUnitId, hostKey);
    if (_loadsInFlight.contains(claimKey) || !_hostLoadClaimed.add(claimKey)) {
      return null;
    }
    _loadsInFlight.add(claimKey);

    final completer = Completer<BannerAd?>();
    final size = await adaptiveSizeForWidth(anchorWidthDp);
    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (!completer.isCompleted) completer.complete(ad as BannerAd);
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          admobTrace(
            'Banner',
            'host onAdFailedToLoad slot=$slot host=${hostKey.hashCode} '
            'width=$anchorWidthDp code=${error.code} message=${error.message}',
          );
          ad.dispose();
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );

    try {
      await bannerAd.load();
      return await completer.future;
    } catch (e) {
      admobTrace('Banner', 'host load exception slot=$slot: $e');
      if (!completer.isCompleted) completer.complete(null);
      bannerAd.dispose();
      return null;
    } finally {
      _loadsInFlight.remove(claimKey);
      _hostLoadClaimed.remove(claimKey);
    }
  }

  Widget getTopBannerWidget(BuildContext context, {required Key hostKey}) =>
      show(context, slot: 'top', hostKey: hostKey);

  Widget getBottomBannerWidget(BuildContext context, {required Key hostKey}) =>
      show(context, slot: 'bottom', hostKey: hostKey);

  @override
  void dispose() {
    _loadsInFlight.clear();
    _hostLoadClaimed.clear();
    for (final ad in _preloadedByKey.values) {
      ad.dispose();
    }
    _preloadedByKey.clear();
    super.dispose();
  }
}

/// Owns exactly one [BannerAd] and one [AdWidget] for [widget.key]'s lifetime.
class _BannerAdSlotHost extends StatefulWidget {
  const _BannerAdSlotHost({
    super.key,
    required this.module,
    required this.slot,
    required this.adUnitId,
  });

  final BannerAdModule module;
  final String slot;
  final String adUnitId;

  @override
  State<_BannerAdSlotHost> createState() => _BannerAdSlotHostState();
}

class _BannerAdSlotHostState extends State<_BannerAdSlotHost> {
  BannerAd? _bannerAd;
  int? _loadedAnchorWidth;
  bool _loadInFlight = false;
  int? _scheduledWidth;

  Future<void> _loadForWidth(int width) async {
    if (width <= 0 || !mounted) return;
    if (_loadInFlight) return;
    if (_bannerAd != null && _loadedAnchorWidth == width) return;

    if (kIsWeb || !AdExperiencePolicy.showMonetizedAds) return;
    final hostKey = widget.key;
    if (hostKey == null) return;

    if (_bannerAd != null) {
      _bannerAd?.dispose();
      _bannerAd = null;
      _loadedAnchorWidth = null;
    }

    _loadInFlight = true;
    final loaded = await widget.module.loadBannerAdForHost(
      slot: widget.slot,
      adUnitId: widget.adUnitId,
      hostKey: hostKey,
      anchorWidthDp: width,
    );
    _loadInFlight = false;

    if (!mounted) {
      loaded?.dispose();
      return;
    }
    if (loaded == null) return;
    if (_bannerAd != null) {
      loaded.dispose();
      return;
    }
    _bannerAd = loaded;
    _loadedAnchorWidth = width;
    setState(() {});
  }

  void _scheduleLoadForWidth(int width) {
    if (width <= 0) return;
    if (_bannerAd != null && _loadedAnchorWidth == width) return;
    if (_loadInFlight && _scheduledWidth == width) return;
    _scheduledWidth = width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final w = _scheduledWidth;
      if (w == null || w <= 0) return;
      if (_bannerAd != null && _loadedAnchorWidth == w) return;
      unawaited(_loadForWidth(w));
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.floor();
        if (width > 0) {
          _scheduleLoadForWidth(width);
        }

        final ad = _bannerAd;
        if (ad == null) {
          return const SizedBox.shrink();
        }

        return SizedBox(
          width: width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(
            key: ValueKey<int>(widget.key.hashCode),
            ad: ad,
          ),
        );
      },
    );
  }
}
