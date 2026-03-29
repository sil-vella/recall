import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/00_base/screen_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../../tools/logging/logger.dart';
import '../../utils/consts/theme_consts.dart';

const bool LOGGING_SWITCH = true; // Coin purchase flow debugging (enable-logging-switch.mdc)

/// Coin purchases on **web**: Stripe Checkout via Python `/userauth/stripe/create-coin-checkout-session`.
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

  static const List<_CoinPackage> _recommendedPackages = [
    _CoinPackage(key: 'starter', label: 'Starter', coins: 100, priceLabel: '\$0.99'),
    _CoinPackage(key: 'casual', label: 'Casual', coins: 300, priceLabel: '\$2.49'),
    _CoinPackage(key: 'popular', label: 'Popular', coins: 700, priceLabel: '\$4.99', isPopular: true),
    _CoinPackage(key: 'grinder', label: 'Grinder', coins: 1500, priceLabel: '\$9.99'),
    _CoinPackage(key: 'pro', label: 'Pro', coins: 3500, priceLabel: '\$19.99'),
  ];

  String? _loadingPackageKey;
  bool _handledStripeReturn = false;

  @override
  void initState() {
    super.initState();
    if (LOGGING_SWITCH) {
      _logger.info('CoinPurchaseScreen: initState (kIsWeb=$kIsWeb)');
    }
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeHandleStripeReturn());
    }
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
    if (LOGGING_SWITCH) {
      _logger.info(
        'CoinPurchaseScreen: return check url=${uri.toString()} '
        'path=${uri.path} query=${uri.query} fragment=${uri.fragment} result=$result',
      );
    }
    if (result == 'none') return;
    if (result == 'cancel') {
      _handledStripeReturn = true;
      if (LOGGING_SWITCH) {
        _logger.warning('CoinPurchaseScreen: stripe return indicates cancel');
      }
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
    if (LOGGING_SWITCH) {
      _logger.info('CoinPurchaseScreen: stripe success detected in return URL');
    }
    _handledStripeReturn = true;
    final sessionId = _sessionIdInUri(uri);
    if (LOGGING_SWITCH) {
      _logger.info('CoinPurchaseScreen: session_id from return URL=$sessionId');
    }
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
          if (LOGGING_SWITCH) {
            _logger.info('CoinPurchaseScreen: verify-coin-checkout-session response=$raw');
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.warning('CoinPurchaseScreen: verify-coin-checkout-session failed: $e');
          }
        }
      }
    }
    if (!mounted) return;
    final ok = await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
    if (LOGGING_SWITCH) {
      _logger.info('CoinPurchaseScreen: user coin refresh result=$ok');
    }
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
    if (LOGGING_SWITCH) {
      _logger.info('CoinPurchaseScreen: checkout requested for package=${pack.key}');
    }
    final api = ModuleManager().getModuleByType<ConnectionsApiModule>();
    if (api == null) {
      if (LOGGING_SWITCH) {
        _logger.warning('CoinPurchaseScreen: ConnectionsApiModule is null');
      }
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
        if (LOGGING_SWITCH) {
          _logger.warning('CoinPurchaseScreen: checkout session creation failed: ${map['message'] ?? map['error']}');
        }
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
      if (LOGGING_SWITCH) {
        _logger.info('CoinPurchaseScreen: launching checkout URL');
      }
      final launched = await ConnectionsApiModule.launchUrl(url);
      if (!launched && mounted) {
        if (LOGGING_SWITCH) {
          _logger.warning('CoinPurchaseScreen: checkout URL launch failed');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open checkout. Check popup blocker.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('CoinPurchaseScreen: checkout error: $e', error: e);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout failed. Try again later.', style: AppTextStyles.bodyMedium(color: AppColors.textOnPrimary)),
            backgroundColor: AppColors.primaryColor,
          ),
        );
      }
    } finally {
      if (LOGGING_SWITCH) {
        _logger.info('CoinPurchaseScreen: checkout flow finished for package=${pack.key}');
      }
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
              Text(
                kIsWeb
                    ? 'Join attempt details (debug / support):'
                    : 'Coin purchases are not available yet. Below is the join attempt data from the server (for debugging / future checkout).',
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
