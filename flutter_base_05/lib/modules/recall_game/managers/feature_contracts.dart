import 'package:flutter/material.dart';
import 'feature_registry_manager.dart';

/// Specialized descriptor for icon actions to be used in icon-only slots.
class IconActionFeatureDescriptor extends FeatureDescriptor {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  IconActionFeatureDescriptor({
    required String featureId,
    required String slotId,
    required this.icon,
    required this.onTap,
    this.tooltip,
    int priority = 100,
    Map<String, dynamic>? metadata,
  }) : super(
          featureId: featureId,
          slotId: slotId,
          priority: priority,
          builder: (context) => const SizedBox.shrink(),
          metadata: metadata,
        );
}


