import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../../../core/managers/module_manager.dart';
import '../../../modules/login_module/login_module.dart';
import '../../../core/managers/state_manager.dart';
import '../../../modules/connections_api_module/connections_api_module.dart';
import '../../../modules/dutch_game/utils/dutch_firebase_analytics.dart';
import '../../../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../../../modules/dutch_game/widgets/ui_kit/dutch_section_header.dart';
import 'account_panel_style.dart';
import '../../../utils/analytics_service.dart';
import '../../../utils/coin_catalog.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../../utils/iap_session_helper.dart';
import '../../../utils/play_purchase_token.dart';
import 'subscription_legal_footer.dart';

/// Native store Premium subscription: purchase, server verify, and sync.
/// Android: Google Play `premium_subscription` SKU + base plans.
/// iOS: App Store `premium_auto_renew_monthly` / `premium_auto_renew_yearly`.
class PremiumSubscriptionSection extends StatefulWidget {
  const PremiumSubscriptionSection({super.key});

  @override
  State<PremiumSubscriptionSection> createState() => _PremiumSubscriptionSectionState();
}

class _PremiumSubscriptionSectionState extends State<PremiumSubscriptionSection> {
  final InAppPurchase _storeIap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _storeBillingAvailable = false;
  GooglePlayProductDetails? _premiumPlayDetails;
  final Map<String, String> _premiumOfferTokenByBasePlan = {};
  final Map<String, ProductDetails> _applePremiumDetails = {};
  String? _premiumBusyPlanKey;
  String? _pendingPremiumPlanKey;
  String? _premiumExpiresAt;
  bool _syncing = false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get _isNativeStore => _isAndroid || _isIos;

  String? _subscriptionTier() {
    final stats = DutchGameHelpers.getUserDutchGameStats();
    return stats?['subscription_tier']?.toString();
  }

  bool get _isPremium => (_subscriptionTier()?.trim().toLowerCase() ?? '') == 'premium';

  String get _monthlyPlanKey => _isIos ? CoinCatalog.premiumAppleProductIdMonthly : CoinCatalog.premiumBasePlanMonthly;

  String get _yearlyPlanKey => _isIos ? CoinCatalog.premiumAppleProductIdYearly : CoinCatalog.premiumBasePlanYearly;

  Set<String> get _premiumProductIds {
    if (_isIos) {
      return {_monthlyPlanKey, _yearlyPlanKey}.where((id) => id.isNotEmpty).toSet();
    }
    final playId = CoinCatalog.premiumSubscriptionProductId;
    return playId.isEmpty ? {} : {playId};
  }

  @override
  void initState() {
    super.initState();
    if (_isNativeStore) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapNativeStoreBilling());
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapNativeStoreBilling() async {
    if (!_isNativeStore || !mounted) return;
    final ok = await _storeIap.isAvailable();
    if (!mounted) return;
    setState(() => _storeBillingAvailable = ok);
    if (!ok) return;

    _purchaseSub?.cancel();
    _purchaseSub = _storeIap.purchaseStream.listen(_handleStorePurchases, onError: (_) {});

    if (_isAndroid) {
      await _loadAndroidPremiumProducts();
    } else if (_isIos) {
      await _loadIosPremiumProducts();
    }

    await _refreshSubscriptionStatus();
    await _restoreStorePurchases(silent: true);
  }

  Future<void> _loadAndroidPremiumProducts() async {
    final premId = CoinCatalog.premiumSubscriptionProductId;
    if (premId.isEmpty) return;

    final resp = await _storeIap.queryProductDetails({premId});
    if (!mounted) return;

    GooglePlayProductDetails? premDetails;
    final offerTokens = <String, String>{};
    for (final p in resp.productDetails) {
      if (p.id == premId && p is GooglePlayProductDetails) {
        premDetails = p;
        final offers = p.productDetails.subscriptionOfferDetails ?? [];
        for (final offer in offers) {
          final basePlan = offer.basePlanId;
          if (basePlan.isNotEmpty) {
            offerTokens[basePlan] = offer.offerIdToken;
          }
        }
      }
    }

    setState(() {
      _premiumPlayDetails = premDetails;
      _premiumOfferTokenByBasePlan
        ..clear()
        ..addAll(offerTokens);
    });
  }

  Future<void> _loadIosPremiumProducts() async {
    final ids = _premiumProductIds;
    if (ids.isEmpty) return;

    final resp = await _storeIap.queryProductDetails(ids);
    if (!mounted) return;

    final map = <String, ProductDetails>{};
    for (final p in resp.productDetails) {
      map[p.id] = p;
    }
    setState(() {
      _applePremiumDetails
        ..clear()
        ..addAll(map);
    });
  }

  Future<void> _refreshSubscriptionStatus() async {
    if (!_isNativeStore || !mounted) return;
    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (api == null) return;
    final wasPremium = _isPremium;
    final endpoint = _isIos ? '/userauth/apple/subscription-status' : '/userauth/play/subscription-status';
    try {
      final raw = await api.sendGetRequest(endpoint);
      if (raw is! Map || raw['success'] != true) return;
      final refreshed = raw['refreshed'] == true;
      if (refreshed) {
        await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      }
      if (!mounted) return;
      final tier = raw['subscription_tier']?.toString().trim().toLowerCase() ?? '';
      final isNowPremium = tier == 'premium';
      if (wasPremium && refreshed && !isNowPremium) {
        unawaited(DutchFirebaseAnalytics.logPremiumSubscriptionCanceled(
          isIos: _isIos,
          reason: 'lapsed',
        ));
      }
      final exp = raw['expires_at']?.toString();
      setState(() => _premiumExpiresAt = (exp != null && exp.isNotEmpty) ? exp : null);
    } catch (_) {}
  }

  Future<void> _buyPremiumSubscription(String planKey) async {
    setState(() {
      _premiumBusyPlanKey = planKey;
      _pendingPremiumPlanKey = planKey;
    });
    try {
      final sessionOk = await IapSessionHelper.ensureSessionForPurchase(
        context: context,
        guestProvisionSource: 'iap_premium',
      );
      if (!sessionOk) {
        _showSnack('Could not start purchase. Check your connection and try again.');
        return;
      }

      if (_isAndroid) {
        final details = _premiumPlayDetails;
        final offerToken = _premiumOfferTokenByBasePlan[planKey];
        if (details == null || offerToken == null || offerToken.isEmpty) {
          _showSnack('Premium subscription is not available right now.');
          return;
        }
        final param = GooglePlayPurchaseParam(
          productDetails: details,
          offerToken: offerToken,
        );
        final started = await _storeIap.buyNonConsumable(purchaseParam: param);
        if (!started) {
          _showSnack('Could not start subscription.');
        }
        return;
      }

      if (_isIos) {
        final details = _applePremiumDetails[planKey];
        if (details == null) {
          _showSnack('Premium subscription is not available right now.');
          return;
        }
        final started = await _storeIap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: details),
        );
        if (!started) {
          _showSnack('Could not start subscription.');
        }
      }
    } catch (_) {
      _showSnack('Subscription purchase failed. Try again later.');
    } finally {
      if (mounted) setState(() => _premiumBusyPlanKey = null);
    }
  }

  Future<void> _handleStorePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!_premiumProductIds.contains(purchase.productID)) {
        continue;
      }
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.error:
          if (purchase.error != null) {
            _showSnack(purchase.error!.message);
          }
          if (purchase.pendingCompletePurchase) {
            await _storeIap.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.canceled:
          unawaited(DutchFirebaseAnalytics.logPremiumSubscriptionCanceled(
            isIos: _isIos,
            reason: 'purchase_sheet',
            productId: purchase.productID,
          ));
          if (purchase.pendingCompletePurchase) {
            await _storeIap.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifySubscriptionOnServer(purchase);
          break;
      }
    }
  }

  Future<void> _verifySubscriptionOnServer(PurchaseDetails purchase) async {
    final loginModule = ModuleManager().getModuleByType<LoginModule>();
    if (loginModule != null && !await loginModule.hasValidToken()) {
      if (!mounted) return;
      final sessionOk = await IapSessionHelper.ensureSessionForPurchase(
        context: context,
        guestProvisionSource: 'iap_premium',
      );
      if (!sessionOk) {
        _showSnack('Could not verify subscription. Tap Sync to retry.');
        return;
      }
    }

    final productId = _isIos ? purchase.productID : CoinCatalog.premiumSubscriptionProductId;
    final verifyFields = nativeSubscriptionVerifyBody(purchase, productId: productId);
    if (verifyFields.isEmpty || !verifyFields.containsKey('product_id')) {
      if (purchase.pendingCompletePurchase) {
        await _storeIap.completePurchase(purchase);
      }
      return;
    }

    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (api == null) {
      _showSnack('Cannot reach server to confirm subscription.');
      return;
    }

    final endpoint = _isIos ? '/userauth/apple/verify-subscription' : '/userauth/play/verify-subscription';
    final body = Map<String, dynamic>.from(verifyFields);
    if (_isAndroid) {
      body['subscription_id'] = CoinCatalog.premiumSubscriptionProductId;
      final basePlanId = _pendingPremiumPlanKey ?? '';
      if (basePlanId.isNotEmpty) {
        body['base_plan_id'] = basePlanId;
      }
    }

    try {
      final raw = await api.sendPostRequest(endpoint, body);
      if (raw is! Map) {
        throw Exception('Unexpected response');
      }
      final map = Map<String, dynamic>.from(raw);
      if (map['success'] != true) {
        final err = map['error']?.toString() ?? 'Subscription verification failed';
        final hint = map['message']?.toString();
        final msg = (hint != null && hint.isNotEmpty) ? '$err — $hint' : err;
        _showSnack(msg);
        return;
      }

      if (purchase.pendingCompletePurchase) {
        await _storeIap.completePurchase(purchase);
      }
      _pendingPremiumPlanKey = null;
      await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      if (!mounted) return;
      final exp = map['expires_at']?.toString();
      setState(() => _premiumExpiresAt = (exp != null && exp.isNotEmpty) ? exp : null);
      _showSnack(
        'Premium active. Ads are off and coin packs include +${CoinCatalog.subscriberCoinBonusPercent}%.',
      );
      await AnalyticsService.logEvent(
        name: _isIos ? 'apple_premium_subscription_verified' : 'play_premium_subscription_verified',
      );
    } catch (_) {
      _showSnack('Could not verify subscription. Tap Sync below to retry.');
    }
  }

  Future<void> _restoreStorePurchases({bool silent = false}) async {
    if (!_isNativeStore || _syncing) return;

    if (!silent) {
      final sessionOk = await IapSessionHelper.ensureSessionForPurchase(
        context: context,
        guestProvisionSource: 'iap_premium',
      );
      if (!sessionOk) {
        _showSnack('Could not sync subscription. Check your connection and try again.');
        return;
      }
    }

    setState(() => _syncing = true);
    try {
      await _storeIap.restorePurchases();
      await _refreshSubscriptionStatus();
      if (!mounted || silent) return;
      _showSnack(
        _isPremium
            ? 'Subscription synced.'
            : _isIos
                ? 'Checked the App Store. If you subscribed, tap Sync again after a moment.'
                : 'Checked Google Play. If you subscribed, tap Sync again after a moment.',
      );
    } catch (_) {
      if (!silent && mounted) {
        _showSnack(_isIos ? 'Could not restore purchases from the App Store.' : 'Could not restore purchases from Google Play.');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary),
        ),
        backgroundColor: AppColors.primaryColor,
      ),
    );
  }

  String _priceForPlan(String planKey) {
    if (_isIos) {
      return _applePremiumDetails[planKey]?.price ?? '—';
    }
    final details = _premiumPlayDetails;
    if (details == null || planKey.isEmpty) return '—';
    final offers = details.productDetails.subscriptionOfferDetails ?? [];
    for (final offer in offers) {
      if (offer.basePlanId == planKey) {
        final phases = offer.pricingPhases;
        if (phases.isNotEmpty) {
          return phases.first.formattedPrice;
        }
      }
    }
    return details.price;
  }

  bool get _premiumProductsReady {
    if (_isIos) {
      return _applePremiumDetails.containsKey(_monthlyPlanKey) ||
          _applePremiumDetails.containsKey(_yearlyPlanKey);
    }
    return _premiumPlayDetails != null;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _card(
        child: Text(
          'Premium subscription (ad-free + bonus coins) is available in the mobile app via Google Play or the App Store.',
          style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
        ),
      );
    }

    if (!_isNativeStore) {
      return _card(
        child: Text(
          'Premium subscription is available on Android and iOS.',
          style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
        ),
      );
    }

    if (!_storeBillingAvailable) {
      return _card(
        child: Text(
          _isIos
              ? 'App Store billing is not available on this device.'
              : 'Google Play Billing is not available on this device.',
          style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
        ),
      );
    }

    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, _) {
        return Semantics(
          identifier: 'account_premium_section',
          container: true,
          child: _card(
            child: _isPremium ? _buildPremiumActiveContent() : _buildPremiumSubscribeContent(),
          ),
        );
      },
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: accountPanelDecoration(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DutchSectionHeader(
            title: 'Premium',
            icon: Icons.workspace_premium_outlined,
            semanticIdentifier: 'account_premium_header',
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildPremiumActiveContent() {
    final exp = _premiumExpiresAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Premium active',
          style: AppTextStyles.headingSmall(color: AppColors.white),
        ),
        const SizedBox(height: 6),
        Text(
          CoinCatalog.premiumBenefitsShort,
          style: AppTextStyles.bodyMedium(color: AppColors.white.withValues(alpha: 0.88)),
        ),
        if (exp != null && exp.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Renews / expires: $exp',
            style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => ConnectionsApiModule.launchUrl(
            _isIos
                ? 'https://apps.apple.com/account/subscriptions'
                : 'https://play.google.com/store/account/subscriptions',
          ),
          style: accountPanelOutlinedButtonStyle(),
          child: Text(_isIos ? 'Manage on App Store' : 'Manage on Google Play'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _syncing ? null : () => _restoreStorePurchases(),
          style: accountPanelOutlinedButtonStyle(),
          child: _syncing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accentColor,
                  ),
                )
              : const Text('Sync subscription with server'),
        ),
        _buildLegalFooter(),
      ],
    );
  }

  Widget _buildLegalFooter() {
    final monthlyPrice = _premiumProductsReady ? _priceForPlan(_monthlyPlanKey) : '—';
    final yearlyPrice = _premiumProductsReady ? _priceForPlan(_yearlyPlanKey) : '—';
    return SubscriptionLegalFooter(
      monthlyPrice: monthlyPrice,
      yearlyPrice: yearlyPrice,
      productsReady: _premiumProductsReady,
    );
  }

  Widget _buildPremiumSubscribeContent() {
    final monthlyPlan = _monthlyPlanKey;
    final yearlyPlan = _yearlyPlanKey;
    final monthlyPrice = _premiumProductsReady ? _priceForPlan(monthlyPlan) : '—';
    final yearlyPrice = _premiumProductsReady ? _priceForPlan(yearlyPlan) : '—';
    final bonus = CoinCatalog.subscriberCoinBonusPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          CoinCatalog.premiumBenefitsShort,
          style: AppTextStyles.bodyMedium(color: AppColors.white.withValues(alpha: 0.88)),
        ),
        const SizedBox(height: 4),
        Text(
          '• Ad-free app experience\n• +$bonus% coins on every coin pack',
          style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentColor,
                  foregroundColor: AppColors.white,
                  disabledBackgroundColor: AppColors.accentColor.withValues(alpha: 0.45),
                  disabledForegroundColor: AppColors.white.withValues(alpha: 0.6),
                ),
                onPressed: (_premiumBusyPlanKey != null || !_premiumProductsReady)
                    ? null
                    : () => _buyPremiumSubscription(monthlyPlan),
                child: _premiumBusyPlanKey == monthlyPlan
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textOnPrimary,
                        ),
                      )
                    : Text('Monthly\n$monthlyPrice', textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentColor,
                  foregroundColor: AppColors.white,
                  disabledBackgroundColor: AppColors.accentColor.withValues(alpha: 0.45),
                  disabledForegroundColor: AppColors.white.withValues(alpha: 0.6),
                ),
                onPressed: (_premiumBusyPlanKey != null || !_premiumProductsReady)
                    ? null
                    : () => _buyPremiumSubscription(yearlyPlan),
                child: _premiumBusyPlanKey == yearlyPlan
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textOnPrimary,
                        ),
                      )
                    : Text('Yearly\n$yearlyPrice', textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _syncing ? null : () => _restoreStorePurchases(),
          style: accountPanelOutlinedButtonStyle(),
          child: _syncing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accentColor,
                  ),
                )
              : const Text('Already subscribed? Sync with server'),
        ),
        _buildLegalFooter(),
      ],
    );
  }
}
