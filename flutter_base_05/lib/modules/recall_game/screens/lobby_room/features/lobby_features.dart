import 'package:flutter/material.dart';
import '../../../managers/feature_registry_manager.dart';
import '../../../../../tools/logging/logger.dart';

/// Scope and slot constants for the lobby screen
class LobbyFeatureSlots {
  // Must match BaseScreen's FeatureSlot scopeKey for LobbyScreen
  static const String scopeKey = 'LobbyScreen';
  // Use 'header' to integrate with BaseScreen's global header slot
  static const String slotTopInline = 'header';
  static const String slotSecondary = 'secondary_band';
}

/// Registers default lobby features into the registry for this screen scope
class LobbyFeatureRegistrar {
  static final Logger _log = Logger();
  final FeatureRegistryManager _registry = FeatureRegistryManager.instance;

  void registerDefaults(BuildContext context) {
    _log.info('🎮 LobbyFeatureRegistrar: No features to register');
    // Feature registration removed - notices widget will be empty
  }

  void unregisterAll() {
    _log.info('🎮 LobbyFeatureRegistrar: Unregistering all features');
    _registry.clearScope(LobbyFeatureSlots.scopeKey);
  }
}




