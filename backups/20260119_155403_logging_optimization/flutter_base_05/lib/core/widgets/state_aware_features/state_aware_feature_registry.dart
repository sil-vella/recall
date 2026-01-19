import 'package:flutter/material.dart';
import '../../../../modules/dutch_game/managers/feature_registry_manager.dart';
import 'connection_status_feature.dart';
import 'coins_display_feature.dart';
import '../../../tools/logging/logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false;

/// Helper class to register state-aware features
class StateAwareFeatureRegistry {
  static final Logger _logger = Logger();
  
  /// Register state-aware global app bar features
  static void registerGlobalAppBarFeatures(BuildContext context) {
    _logger.info('🔧 StateAwareFeatureRegistry: Registering global app bar features', isOn: LOGGING_SWITCH);
    
    // Register coins display feature (appears first, leftmost)
    final coinsFeature = FeatureDescriptor(
      featureId: 'global_coins_display',
      slotId: 'app_bar_actions',
      builder: (context) => const StateAwareCoinsDisplayFeature(),
      priority: 50, // Medium priority - appears before connection status
    );
    
    _logger.info('🔧 StateAwareFeatureRegistry: Registering coins display feature', isOn: LOGGING_SWITCH);
    
    // Register connection status feature (appears last, rightmost)
    final connectionFeature = FeatureDescriptor(
      featureId: 'global_connection_status',
      slotId: 'app_bar_actions',
      builder: (context) => const StateAwareConnectionStatusFeature(),
      priority: 100, // Highest priority - appears last (rightmost)
    );
    
    // Register features with global scope
    FeatureRegistryManager.instance.register(
      scopeKey: 'global_app_bar',
      feature: coinsFeature,
      context: context,
    );
    
    _logger.info('✅ StateAwareFeatureRegistry: Coins feature registered with scope: global_app_bar', isOn: LOGGING_SWITCH);
    
    FeatureRegistryManager.instance.register(
      scopeKey: 'global_app_bar',
      feature: connectionFeature,
      context: context,
    );
    
    _logger.info('✅ StateAwareFeatureRegistry: All global app bar features registered', isOn: LOGGING_SWITCH);
  }
  
  /// Unregister global app bar features
  static void unregisterGlobalAppBarFeatures() {
    FeatureRegistryManager.instance.unregister(
      scopeKey: 'global_app_bar',
      featureId: 'global_coins_display',
    );
    
    FeatureRegistryManager.instance.unregister(
      scopeKey: 'global_app_bar',
      featureId: 'global_connection_status',
    );
  }
}
