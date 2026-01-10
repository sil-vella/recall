import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/consts/theme_consts.dart';
import '../../modules/dutch_game/managers/feature_registry_manager.dart';
import '../../modules/dutch_game/managers/feature_contracts.dart';

/// A visual template for a feature slot. Enforces padding, spacing, and theme.
class SlotTemplate extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const SlotTemplate({
    Key? key,
    required this.title,
    required this.children,
    this.padding,
    this.margin,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? AppPadding.defaultPadding,
      padding: padding ?? AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accentColor.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title, style: AppTextStyles.headingSmall()),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// Renders all registered features for a given [slotId] within a [scopeKey].
/// Rebuilds when the registry emits a change for the scope.
class FeatureSlot extends StatefulWidget {
  final String scopeKey;
  final String slotId;
  final String? title;
  final bool useTemplate;
  final String? contract; // e.g., 'icon_action'
  final double iconSize;
  final EdgeInsets iconPadding;

  const FeatureSlot({
    Key? key,
    required this.scopeKey,
    required this.slotId,
    this.title,
    this.useTemplate = true,
    this.contract,
    this.iconSize = 24,
    this.iconPadding = const EdgeInsets.all(8),
  }) : super(key: key);

  @override
  State<FeatureSlot> createState() => _FeatureSlotState();
}

class _FeatureSlotState extends State<FeatureSlot> {
  final FeatureRegistryManager _registry = FeatureRegistryManager.instance;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _registry.changes.listen((scope) {
      // Rebuild if the change is in our scope OR in the global scope
      if ((scope == widget.scopeKey || scope == 'global_app_bar') && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final features = _registry.getFeaturesForSlot(
      scopeKey: widget.scopeKey,
      slotId: widget.slotId,
    );

    if (features.isEmpty) {
      return const SizedBox.shrink();
    }

    final widgets = features.map((feature) {
      if (feature is IconActionFeatureDescriptor) {
        return _buildIconActionFeature(feature);
      } else if (feature is HomeScreenButtonFeatureDescriptor) {
        return _buildHomeScreenButtonFeature(feature);
      } else {
        return _buildGenericFeature(feature);
      }
    }).toList();

    if (widget.useTemplate && widget.title != null) {
      return SlotTemplate(
        title: widget.title!,
        children: widgets,
      );
    }

    // For home screen buttons, return as column (full-width buttons stacked vertically)
    if (widget.contract == 'home_screen_button') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: widgets,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _buildIconActionFeature(IconActionFeatureDescriptor feature) {
    final color = feature.metadata?['color'] as Color?;
    
    return Padding(
      padding: widget.iconPadding,
      child: IconButton(
        icon: Icon(
          feature.icon,
          size: widget.iconSize,
          color: color,
        ),
        onPressed: feature.onTap,
        tooltip: feature.tooltip,
        style: IconButton.styleFrom(
          foregroundColor: color,
        ),
      ),
    );
  }

  Widget _buildHomeScreenButtonFeature(HomeScreenButtonFeatureDescriptor feature) {
    // Calculate height: use percentage if provided, otherwise use fixed height or default
    double? calculatedHeight;
    if (feature.heightPercentage != null) {
      final mediaQuery = MediaQuery.of(context);
      final availableHeight = mediaQuery.size.height - mediaQuery.padding.top - mediaQuery.padding.bottom;
      calculatedHeight = availableHeight * feature.heightPercentage!;
    } else {
      calculatedHeight = feature.height ?? 80;
    }
    
    return Container(
      width: double.infinity,
      height: calculatedHeight,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: feature.backgroundColor ?? AppColors.primaryColor,
        borderRadius: BorderRadius.circular(12),
        image: feature.imagePath != null
            ? DecorationImage(
                image: AssetImage(feature.imagePath!),
                fit: BoxFit.cover,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: feature.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: feature.padding ?? const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
              child: Text(
                feature.text,
                  style: feature.textStyle ?? AppTextStyles.headingLarge().copyWith(
                  color: AppColors.textOnPrimary,
                  fontWeight: FontWeight.bold,
                    fontSize: 56, // Double the default headingLarge size (28 * 2)
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGenericFeature(FeatureDescriptor feature) {
    return Padding(
      padding: widget.iconPadding,
      child: feature.builder(context),
    );
  }
}
