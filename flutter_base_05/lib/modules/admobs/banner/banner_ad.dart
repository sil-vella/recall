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
/// Top and bottom are tracked separately so the **same ad unit id** can be used for both
/// slots (two loads, two [BannerAd] instances). Deduplicating only by unit id would skip the
/// second load and would not allow two [AdWidget]s for one ad object.
///
/// Use [show] (not a shared [AdWidget] in multiple routes). Each call returns a new host
/// widget; only one host may mount [AdWidget] per slot at a time (route transitions).
class BannerAdModule extends ModuleBase {
  BannerAdModule() : super('admobs_banner_ad_module', dependencies: []);

  static String _storageKey(String slot, String adUnitId) => '$slot|${adUnitId.trim()}';

  /// One-shot diagnostics (avoid log spam on every rebuild).
  static final Set<String> _diagOnce = <String>{};

  static void _diagOnceLog(String key, String message) {
    if (_diagOnce.add(key)) {
      admobTrace('Banner', message);
    }
  }

  final Map<String, BannerAd?> _bannerByKey = <String, BannerAd?>{};
  final Set<String> _loadsInFlight = <String>{};
  final ValueNotifier<int> _frameTick = ValueNotifier<int>(0);

  /// Active [AdWidget] host per slot (`top` / `bottom`).
  final Map<String, Object> _slotOwnerBySlot = <String, Object>{};

  /// Bumped when a slot's [AdWidget] host changes so the next mount gets a fresh key.
  final Map<String, int> _slotAdWidgetGeneration = <String, int>{};

  bool _disposed = false;

  /// Schedules a tick bump **after** the current frame so [releaseSlot] during [deactivate]
  /// does not notify [ValueListenableBuilder] listeners while the framework is still building.
  void _notifyFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _frameTick.value++;
    });
  }

  /// Returns a new banner host widget for [slot]. Only the owning host builds [AdWidget].
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

  BannerAd? bannerAdFor(String slot, String adUnitId) =>
      _bannerByKey[_storageKey(slot, adUnitId)];

  int adWidgetGenerationFor(String slot) => _slotAdWidgetGeneration[slot] ?? 0;

  /// Claims [slot] for [token] when unowned or already held by [token].
  bool tryClaimSlot(String slot, Object token) {
    final owner = _slotOwnerBySlot[slot];
    if (owner == token) return true;
    if (owner != null) return false;
    _slotOwnerBySlot[slot] = token;
    _slotAdWidgetGeneration[slot] = (_slotAdWidgetGeneration[slot] ?? 0) + 1;
    return true;
  }

  void releaseSlot(String slot, Object token) {
    if (_slotOwnerBySlot[slot] == token) {
      _slotOwnerBySlot.remove(slot);
      _notifyFrame();
    }
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

  /// Preloads a banner for [adUnitId] (native only). [slot] must be stable (`top` / `bottom`)
  /// so top and bottom can share the same unit id with two separate [BannerAd] instances.
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
    final key = _storageKey(slot, adUnitId);
    if (_bannerByKey[key] != null || _loadsInFlight.contains(key)) {
      admobTrace(
        'Banner',
        'loadBannerAd skip: already loaded or inFlight slot=$slot inFlight=${_loadsInFlight.contains(key)}',
      );
      return;
    }
    _loadsInFlight.add(key);
    admobTrace(
      'Banner',
      'BannerAd.load() slot=$slot unitId=$adUnitId size=AdSize.banner — '
      'Android app id must match this unit (local.properties admob.application_id)',
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
          _bannerByKey[key] = b;
          _notifyFrame();
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          admobTrace(
            'Banner',
            'onAdFailedToLoad slot=$slot unitId=$adUnitId code=${error.code} message=${error.message}',
          );
          ad.dispose();
          _bannerByKey.remove(key);
          _notifyFrame();
        },
      ),
    );

    try {
      await bannerAd.load();
      admobTrace('Banner', 'await load() returned slot=$slot unitId=$adUnitId (callbacks may still be pending)');
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
      final key = _storageKey(slot, t);
      final ad = _bannerByKey.remove(key);
      ad?.dispose();
      _slotOwnerBySlot.remove(slot);
    }
    _notifyFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadsInFlight.clear();
    _slotOwnerBySlot.clear();
    _slotAdWidgetGeneration.clear();
    for (final ad in _bannerByKey.values) {
      ad?.dispose();
    }
    _bannerByKey.clear();
    _frameTick.dispose();
    super.dispose();
  }
}

/// One host per [BannerAdModule.show] call. Releases the slot on deactivate so the next
/// route can claim the preloaded [BannerAd] without duplicate [AdWidget] errors.
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
  final Object _hostToken = Object();

  @override
  void deactivate() {
    widget.module.releaseSlot(widget.slot, _hostToken);
    super.deactivate();
  }

  @override
  void dispose() {
    widget.module.releaseSlot(widget.slot, _hostToken);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.module._frameTick,
      builder: (context, tick, _) {
        if (!widget.module.tryClaimSlot(widget.slot, _hostToken)) {
          return const SizedBox.shrink();
        }

        final storageKey = BannerAdModule._storageKey(widget.slot, widget.adUnitId);
        final ad = widget.module.bannerAdFor(widget.slot, widget.adUnitId);
        if (ad == null) {
          BannerAdModule._diagOnceLog(
            'await|$storageKey',
            'show slot=${widget.slot} key=$storageKey tick=$tick → no BannerAd yet',
          );
          return const SizedBox.shrink();
        }

        final gen = widget.module.adWidgetGenerationFor(widget.slot);
        BannerAdModule._diagOnceLog(
          'show|$storageKey',
          'show slot=${widget.slot} key=$storageKey gen=$gen '
          'size=${ad.size.width}x${ad.size.height}',
        );

        return SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(
            key: ValueKey('banner_${widget.slot}_$gen'),
            ad: ad,
          ),
        );
      },
    );
  }
}
