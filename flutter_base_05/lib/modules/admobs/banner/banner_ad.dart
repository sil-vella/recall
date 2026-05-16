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

/// Loads banner units via hooks and displays each slot with its own [BannerAd] + [AdWidget].
///
/// Each [show] call returns a new host [StatefulWidget] that **owns** one [BannerAd] for its
/// lifetime (take preloaded inventory or load locally). Never share one [BannerAd] across
/// two [AdWidget]s — including top + bottom on the same screen.
class BannerAdModule extends ModuleBase {
  BannerAdModule() : super('admobs_banner_ad_module', dependencies: []);

  static String storageKey(String slot, String adUnitId) =>
      '$slot|${adUnitId.trim()}';

  static final Set<String> _diagOnce = <String>{};

  static void _diagOnceLog(String key, String message) {
    if (_diagOnce.add(key)) {
      admobTrace('Banner', message);
    }
  }

  /// Preloaded ads waiting for a host to [takePreloaded].
  final Map<String, BannerAd> _preloadedByKey = <String, BannerAd>{};
  final Set<String> _loadsInFlight = <String>{};

  /// Returns a new banner host; each call creates a distinct widget subtree.
  Widget show(BuildContext context, {required String slot}) {
    final adUnitId =
        slot == 'bottom' ? Config.admobsBottomBanner : Config.admobsTopBanner;
    if (kIsWeb || adUnitId.trim().isEmpty || !AdExperiencePolicy.showMonetizedAds) {
      _diagOnceLog(
        'shrink|$slot',
        'show shrink slot=$slot web=$kIsWeb empty=${adUnitId.trim().isEmpty} '
        'monetized=${AdExperiencePolicy.showMonetizedAds} ${AdExperiencePolicy.monetizedAdsDebugLabel()}',
      );
      return const SizedBox.shrink();
    }
    return _BannerAdSlotHost(
      module: this,
      slot: slot,
      adUnitId: adUnitId,
    );
  }

  /// Hands exclusive ownership of a preloaded [BannerAd] to one host, or null if none.
  BannerAd? takePreloaded(String slot, String adUnitId) {
    final key = storageKey(slot, adUnitId);
    return _preloadedByKey.remove(key);
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
    admobTrace(
      'Banner',
      'compile-time ADMOBS_TOP len=${Config.admobsTopBanner.length} '
      'ADMOBS_BOTTOM len=${Config.admobsBottomBanner.length} '
      '(empty unit skips load for that slot)',
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
    admobTrace('Banner', 'registered top+bottom hooks (priority 10; AppManager stubs at 1)');
  }

  /// Preloads a banner into inventory (native only). A host consumes it via [takePreloaded].
  Future<void> loadBannerAd(String adUnitId, {required String slot}) async {
    if (kIsWeb) {
      admobTrace('Banner', 'loadBannerAd skip: web');
      return;
    }
    if (adUnitId.trim().isEmpty) {
      admobTrace('Banner', 'loadBannerAd skip: empty adUnitId (check ADMOBS_TOP/BOTTOM dart-define)');
      return;
    }
    if (!AdExperiencePolicy.showMonetizedAds) {
      admobTrace(
        'Banner',
        'loadBannerAd skip: monetized ads off (${AdExperiencePolicy.monetizedAdsDebugLabel()})',
      );
      return;
    }
    final key = storageKey(slot, adUnitId);
    if (_preloadedByKey.containsKey(key) || _loadsInFlight.contains(key)) {
      admobTrace(
        'Banner',
        'loadBannerAd skip: already preloaded or inFlight slot=$slot',
      );
      return;
    }
    _loadsInFlight.add(key);
    admobTrace(
      'Banner',
      'BannerAd.load() slot=$slot unitId=$adUnitId size=AdSize.banner',
    );

    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          final b = ad as BannerAd;
          admobTrace(
            'Banner',
            'onAdLoaded slot=$slot unitId=$adUnitId widget=${b.size.width}x${b.size.height}',
          );
          _preloadedByKey[key] = b;
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          admobTrace(
            'Banner',
            'onAdFailedToLoad slot=$slot unitId=$adUnitId code=${error.code} message=${error.message}',
          );
          ad.dispose();
          _preloadedByKey.remove(key);
        },
      ),
    );

    try {
      await bannerAd.load();
      admobTrace('Banner', 'await load() returned slot=$slot unitId=$adUnitId');
    } finally {
      _loadsInFlight.remove(key);
    }
  }

  /// Loads a [BannerAd] for a single host (not shared). Caller must [BannerAd.dispose] it.
  Future<BannerAd?> loadBannerAdForHost({
    required String slot,
    required String adUnitId,
  }) async {
    if (kIsWeb || adUnitId.trim().isEmpty || !AdExperiencePolicy.showMonetizedAds) {
      return null;
    }
    final key = storageKey(slot, adUnitId);
    if (_loadsInFlight.contains(key)) {
      admobTrace('Banner', 'loadBannerAdForHost skip: inFlight slot=$slot');
      return null;
    }
    _loadsInFlight.add(key);
    BannerAd? loaded;
    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) => loaded = ad as BannerAd,
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          admobTrace(
            'Banner',
            'host onAdFailedToLoad slot=$slot code=${error.code} message=${error.message}',
          );
          ad.dispose();
          loaded = null;
        },
      ),
    );
    try {
      await bannerAd.load();
      return loaded;
    } catch (_) {
      bannerAd.dispose();
      return null;
    } finally {
      _loadsInFlight.remove(key);
    }
  }

  Widget getTopBannerWidget(BuildContext context) => show(context, slot: 'top');

  Widget getBottomBannerWidget(BuildContext context) => show(context, slot: 'bottom');

  void disposeBannerAd(String adUnitId) {
    final t = adUnitId.trim();
    if (t.isEmpty) return;
    for (final slot in <String>['top', 'bottom']) {
      final key = storageKey(slot, t);
      _preloadedByKey.remove(key)?.dispose();
    }
  }

  @override
  void dispose() {
    _loadsInFlight.clear();
    for (final ad in _preloadedByKey.values) {
      ad.dispose();
    }
    _preloadedByKey.clear();
    super.dispose();
  }
}

/// Owns exactly one [BannerAd] and one [AdWidget] for the host's lifetime.
class _BannerAdSlotHost extends StatefulWidget {
  const _BannerAdSlotHost({
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

  @override
  void initState() {
    super.initState();
    _acquireAd();
  }

  Future<void> _acquireAd() async {
    var taken = widget.module.takePreloaded(widget.slot, widget.adUnitId);
    if (taken != null) {
      if (!mounted) {
        taken.dispose();
        return;
      }
      setState(() => _bannerAd = taken);
      return;
    }

    final loaded = await widget.module.loadBannerAdForHost(
      slot: widget.slot,
      adUnitId: widget.adUnitId,
    );
    if (!mounted) {
      loaded?.dispose();
      return;
    }
    if (loaded != null) {
      setState(() => _bannerAd = loaded);
      return;
    }

    // Preload may still be in flight from hooks; poll inventory briefly.
    for (var i = 0; i < 12 && mounted && _bannerAd == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      taken = widget.module.takePreloaded(widget.slot, widget.adUnitId);
      if (taken != null && mounted) {
        setState(() => _bannerAd = taken);
        return;
      }
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (ad == null) {
      BannerAdModule._diagOnceLog(
        'await|${widget.slot}',
        'host slot=${widget.slot} awaiting BannerAd',
      );
      return const SizedBox.shrink();
    }

    BannerAdModule._diagOnceLog(
      'show|${widget.slot}',
      'host slot=${widget.slot} AdWidget ${ad.size.width}x${ad.size.height}',
    );

    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(
        key: ObjectKey(ad),
        ad: ad,
      ),
    );
  }
}
