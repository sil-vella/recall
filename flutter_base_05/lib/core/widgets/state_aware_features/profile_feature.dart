import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../managers/state_manager.dart';
import '../../managers/navigation_manager.dart';
import '../../../tools/logging/logger.dart';

/// State-aware profile feature widget
/// 
/// This widget subscribes to the login state slice and updates dynamically
/// when the user's profile information changes.
class StateAwareProfileFeature extends StatelessWidget {
  static final Logger _log = Logger();
  
  const StateAwareProfileFeature({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get login state from StateManager
        final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
        final isLoggedIn = loginState['isLoggedIn'] == true;
        final username = loginState['username']?.toString() ?? 'Guest';
        
        _log.info('👤 StateAwareProfileFeature: isLoggedIn=$isLoggedIn, username=$username');
        
        return IconButton(
          icon: const Icon(Icons.account_circle),
          onPressed: () {
            try {
              final navigationManager = Provider.of<NavigationManager>(context, listen: false);
              navigationManager.navigateTo('/account');
            } catch (e) {
              _log.error('❌ Navigation error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Navigation failed: $e')),
              );
            }
          },
          tooltip: isLoggedIn ? 'Account Settings - $username' : 'Account Settings',
        );
      },
    );
  }
}
