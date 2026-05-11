import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:uuid/uuid.dart';

import '../../core/00_base/screen_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../modules/admobs/ad_experience_policy.dart';
import '../../modules/admobs/rewarded/rewarded_ad.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../../utils/analytics_service.dart';
import '../../utils/coin_catalog.dart';
import '../../utils/consts/config.dart';
import '../../utils/consts/theme_consts.dart';
import '../../utils/dbg.dart';

/// **Web**: Stripe Checkout via `/userauth/stripe/create-coin-checkout-session`.
/// **Android**: Google Play Billing + server verify `/userauth/play/verify-coin-purchase`.
/// **iOS**: not wired (use web or add App Store Server API later).
class CoinPurchaseScreen extends BaseScreen {
  const CoinPurchaseScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Buy coins';

  @override
  BaseScreenState<CoinPurchaseScreen> createState() => _CoinPurchaseScreenState();
}

class _CoinPurchaseScreenState extends BaseScreenState<CoinPurchaseScreen> {
  static const String _contextKey = 'lastCoinPurchaseJoinContext';
  List<_CoinPackage> _recommendedPackages = [];
  bool _catalogReady = false;

  String? _loadingPackageKey;
  bool _handledStripeReturn = false;

  final InAppPurchase _playIap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _playPurchaseSub;
  bool _playBillingAvailable = false;
  Map<String, ProductDetails> _playProductDetails = {};
  String? _playBusyProductId;
  bool _rewardedAdBusy = false;

  bool get _nativeMobile => !kIsWeb;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _bootstrapCatalog() async {
    await CoinCatalog.ensureLoaded();
    if (!mounted) {
      return;
    }
    final rec = CoinCatalog.recommendedUiPackages;
    setState(() {
      _catalogReady = true;
      _recommendedPackages = rec
          .map(
            (j) => _CoinPackage(
              key: j['key'] as String,
              label: j['label'] as String,
              coins: (j['coins'] as num).toInt(),
              description: _coinPackDescriptionFromRow(j),
              priceLabel: (j['priceLabel'] as String?) ?? '',
              isPopular: j['isPopular'] == true,
            ),
          )
          .toList();
    });
  }

  Future<void> _bootstrapPlayBilling() async {
    if (!_isAndroid || !mounted) return;
    final ok = await _playIap.isAvailable();
    if (!mounted) return;
    setState(() => _playBillingAvailable = ok);
    if (!ok) return;

    _playPurchaseSub?.cancel();
    _playPurchaseSub = _playIap.purchaseStream.listen(_handlePlayPurchases, onError: (_) {});

    final ids = <String>{};
    for (final row in CoinCatalog.playRecommendedPackages) {
      final id = row['product_id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) return;

    final resp = await _playIap.queryProductDetails(ids);
    if (!mounted) return;
    final map = <String, ProductDetails>{};
    for (final p in resp.productDetails) {
      map[p.id] = p;
    }
    setState(() => _playProductDetails = map);
  }

  Future<void> _handlePlayPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.error:
          if (mounted && purchase.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  purchase.error!.message,
                  style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
                ),
                backgroundColor: AppColors.primaryColor,
              ),
            );
          }
          if (purchase.pendingCompletePurchase) {
            await _playIap.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) {
            await _playIap.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyPlayPurchaseOnServer(purchase);
          break;
      }
    }
  }

  Future<void> _verifyPlayPurchaseOnServer(PurchaseDetails purchase) async {
    final token = purchase.purchaseID ?? '';
    final productId = purchase.productID;
    if (token.isEmpty) {
      if (purchase.pendingCompletePurchase) {
        await _playIap.completePurchase(purchase);
      }
      return;
    }

    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (api == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cannot reach server to confirm purchase.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
      return;
    }

    try {
      final raw = await api.sendPostRequest('/userauth/play/verify-coin-purchase', {
        'product_id': productId,
        'purchase_token': token,
      });
      if (raw is! Map) {
        throw Exception('Unexpected response');
      }
      final map = Map<String, dynamic>.from(raw);
      final success = map['success'] == true;
      if (!success) {
        final msg = map['message']?.toString() ?? map['error']?.toString() ?? 'Purchase verification failed';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg, style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
              backgroundColor: AppColors.primaryColor,
            ),
          );
        }
        return;
      }

      if (purchase.pendingCompletePurchase) {
        await _playIap.completePurchase(purchase);
      }
      await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Coins added to your balance.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
      await AnalyticsService.logEvent(
        name: 'play_coin_purchase_verified',
        parameters: {'product_id': productId},
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not verify purchase. You can reopen this screen to retry.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    }
  }

  Future<void> _buyPlayProduct(ProductDetails details) async {
    setState(() => _playBusyProductId = details.id);
    try {
      final started = await _playIap.buyConsumable(purchaseParam: PurchaseParam(productDetails: details));
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not start purchase.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Purchase failed. Try again later.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _playBusyProductId = null);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _bootstrapCatalog();
      if (!mounted) return;
      if (kIsWeb) {
        await _maybeHandleStripeReturn();
      } else if (_isAndroid) {
        await _bootstrapPlayBilling();
      }
    });
  }

  @override
  void dispose() {
    _playPurchaseSub?.cancel();
    super.dispose();
  }

  String _stripeResultInUri(Uri u) {
    final direct = u.queryParameters['stripe_checkout'];
    if (direct == 'success' || direct == 'cancel') return direct.toString();
    final fragment = u.fragment;
    final qMark = fragment.indexOf('?');
    if (qMark >= 0 && qMark < fragment.length - 1) {
      final inner = Uri.splitQueryString(fragment.substring(qMark + 1));
      final fromHash = inner['stripe_checkout'];
      if (fromHash == 'success' || fromHash == 'cancel') return fromHash.toString();
    }
    return 'none';
  }

  String? _sessionIdInUri(Uri u) {
    final direct = u.queryParameters['session_id'];
    if (direct != null && direct.isNotEmpty) return direct;
    final fragment = u.fragment;
    final qMark = fragment.indexOf('?');
    if (qMark >= 0 && qMark < fragment.length - 1) {
      final inner = Uri.splitQueryString(fragment.substring(qMark + 1));
      final id = inner['session_id'];
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> _maybeHandleStripeReturn() async {
    if (!kIsWeb || _handledStripeReturn || !mounted) {
      return;
    }
    final uri = Uri.base;
    final result = _stripeResultInUri(uri);
    if (result == 'none') return;
    if (result == 'cancel') {
      _handledStripeReturn = true;
      await AnalyticsService.logEvent(
        name: 'coin_checkout_return',
        parameters: {'result': 'cancel'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment canceled.',
            style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
          ),
          backgroundColor: AppColors.primaryColor,
        ),
      );
      return;
    }
    await AnalyticsService.logEvent(
      name: 'coin_checkout_return',
      parameters: {'result': 'success'},
    );
    _handledStripeReturn = true;
    final sessionId = _sessionIdInUri(uri);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Payment complete. Refreshing your coin balance…',
          style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
        ),
        backgroundColor: AppColors.primaryColor,
      ),
    );
    if (sessionId != null && sessionId.isNotEmpty) {
      final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
      if (api != null) {
        try {
          await api.sendPostRequest('/userauth/stripe/verify-coin-checkout-session', {
            'session_id': sessionId,
          });
        } catch (_) {}
      }
    }
    if (!mounted) return;
    final ok = await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Balance updated.' : 'Coins may take a moment to appear. Open this screen again in a few seconds.',
          style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
        ),
        backgroundColor: AppColors.primaryColor,
      ),
    );
  }

  Future<void> _startCheckout(_CoinPackage pack) async {
    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (api == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot reach payment service.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
      return;
    }
    setState(() => _loadingPackageKey = pack.key);
    try {
      final raw = await api.sendPostRequest('/userauth/stripe/create-coin-checkout-session', {
        'package_key': pack.key,
      });
      if (raw is! Map) {
        throw Exception('Unexpected response');
      }
      final map = Map<String, dynamic>.from(raw);
      if (map['success'] != true || map['url'] == null) {
        final msg = map['message']?.toString() ?? map['error']?.toString() ?? 'Checkout could not start';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg, style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
              backgroundColor: AppColors.primaryColor,
            ),
          );
        }
        return;
      }
      final url = map['url'].toString();
      await AnalyticsService.logEvent(
        name: 'coin_checkout_started',
        parameters: {
          'package_key': pack.key,
          'coins': pack.coins,
        },
      );
      final launched = await ConnectionsApiModule.launchUrl(url);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open checkout. Check popup blocker.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout failed. Try again later.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPackageKey = null);
    }
  }

  Future<void> _claimRewardedAdCoins(ConnectionsApiModule api, String clientNonce) async {
    try {
      final raw = await api.sendPostRequest('/userauth/admob/claim-rewarded-ad', {
        'client_nonce': clientNonce,
      });
      if (raw is! Map) {
        throw Exception('Unexpected response');
      }
      final map = Map<String, dynamic>.from(raw);
      if (map['success'] != true) {
        final msg = map['error']?.toString() ?? map['message']?.toString() ?? 'Could not apply reward';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg, style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
              backgroundColor: AppColors.primaryColor,
            ),
          );
        }
        return;
      }
      await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      if (!mounted) return;
      final credited = map['coins_credited'];
      final bal = map['balance'];
      final dup = map['duplicate'] == true;
      final msg = dup
          ? 'Reward already recorded.'
          : (credited != null ? '+$credited coins. Balance: $bal' : 'Coins added.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
          backgroundColor: AppColors.primaryColor,
        ),
      );
      await AnalyticsService.logEvent(
        name: 'admob_rewarded_claim',
        parameters: {'duplicate': dup},
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not confirm reward. Try again later.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    }
  }

  Future<void> _watchRewardedAdForCoins() async {
    if (kIsWeb || Config.admobsRewarded01.trim().isEmpty) {
      dbgAdMob(
        'coin screen _watchRewardedAdForCoins skip (web=$kIsWeb rewardedUnitEmpty=${Config.admobsRewarded01.trim().isEmpty})',
      );
      return;
    }

    dbgAdMob('coin screen _watchRewardedAdForCoins start');
    final mod = ModuleManager().getModuleByType<RewardedAdModule>();
    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (mod == null || api == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rewards are not available right now.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
      dbgAdMob(
        'coin screen rewarded unavailable (modNull=${mod == null} apiNull=${api == null})',
      );
      return;
    }

    if (!mod.isReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ad is still loading. Try again in a moment.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
      dbgAdMob('coin screen rewarded not ready → snack + loadAd');
      unawaited(mod.loadAd());
      return;
    }

    final clientNonce = const Uuid().v4();
    setState(() => _rewardedAdBusy = true);
    try {
      dbgAdMob('coin screen calling RewardedAdModule.showAd nonceLen=${clientNonce.length}');
      await mod.showAd(
        context,
        onUserEarnedReward: () {
          dbgAdMob('coin screen onUserEarnedReward → claim API');
          unawaited(_claimRewardedAdCoins(api, clientNonce));
        },
      );
      dbgAdMob('coin screen RewardedAdModule.showAd completed');
    } finally {
      if (mounted) setState(() => _rewardedAdBusy = false);
    }
  }

  Widget _buildRewardedAdCard() {
    final mod = ModuleManager().getModuleByType<RewardedAdModule>();
    if (mod == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int>(
      valueListenable: mod.stateTick,
      builder: (context, _, __) {
        final ready = mod.isReady;
        return Container(
          width: double.infinity,
          padding: AppPadding.cardPadding,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppBorderRadius.smallRadius,
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Free coins', style: AppTextStyles.headingSmall()),
              const SizedBox(height: 6),
              Text(
                'Watch a short video. Coins are added after the server confirms your reward.',
                style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_rewardedAdBusy || !ready) ? null : _watchRewardedAdForCoins,
                child: _rewardedAdBusy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textOnPrimary,
                        ),
                      )
                    : Text(ready ? 'Watch ad for coins' : 'Loading ad…'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, _) {
        final dutch = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final joinCtx = dutch[_contextKey];
        final Map<String, dynamic> map = joinCtx is Map
            ? Map<String, dynamic>.from(joinCtx)
            : <String, dynamic>{};

        return SingleChildScrollView(
          padding: AppPadding.defaultPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (kIsWeb) ...[
                Text('Coin packages', style: AppTextStyles.headingSmall()),
                const SizedBox(height: 8),
                Text(
                  'Choose a coin pack. Secure checkout is processed by Stripe.',
                  style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                ),
                SizedBox(height: AppPadding.defaultPadding.top),
                if (!_catalogReady)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  ..._recommendedPackages.map(_buildPackageCard),
                SizedBox(height: AppPadding.defaultPadding.top),
              ],
              if (_isAndroid) ...[
                Text('Coin packages', style: AppTextStyles.headingSmall()),
                const SizedBox(height: 8),
                Text(
                  'Purchases are processed by Google Play. Your account is credited after our server confirms the transaction.',
                  style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                ),
                SizedBox(height: AppPadding.defaultPadding.top),
                if (!_catalogReady)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (!_playBillingAvailable)
                  Text(
                    'Google Play Billing is not available on this device.',
                    style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                  )
                else
                  ...CoinCatalog.playRecommendedPackages.map(_buildPlayPackageRow),
                SizedBox(height: AppPadding.defaultPadding.top),
              ],
              if (_nativeMobile && Config.admobsRewarded01.trim().isNotEmpty) ...[
                ListenableBuilder(
                  listenable: StateManager(),
                  builder: (context, _) {
                    if (!AdExperiencePolicy.showMonetizedAds) {
                      return const SizedBox.shrink();
                    }
                    return _buildRewardedAdCard();
                  },
                ),
                SizedBox(height: AppPadding.defaultPadding.top),
              ],
              if (_isIos) ...[
                Text('Coin packages', style: AppTextStyles.headingSmall()),
                const SizedBox(height: 8),
                Text(
                  'App Store billing is not enabled in this build. Use the web app (Stripe) to buy coins.',
                  style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                ),
                SizedBox(height: AppPadding.defaultPadding.top),
              ],
              Text(
                kIsWeb || _nativeMobile
                    ? 'Join attempt details (debug / support):'
                    : 'Coin purchases on this platform are not set up yet. Join attempt data:',
                style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
              ),
              SizedBox(height: AppPadding.defaultPadding.top),
              if (map.isEmpty)
                Text(
                  'No recent join attempt on record. Open this screen after a failed join, or use the drawer any time.',
                  style: AppTextStyles.bodyLarge(color: AppColors.textPrimary),
                )
              else
                Container(
                  width: double.infinity,
                  padding: AppPadding.cardPadding,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppBorderRadius.smallRadius,
                    border: Border.all(color: AppColors.borderDefault),
                  ),
                  child: SelectableText(
                    _formatContext(map),
                    style: AppTextStyles.bodySmall(color: AppColors.textOnSurface).copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlayPackageRow(Map<String, dynamic> row) {
    final productId = row['product_id'] as String? ?? '';
    final label = row['label'] as String? ?? productId;
    final isPopular = row['isPopular'] == true;
    final details = _playProductDetails[productId];
    final priceText = details?.price ?? (row['priceLabel'] as String? ?? '—');
    final busy = _playBusyProductId == productId;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppBorderRadius.smallRadius,
        border: Border.all(
          color: isPopular ? AppColors.accentColor : AppColors.borderDefault,
          width: isPopular ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: AppTextStyles.bodyLarge(color: AppColors.textPrimary)),
                    if (isPopular) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accentColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Most Popular',
                          style: AppTextStyles.bodySmall(color: AppColors.textOnPrimary),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _coinPackDescriptionFromRow(row),
                  style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(priceText, style: AppTextStyles.headingSmall()),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: (busy || details == null) ? null : () => _buyPlayProduct(details),
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textOnPrimary,
                    ),
                  )
                : const Text('Buy'),
          ),
        ],
      ),
    );
  }

  String _formatContext(Map<String, dynamic> m) {
    final buf = StringBuffer();
    for (final e in m.entries) {
      buf.writeln('${e.key}: ${e.value}');
    }
    return buf.toString().trim();
  }

  Widget _buildPackageCard(_CoinPackage pack) {
    final busy = _loadingPackageKey == pack.key;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppBorderRadius.smallRadius,
        border: Border.all(
          color: pack.isPopular ? AppColors.accentColor : AppColors.borderDefault,
          width: pack.isPopular ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(pack.label, style: AppTextStyles.bodyLarge(color: AppColors.textPrimary)),
                    if (pack.isPopular) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accentColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Most Popular',
                          style: AppTextStyles.bodySmall(color: AppColors.textOnPrimary),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  pack.description,
                  style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(pack.priceLabel, style: AppTextStyles.headingSmall()),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: busy ? null : () => _startCheckout(pack),
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textOnPrimary,
                    ),
                  )
                : const Text('Buy'),
          ),
        ],
      ),
    );
  }
}

class _CoinPackage {
  final String key;
  final String label;
  final int coins;
  final String description;
  final String priceLabel;
  final bool isPopular;

  const _CoinPackage({
    required this.key,
    required this.label,
    required this.coins,
    required this.description,
    required this.priceLabel,
    this.isPopular = false,
  });
}

String _coinPackDescriptionFromRow(Map<String, dynamic> j) {
  final d = j['description']?.toString().trim();
  if (d != null && d.isNotEmpty) return d;
  final c = (j['coins'] as num?)?.toInt() ?? 0;
  return 'Adds $c coins to your balance. Coins are used for table fees and in-game purchases.';
}
