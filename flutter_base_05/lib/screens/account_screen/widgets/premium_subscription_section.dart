import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../../../core/managers/module_manager.dart';
import '../../../core/managers/state_manager.dart';
import '../../../modules/connections_api_module/connections_api_module.dart';
import '../../../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../../../modules/dutch_game/widgets/ui_kit/dutch_section_header.dart';
import '../../../utils/analytics_service.dart';
import '../../../utils/coin_catalog.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../../utils/play_purchase_token.dart';

/// Google Play Premium subscription: purchase, server verify, and sync.
/// Shown on the Account screen (Android). Coin packs stay on Buy coins.
class PremiumSubscriptionSection extends StatefulWidget {
  const PremiumSubscriptionSection({super.key});

  @override
  State<PremiumSubscriptionSection> createState() => _PremiumSubscriptionSectionState();
}

class _PremiumSubscriptionSectionState extends State<PremiumSubscriptionSection> {
  final InAppPurchase _playIap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _playPurchaseSub;

  bool _playBillingAvailable = false;
  GooglePlayProductDetails? _premiumPlayDetails;
  final Map<String, String> _premiumOfferTokenByBasePlan = {};
  String? _premiumBusyBasePlanId;
  String? _pendingPremiumBasePlanId;
  String? _premiumExpiresAt;
  bool _syncing = false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String? _subscriptionTier() {
    final stats = DutchGameHelpers.getUserDutchGameStats();
    return stats?['subscription_tier']?.toString();
  }

  bool get _isPremium => (_subscriptionTier()?.trim().toLowerCase() ?? '') == 'premium';

  @override
  void initState() {
    super.initState();
    if (_isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapPlayBilling());
    }
  }

  @override
  void dispose() {
    _playPurchaseSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapPlayBilling() async {
    if (!_isAndroid || !mounted) return;
    final ok = await _playIap.isAvailable();
    if (!mounted) return;
    setState(() => _playBillingAvailable = ok);
    if (!ok) return;

    _playPurchaseSub?.cancel();
    _playPurchaseSub = _playIap.purchaseStream.listen(_handlePlayPurchases, onError: (_) {});

    final premId = CoinCatalog.premiumSubscriptionProductId;
    if (premId.isEmpty) return;

    final resp = await _playIap.queryProductDetails({premId});
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

    await _refreshSubscriptionStatus();
    await _restorePlayPurchases(silent: true);
  }

  Future<void> _refreshSubscriptionStatus() async {
    if (!_isAndroid || !mounted) return;
    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (api == null) return;
    try {
      final raw = await api.sendGetRequest('/userauth/play/subscription-status');
      if (raw is! Map || raw['success'] != true) return;
      if (raw['refreshed'] == true) {
        await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      }
      if (!mounted) return;
      final exp = raw['expires_at']?.toString();
      setState(() => _premiumExpiresAt = (exp != null && exp.isNotEmpty) ? exp : null);
    } catch (_) {}
  }

  Future<void> _buyPremiumSubscription(String basePlanId) async {
    final details = _premiumPlayDetails;
    final offerToken = _premiumOfferTokenByBasePlan[basePlanId];
    if (details == null || offerToken == null || offerToken.isEmpty) {
      _showSnack('Premium subscription is not available right now.');
      return;
    }
    setState(() {
      _premiumBusyBasePlanId = basePlanId;
      _pendingPremiumBasePlanId = basePlanId;
    });
    try {
      final param = GooglePlayPurchaseParam(
        productDetails: details,
        offerToken: offerToken,
      );
      final started = await _playIap.buyNonConsumable(purchaseParam: param);
      if (!started) {
        _showSnack('Could not start subscription.');
      }
    } catch (_) {
      _showSnack('Subscription purchase failed. Try again later.');
    } finally {
      if (mounted) setState(() => _premiumBusyBasePlanId = null);
    }
  }

  Future<void> _handlePlayPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != CoinCatalog.premiumSubscriptionProductId) {
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
          await _verifyPlaySubscriptionOnServer(purchase);
          break;
      }
    }
  }

  Future<void> _verifyPlaySubscriptionOnServer(PurchaseDetails purchase) async {
    final token = playPurchaseToken(purchase);
    if (token.isEmpty) {
      if (purchase.pendingCompletePurchase) {
        await _playIap.completePurchase(purchase);
      }
      return;
    }

    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (api == null) {
      _showSnack('Cannot reach server to confirm subscription.');
      return;
    }

    final basePlanId = _pendingPremiumBasePlanId ?? '';
    try {
      final raw = await api.sendPostRequest('/userauth/play/verify-subscription', {
        'purchase_token': token,
        'subscription_id': CoinCatalog.premiumSubscriptionProductId,
        if (basePlanId.isNotEmpty) 'base_plan_id': basePlanId,
      });
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
        await _playIap.completePurchase(purchase);
      }
      _pendingPremiumBasePlanId = null;
      await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
      if (!mounted) return;
      final exp = map['expires_at']?.toString();
      setState(() => _premiumExpiresAt = (exp != null && exp.isNotEmpty) ? exp : null);
      _showSnack(
        'Premium active. Ads are off and coin packs include +${CoinCatalog.subscriberCoinBonusPercent}%.',
      );
      await AnalyticsService.logEvent(name: 'play_premium_subscription_verified');
    } catch (_) {
      _showSnack('Could not verify subscription. Tap Sync below to retry.');
    }
  }

  Future<void> _restorePlayPurchases({bool silent = false}) async {
    if (!_isAndroid || _syncing) return;
    setState(() => _syncing = true);
    try {
      await _playIap.restorePurchases();
      await _refreshSubscriptionStatus();
      if (!mounted || silent) return;
      _showSnack(
        _isPremium
            ? 'Subscription synced.'
            : 'Checked Google Play. If you subscribed, tap Sync again after a moment.',
      );
    } catch (_) {
      if (!silent && mounted) {
        _showSnack('Could not restore purchases from Google Play.');
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

  String _priceForBasePlan(String basePlanId) {
    final details = _premiumPlayDetails;
    if (details == null || basePlanId.isEmpty) return '—';
    final offers = details.productDetails.subscriptionOfferDetails ?? [];
    for (final offer in offers) {
      if (offer.basePlanId == basePlanId) {
        final phases = offer.pricingPhases;
        if (phases.isNotEmpty) {
          return phases.first.formattedPrice;
        }
      }
    }
    return details.price;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _card(
        child: Text(
          'Premium subscription (ad-free + bonus coins) is available on the Android app via Google Play.',
          style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
        ),
      );
    }

    if (!_isAndroid) {
      return _card(
        child: Text(
          'Premium subscription is available on Android via Google Play.',
          style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
        ),
      );
    }

    if (!_playBillingAvailable) {
      return _card(
        child: Text(
          'Google Play Billing is not available on this device.',
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentColor.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardVariant,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
        Text('Premium active', style: AppTextStyles.headingSmall()),
        const SizedBox(height: 6),
        Text(
          CoinCatalog.premiumBenefitsShort,
          style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
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
            'https://play.google.com/store/account/subscriptions',
          ),
          child: const Text('Manage on Google Play'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _syncing ? null : () => _restorePlayPurchases(),
          child: _syncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sync subscription with server'),
        ),
      ],
    );
  }

  Widget _buildPremiumSubscribeContent() {
    final monthlyPlan = CoinCatalog.premiumBasePlanMonthly;
    final yearlyPlan = CoinCatalog.premiumBasePlanYearly;
    final prem = _premiumPlayDetails;
    final monthlyPrice = prem != null ? _priceForBasePlan(monthlyPlan) : '—';
    final yearlyPrice = prem != null ? _priceForBasePlan(yearlyPlan) : '—';
    final bonus = CoinCatalog.subscriberCoinBonusPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          CoinCatalog.premiumBenefitsShort,
          style: AppTextStyles.bodyMedium(color: AppColors.textSecondary),
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
                onPressed: (_premiumBusyBasePlanId != null || prem == null)
                    ? null
                    : () => _buyPremiumSubscription(monthlyPlan),
                child: _premiumBusyBasePlanId == monthlyPlan
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
                onPressed: (_premiumBusyBasePlanId != null || prem == null)
                    ? null
                    : () => _buyPremiumSubscription(yearlyPlan),
                child: _premiumBusyBasePlanId == yearlyPlan
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
          onPressed: _syncing ? null : () => _restorePlayPurchases(),
          child: _syncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Already subscribed? Sync with server'),
        ),
      ],
    );
  }
}
