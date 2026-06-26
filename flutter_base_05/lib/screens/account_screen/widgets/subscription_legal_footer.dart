import 'package:flutter/material.dart';

import '../../../modules/connections_api_module/connections_api_module.dart';
import '../../../utils/consts/config.dart';
import '../../../utils/consts/theme_consts.dart';

/// Required subscription disclosures (App Store 3.1.2): title, duration, price, auto-renew, legal links.
class SubscriptionLegalFooter extends StatelessWidget {
  const SubscriptionLegalFooter({
    super.key,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.productsReady,
  });

  final String monthlyPrice;
  final String yearlyPrice;
  final bool productsReady;

  @override
  Widget build(BuildContext context) {
    final monthlyDisplay = productsReady ? monthlyPrice : '—';
    final yearlyDisplay = productsReady ? yearlyPrice : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Dutch Premium (Monthly): 1 month — $monthlyDisplay\n'
          'Dutch Premium (Yearly): 1 year — $yearlyDisplay',
          style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          'Payment is charged to your App Store or Google Play account at confirmation. '
          'Subscription renews automatically unless canceled at least 24 hours before the end of the current period. '
          'Manage or cancel in your store account settings.',
          style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _LegalLink(
              label: 'Privacy Policy',
              url: Config.privacyPolicyUrl,
              semanticId: 'premium_link_privacy_policy',
            ),
            _LegalLink(
              label: 'Terms of Use (EULA)',
              url: Config.termsOfUseUrl,
              semanticId: 'premium_link_terms_of_use',
            ),
          ],
        ),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.url,
    required this.semanticId,
  });

  final String label;
  final String url;
  final String semanticId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: semanticId,
      button: true,
      child: InkWell(
        onTap: () => ConnectionsApiModule.launchUrl(url),
        child: Text(
          label,
          style: AppTextStyles.bodySmall(color: AppColors.accentColor).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: AppColors.accentColor,
          ),
        ),
      ),
    );
  }
}
