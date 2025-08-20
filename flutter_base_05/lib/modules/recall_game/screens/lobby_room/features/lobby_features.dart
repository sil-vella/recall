import 'package:flutter/material.dart';
import '../../../managers/feature_registry_manager.dart';
import '../../../managers/feature_contracts.dart';
import '../../../../../utils/consts/theme_consts.dart';
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
    _log.info('🎮 LobbyFeatureRegistrar: Registering default features');
    
    // Example Feature: Connection hint banner
    _registry.register(
      scopeKey: LobbyFeatureSlots.scopeKey,
      feature: FeatureDescriptor(
        featureId: 'connection_hint',
        slotId: LobbyFeatureSlots.slotTopInline,
        priority: 10,
        builder: (ctx) => _InfoBanner(
          icon: Icons.wifi,
          text: 'Manage rooms below. Connection status is shown at the top.',
        ),
      ),
      context: context,
    );

    // Example Feature: Quick actions in secondary slot
    _registry.register(
      scopeKey: LobbyFeatureSlots.scopeKey,
      feature: IconActionFeatureDescriptor(
        featureId: 'refresh_rooms',
        slotId: LobbyFeatureSlots.slotSecondary,
        priority: 10,
        icon: Icons.refresh,
        tooltip: 'Refresh rooms',
        onTap: () {
          _log.info('🎮 LobbyFeatureRegistrar: Refresh rooms action triggered');
          // Intentionally minimal for example; real impl should call service
        },
      ),
      context: context,
    );

    _registry.register(
      scopeKey: LobbyFeatureSlots.scopeKey,
      feature: IconActionFeatureDescriptor(
        featureId: 'help',
        slotId: LobbyFeatureSlots.slotSecondary,
        priority: 20,
        icon: Icons.help_outline,
        tooltip: 'How it works',
        onTap: () {
          _log.info('🎮 LobbyFeatureRegistrar: Help action triggered');
        },
      ),
      context: context,
    );
    
    _log.info('🎮 LobbyFeatureRegistrar: Default features registered successfully');
  }

  void unregisterAll() {
    _log.info('🎮 LobbyFeatureRegistrar: Unregistering all features');
    _registry.clearScope(LobbyFeatureSlots.scopeKey);
  }
}

class _InfoBanner extends StatelessWidget {
  static final Logger _log = Logger();
  final IconData icon;
  final String text;
  const _InfoBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    _log.info('🎮 InfoBanner: Building banner with text: $text');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accentColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Rooms'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.help_outline, color: AppColors.white),
            label: const Text('How it works'),
          ),
        ),
      ],
    );
  }
}


