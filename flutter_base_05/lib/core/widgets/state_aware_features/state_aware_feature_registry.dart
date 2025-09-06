import 'package:flutter/material.dart';
import '../../../../modules/recall_game/managers/feature_registry_manager.dart';
import 'connection_status_feature.dart';
import 'profile_feature.dart';

/// Helper class to register state-aware features
class StateAwareFeatureRegistry {
  /// Register state-aware global app bar features
  static void registerGlobalAppBarFeatures(BuildContext context) {
    
    // Register connection status feature
    final connectionFeature = FeatureDescriptor(
      featureId: 'global_connection_status',
      slotId: 'app_bar_actions',
      builder: (context) => const StateAwareConnectionStatusFeature(),
      priority: 10, // Highest priority - appears first
    );
    
    // Register profile feature
    final profileFeature = FeatureDescriptor(
      featureId: 'global_profile',
      slotId: 'app_bar_actions',
      builder: (context) => const StateAwareProfileFeature(),
      priority: 20, // Second priority - appears after connection status
    );
    
    // Register features with global scope
    FeatureRegistryManager.instance.register(
      scopeKey: 'global_app_bar',
      feature: connectionFeature,
      context: context,
    );
    
    FeatureRegistryManager.instance.register(
      scopeKey: 'global_app_bar',
      feature: profileFeature,
      context: context,
    );
  }
  
  /// Unregister global app bar features
  static void unregisterGlobalAppBarFeatures() {
    FeatureRegistryManager.instance.unregister(
      scopeKey: 'global_app_bar',
      featureId: 'global_connection_status',
    );
    
    FeatureRegistryManager.instance.unregister(
      scopeKey: 'global_app_bar',
      featureId: 'global_profile',
    );
  }
}
