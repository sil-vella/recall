import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../managers/navigation_manager.dart';

/// App bar feature: envelope icon that navigates to the Notifications screen.
/// Registered globally so it appears on all screens that use the app bar feature slot.
class StateAwareNotificationsFeature extends StatelessWidget {
  const StateAwareNotificationsFeature({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.mail_outline),
      onPressed: () {
        try {
          final navigationManager = Provider.of<NavigationManager>(context, listen: false);
          navigationManager.navigateTo('/notifications');
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Navigation failed: $e')),
          );
        }
      },
      tooltip: 'Notifications',
    );
  }
}
