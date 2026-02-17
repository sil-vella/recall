import 'package:flutter/material.dart';
import '../../../../modules/dutch_game/managers/feature_registry_manager.dart';
import 'coins_display_feature.dart';
import '../../../tools/logging/logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false;

/// Helper class to register state-aware features
class StateAwareFeatureRegistry {
  static final Logger _logger = Logger();
  
  /// Register state-aware global app bar features
  static void registerGlobalAppBarFeatures(BuildContext context) {
    if (LOGGING_SWITCH) {
      _logger.info('🔧 StateAwareFeatureRegistry: Registering global app bar features');
    }
    
    // Register coins display feature (app bar actions)
    final coinsFeature = FeatureDescriptor(
      featureId: 'global_coins_display',
      slotId: 'app_bar_actions',
      builder: (context) => const StateAwareCoinsDisplayFeature(),
      priority: 50,
    );
    
    if (LOGGING_SWITCH) {
      _logger.info('🔧 StateAwareFeatureRegistry: Registering coins display feature');
    }
    
    FeatureRegistryManager.instance.register(
      scopeKey: 'global_app_bar',
      feature: coinsFeature,
      context: context,
    );
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ StateAwareFeatureRegistry: Coins feature registered with scope: global_app_bar');
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ StateAwareFeatureRegistry: All global app bar features registered');
    }
  }
  
  /// Unregister global app bar features
  static void unregisterGlobalAppBarFeatures() {
    FeatureRegistryManager.instance.unregister(
      scopeKey: 'global_app_bar',
      featureId: 'global_coins_display',
    );
  }
}
