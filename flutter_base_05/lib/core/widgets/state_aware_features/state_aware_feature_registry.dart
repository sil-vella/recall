import 'package:flutter/material.dart';
import '../../../../modules/cleco_game/managers/feature_registry_manager.dart';
import 'connection_status_feature.dart';

/// Helper class to register state-aware features
class StateAwareFeatureRegistry {
  /// Register state-aware global app bar features
  static void registerGlobalAppBarFeatures(BuildContext context) {
    
    // Register connection status feature
    final connectionFeature = FeatureDescriptor(
      featureId: 'global_connection_status',
      slotId: 'app_bar_actions',
      builder: (context) => const StateAwareConnectionStatusFeature(),
      priority: 100, // Highest priority - appears last (rightmost)
    );
    
    // Register features with global scope
    FeatureRegistryManager.instance.register(
      scopeKey: 'global_app_bar',
      feature: connectionFeature,
      context: context,
    );
  }
  
  /// Unregister global app bar features
  static void unregisterGlobalAppBarFeatures() {
    FeatureRegistryManager.instance.unregister(
      scopeKey: 'global_app_bar',
      featureId: 'global_connection_status',
    );
  }
}
