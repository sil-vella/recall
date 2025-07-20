import 'package:flutter/material.dart';
import '../../../core/00_base/screen_base.dart';

/// Screen for managing subscriptions
/// TODO: Implement subscription management functionality
class SubscriptionScreen extends BaseScreen {
  const SubscriptionScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Subscriptions';

  @override
  BaseScreenState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends BaseScreenState<SubscriptionScreen> {
  @override
  Widget buildContent(BuildContext context) {
    return buildContentCard(
      context,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.subscriptions_outlined,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'Subscription Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Coming Soon',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 24),
          Text(
            'This screen will allow users to:\n'
            '• View active subscriptions\n'
            '• Manage subscription settings\n'
            '• Cancel or upgrade subscriptions\n'
            '• View billing history',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
} 