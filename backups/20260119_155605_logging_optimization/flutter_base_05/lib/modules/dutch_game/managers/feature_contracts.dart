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

/// Specialized descriptor for home screen full-width button features.
/// Supports image background or solid color, with centered text.
class HomeScreenButtonFeatureDescriptor extends FeatureDescriptor {
  final String text;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final String? imagePath;
  final double? height;
  final double? heightPercentage; // Percentage of available height (0.0 to 1.0)
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;

  HomeScreenButtonFeatureDescriptor({
    required String featureId,
    required String slotId,
    required this.text,
    required this.onTap,
    this.backgroundColor,
    this.imagePath,
    this.height,
    this.heightPercentage,
    this.padding,
    this.textStyle,
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


