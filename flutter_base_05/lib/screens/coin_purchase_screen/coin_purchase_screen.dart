import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/00_base/screen_base.dart';
import '../../core/managers/auth_manager.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../../tools/logging/logger.dart';
import '../../utils/analytics_service.dart';
import '../../utils/consts/theme_consts.dart';

const bool LOGGING_SWITCH = true; // RevenueCat native + Stripe web coin flow (enable-logging-switch.mdc) — set false after debugging

/// Coin purchases on **web**: Stripe Checkout via Python `/userauth/stripe/create-coin-checkout-session`.
/// On **iOS/Android**: RevenueCat store packages + `/userauth/revenuecat/verify-coin-purchase` to credit coins.
/// Also shows [lastCoinPurchaseJoinContext] when the user was sent here after a failed join.
class CoinPurchaseScreen extends BaseScreen {
  const CoinPurchaseScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Buy coins';

  @override
  BaseScreenState<CoinPurchaseScreen> createState() => _CoinPurchaseScreenState();
}

class _CoinPurchaseScreenState extends BaseScreenState<CoinPurchaseScreen> {
  static const String _contextKey = 'lastCoinPurchaseJoinContext';
  final Logger _logger = Logger();

  /// Store product id → coin amount (must stay aligned with Python `REVENUECAT_COIN_PRODUCT_COINS`).
  static const Map<String, int> _nativeStoreProductCoins = {
    'starter_pack_100_coin': 100,
    'coins_100': 100,
    'coins_500': 500,
    'coins_1000': 1000,
    'coins_2500': 2500,
    'coins_5000': 5000,
    'coins_10000': 10000,
  };

  static const List<_CoinPackage> _recommendedPackages = [
    _CoinPackage(key: 'starter', label: 'Starter', coins: 100, priceLabel: '\$0.99'),
    _CoinPackage(key: 'casual', label: 'Casual', coins: 300, priceLabel: '\$2.49'),
    _CoinPackage(key: 'popular', label: 'Popular', coins: 700, priceLabel: '\$4.99', isPopular: true),
    _CoinPackage(key: 'grinder', label: 'Grinder', coins: 1500, priceLabel: '\$9.99'),
    _CoinPackage(key: 'pro', label: 'Pro', coins: 3500, priceLabel: '\$19.99'),
  ];

  String? _loadingPackageKey;
  bool _handledStripeReturn = false;

  List<Package>? _nativePackages;
  String? _nativeLoadError;
  String? _loadingNativeProductId;

  bool get _nativeIapSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static int? _coinsForNativeProduct(String storeProductId) => _nativeStoreProductCoins[storeProductId];

  @override
  void initState() {
    super.initState();
    _logger.info(
      'CoinPurchaseScreen: initState kIsWeb=$kIsWeb nativeIap=$_nativeIapSupported '
      'defaultTargetPlatform=$defaultTargetPlatform '
      '(web shows Stripe cards; iOS/Android load RevenueCat packages)',
      isOn: LOGGING_SWITCH,
    );
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeHandleStripeReturn());
    } else if (_nativeIapSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadNativeOfferings());
    } else {
      _logger.info(
        'CoinPurchaseScreen: native RevenueCat load skipped (platform is not iOS/Android)—'
        'Buy coins store UI only appears on web (Stripe) or iOS/Android (RevenueCat)',
        isOn: LOGGING_SWITCH,
      );
    }
  }

  Future<void> _loadNativeOfferings() async {
    if (!_nativeIapSupported || !mounted) return;
    setState(() {
      _nativeLoadError = null;
      _nativePackages = null;
    });
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      final raw = current?.availablePackages ?? <Package>[];
      final filtered = raw.where((p) => _coinsForNativeProduct(p.storeProduct.identifier) != null).toList();
      final allSummary = offerings.all.entries
          .map(
            (e) =>
                '${e.key}:[${e.value.availablePackages.map((p) => p.storeProduct.identifier).join(",")}]',
          )
          .join(' | ');
      _logger.info(
        'CoinPurchaseScreen: RevenueCat getOfferings currentId=${current?.identifier} '
        'currentRawCount=${raw.length} filteredCount=${filtered.length} '
        'allowedCatalogIds=${_nativeStoreProductCoins.keys.toList()} '
        'allOfferings=$allSummary',
        isOn: LOGGING_SWITCH,
      );
      if (filtered.isEmpty && raw.isNotEmpty) {
        _logger.warning(
          'CoinPurchaseScreen: RevenueCat packages present but none match app catalog '
          '(store ids vs _nativeStoreProductCoins). rawIds=${raw.map((p) => p.storeProduct.identifier).toList()}',
          isOn: LOGGING_SWITCH,
        );
      }
      if (!mounted) return;
      setState(() {
        _nativePackages = filtered;
        if (filtered.isEmpty) {
          _nativeLoadError = current == null
              ? 'No store offering is set as current in RevenueCat.'
              : 'No coin products in this offering match the app catalog. Check RevenueCat and product IDs.';
        }
      });
    } catch (e) {
      _logger.warning('CoinPurchaseScreen: load native offerings failed: $e', isOn: LOGGING_SWITCH);
      if (!mounted) return;
      setState(() {
        _nativePackages = [];
        _nativeLoadError = 'Could not load store packages. Pull to refresh or try again later.';
      });
    }
  }

  Future<void> _purchaseNativePackage(Package package) async {
    if (!_nativeIapSupported || !mounted) return;
    final auth = AuthManager();
    final userData = auth.getCurrentUserData();
    final loggedIn = userData['isLoggedIn'] == true && (userData['userId']?.toString().isNotEmpty ?? false);
    if (!loggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in to buy coins.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
      return;
    }

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

    final productId = package.storeProduct.identifier;
    final coins = _coinsForNativeProduct(productId);
    if (coins == null) return;

    setState(() => _loadingNativeProductId = productId);
    try {
      final userId = userData['userId']!.toString();
      try {
        await Purchases.logIn(userId);
      } catch (e) {
        _logger.warning('CoinPurchaseScreen: Purchases.logIn failed (continuing): $e', isOn: LOGGING_SWITCH);
      }

      final purchaseResult = await Purchases.purchasePackage(package);
      var storeTxnId = purchaseResult.storeTransaction.transactionIdentifier.trim();
      if (storeTxnId.isEmpty) {
        final txs = purchaseResult.customerInfo.nonSubscriptionTransactions
            .where((t) => t.productIdentifier == productId)
            .toList();
        if (txs.isNotEmpty) {
          storeTxnId = txs.last.transactionIdentifier.trim();
        }
      }
      if (storeTxnId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Purchase completed but receipt id was missing. Contact support with your Play/App receipt.',
                style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
              ),
              backgroundColor: AppColors.primaryColor,
            ),
          );
        }
        return;
      }

      final verified = await _verifyRevenueCatPurchaseWithRetry(
        api: api,
        productIdentifier: productId,
        storeTransactionId: storeTxnId,
      );
      if (!mounted) return;
      if (!verified) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Purchase succeeded but crediting coins is still pending. Tap Buy again in a moment or restart the app.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
        return;
      }

      await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      if (!mounted) return;
      await AnalyticsService.logEvent(
        name: 'coin_native_purchase_completed',
        parameters: {'product_id': productId, 'coins': coins},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $coins coins.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
          backgroundColor: AppColors.primaryColor,
        ),
      );
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return;
      }
      _logger.warning('CoinPurchaseScreen: native purchase failed: $e', isOn: LOGGING_SWITCH);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message ?? 'Purchase failed.',
              style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } catch (e) {
      _logger.error('CoinPurchaseScreen: native purchase error: $e', error: e, isOn: LOGGING_SWITCH);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed. Try again.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingNativeProductId = null);
    }
  }

  /// RevenueCat can lag behind the device; retry verify while the API returns RC_NOT_FOUND / RC_TXN_PENDING / 404.
  Future<bool> _verifyRevenueCatPurchaseWithRetry({
    required ConnectionsApiModule api,
    required String productIdentifier,
    required String storeTransactionId,
  }) async {
    const betweenAttemptsMs = <int>[400, 800, 1200, 2000];
    for (var attempt = 0; attempt < 5; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: betweenAttemptsMs[attempt - 1]));
      }
      final raw = await api.sendPostRequest('/userauth/revenuecat/verify-coin-purchase', {
        'product_identifier': productIdentifier,
        'store_transaction_id': storeTransactionId,
      });
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      _logger.info(
        'CoinPurchaseScreen: verify-coin-purchase attempt=${attempt + 1} success=${map['success']} '
        'code=${map['code']} status=${map['status']}',
        isOn: LOGGING_SWITCH,
      );
      if (map['success'] == true) {
        return true;
      }
      final code = map['code']?.toString();
      final status = map['status'];
      final retryable = status == 404 && (code == 'RC_NOT_FOUND' || code == 'RC_TXN_PENDING');
      if (!retryable) {
        _logger.warning('CoinPurchaseScreen: verify-coin-purchase stop: $map', isOn: LOGGING_SWITCH);
      }
      if (!retryable) {
        return false;
      }
    }
    return false;
  }

  /// Return `success` / `cancel` / `none` by parsing top-level query and hash-query.
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

  /// Stripe expands `{CHECKOUT_SESSION_ID}` in the success URL; read from path query or hash query.
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
    if (!kIsWeb || _handledStripeReturn || !mounted) return;
    final uri = Uri.base;
    final result = _stripeResultInUri(uri);
    _logger.info(
      'CoinPurchaseScreen: return check url=${uri.toString()} '
      'path=${uri.path} query=${uri.query} fragment=${uri.fragment} result=$result',
      isOn: LOGGING_SWITCH,
    );
    if (result == 'none') return;
    if (result == 'cancel') {
      _handledStripeReturn = true;
      await AnalyticsService.logEvent(
        name: 'coin_checkout_return',
        parameters: {'result': 'cancel'},
      );
      _logger.warning('CoinPurchaseScreen: stripe return indicates cancel', isOn: LOGGING_SWITCH);
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
    _logger.info('CoinPurchaseScreen: stripe success detected in return URL', isOn: LOGGING_SWITCH);
    await AnalyticsService.logEvent(
      name: 'coin_checkout_return',
      parameters: {'result': 'success'},
    );
    _handledStripeReturn = true;
    final sessionId = _sessionIdInUri(uri);
    _logger.info('CoinPurchaseScreen: session_id from return URL=$sessionId', isOn: LOGGING_SWITCH);
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
    // Credits are applied in the webhook; on localhost the webhook often never arrives.
    // Ask the API to retrieve the session from Stripe and credit (same idempotent path as webhook).
    if (sessionId != null && sessionId.isNotEmpty) {
      final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
      if (api != null) {
        try {
          final raw = await api.sendPostRequest('/userauth/stripe/verify-coin-checkout-session', {
            'session_id': sessionId,
          });
          _logger.info('CoinPurchaseScreen: verify-coin-checkout-session response=$raw', isOn: LOGGING_SWITCH);
        } catch (e) {
          _logger.warning('CoinPurchaseScreen: verify-coin-checkout-session failed: $e', isOn: LOGGING_SWITCH);
        }
      }
    }
    if (!mounted) return;
    final ok = await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
    _logger.info('CoinPurchaseScreen: user coin refresh result=$ok', isOn: LOGGING_SWITCH);
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
    _logger.info('CoinPurchaseScreen: checkout requested for package=${pack.key}', isOn: LOGGING_SWITCH);
    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (api == null) {
      _logger.warning('CoinPurchaseScreen: ConnectionsApiModule is null', isOn: LOGGING_SWITCH);
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
        _logger.warning(
          'CoinPurchaseScreen: checkout session creation failed: ${map['message'] ?? map['error']}',
          isOn: LOGGING_SWITCH,
        );
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
      _logger.info('CoinPurchaseScreen: launching checkout URL', isOn: LOGGING_SWITCH);
      await AnalyticsService.logEvent(
        name: 'coin_checkout_started',
        parameters: {
          'package_key': pack.key,
          'coins': pack.coins,
        },
      );
      final launched = await ConnectionsApiModule.launchUrl(url);
      if (!launched && mounted) {
        _logger.warning('CoinPurchaseScreen: checkout URL launch failed', isOn: LOGGING_SWITCH);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open checkout. Check popup blocker.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } catch (e) {
      _logger.error('CoinPurchaseScreen: checkout error: $e', error: e, isOn: LOGGING_SWITCH);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout failed. Try again later.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } finally {
      _logger.info('CoinPurchaseScreen: checkout flow finished for package=${pack.key}', isOn: LOGGING_SWITCH);
      if (mounted) setState(() => _loadingPackageKey = null);
    }
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
                  'Each match starts from a 25 coin table fee. Secure checkout is processed by Stripe.',
                  style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                ),
                SizedBox(height: AppPadding.defaultPadding.top),
                ..._recommendedPackages.map(_buildPackageCard),
                SizedBox(height: AppPadding.defaultPadding.top),
              ],
              if (_nativeIapSupported) ...[
                Text('Coin packages', style: AppTextStyles.headingSmall()),
                const SizedBox(height: 8),
                Text(
                  'Purchases are processed by Google Play or the App Store via RevenueCat.',
                  style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
                ),
                SizedBox(height: AppPadding.defaultPadding.top),
                if (_nativePackages == null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_nativeLoadError != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_nativeLoadError!, style: AppTextStyles.bodyMedium(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadNativeOfferings,
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                else
                  ..._nativePackages!.map(_buildNativePackageCard),
                SizedBox(height: AppPadding.defaultPadding.top),
              ],
              Text(
                kIsWeb || _nativeIapSupported
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

  String _formatContext(Map<String, dynamic> m) {
    final buf = StringBuffer();
    for (final e in m.entries) {
      buf.writeln('${e.key}: ${e.value}');
    }
    return buf.toString().trim();
  }

  Widget _buildNativePackageCard(Package package) {
    final id = package.storeProduct.identifier;
    final coins = _coinsForNativeProduct(id)!;
    final busy = _loadingNativeProductId == id;
    final title = package.storeProduct.title.trim().isEmpty ? id : package.storeProduct.title;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppBorderRadius.smallRadius,
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyLarge(color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('$coins coins', style: AppTextStyles.bodyMedium(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(package.storeProduct.priceString, style: AppTextStyles.headingSmall()),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: busy ? null : () => _purchaseNativePackage(package),
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
                Text('${pack.coins} coins', style: AppTextStyles.bodyMedium(color: AppColors.textSecondary)),
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
  final String priceLabel;
  final bool isPopular;

  const _CoinPackage({
    required this.key,
    required this.label,
    required this.coins,
    required this.priceLabel,
    this.isPopular = false,
  });
}
