import 'package:flutter/material.dart';
import '../../../../modules/dutch_game/managers/feature_registry_manager.dart';
import 'coins_display_feature.dart';
import 'notifications_feature.dart';

/// Helper class to register state-aware features
class StateAwareFeatureRegistry {
  /// Register state-aware global app bar features
  static void registerGlobalAppBarFeatures(BuildContext context) {
    // Register coins display feature (app bar actions)
    final coinsFeature = FeatureDescriptor(
      featureId: 'global_coins_display',
      slotId: 'app_bar_actions',
      builder: (context) => const StateAwareCoinsDisplayFeature(),
      priority: 50,
    );
    
    FeatureRegistryManager.instance.register(
      scopeKey: 'global_app_bar',
      feature: coinsFeature,
      context: context,
    );

    // Notifications (bell) icon – navigates to /notifications
    final notificationsFeature = FeatureDescriptor(
      featureId: 'global_notifications',
      slotId: 'app_bar_actions',
      builder: (context) => const StateAwareNotificationsFeature(),
      priority: 75,
    );
    FeatureRegistryManager.instance.register(
      scopeKey: 'global_app_bar',
      feature: notificationsFeature,
      context: context,
    );
  }
  
  /// Unregister global app bar features
  static void unregisterGlobalAppBarFeatures() {
    FeatureRegistryManager.instance.unregister(
      scopeKey: 'global_app_bar',
      featureId: 'global_coins_display',
    );
    FeatureRegistryManager.instance.unregister(
      scopeKey: 'global_app_bar',
      featureId: 'global_notifications',
    );
  }
}
