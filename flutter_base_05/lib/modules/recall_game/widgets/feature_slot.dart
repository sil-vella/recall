import 'dart:async';
import 'package:flutter/material.dart';
import '../../../utils/consts/theme_consts.dart';
import '../managers/feature_registry_manager.dart';
import '../managers/feature_contracts.dart';
import '../../../tools/logging/logger.dart';

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
  static final Logger _log = Logger();
  final FeatureRegistryManager _registry = FeatureRegistryManager.instance;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _log.info('🎮 FeatureSlot initialized for scope: ${widget.scopeKey}, slot: ${widget.slotId}');
    _sub = _registry.changes.listen((scope) {
      if (scope == widget.scopeKey && mounted) {
        _log.info('🎮 FeatureSlot rebuilding due to registry change for scope: $scope');
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _log.info('🎮 FeatureSlot disposing for scope: ${widget.scopeKey}, slot: ${widget.slotId}');
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final features = _registry.getFeaturesForSlot(
      scopeKey: widget.scopeKey,
      slotId: widget.slotId,
    );
    
    _log.info('🎮 FeatureSlot building with ${features.length} features for scope: ${widget.scopeKey}, slot: ${widget.slotId}');

    if (features.isEmpty) {
      return const SizedBox.shrink();
    }

    // If a contract is specified, enforce it
    if (widget.contract == 'icon_action') {
      final iconFeatures = features.whereType<IconActionFeatureDescriptor>().toList();
      if (iconFeatures.isEmpty) return const SizedBox.shrink();

      final row = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: iconFeatures.map((f) {
          final iconButton = InkWell(
            onTap: f.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: widget.iconPadding,
              child: Icon(f.icon, size: widget.iconSize, color: AppColors.white),
            ),
          );
          return f.tooltip != null
              ? Tooltip(message: f.tooltip!, child: iconButton)
              : iconButton;
        }).toList(),
      );

      if (!widget.useTemplate) return row;
      return SlotTemplate(title: widget.title ?? widget.slotId, children: [row]);
    }

    final children = features.map((f) => f.builder(context)).toList();

    if (!widget.useTemplate) {
      return Column(children: children);
    }

    return SlotTemplate(
      title: widget.title ?? widget.slotId,
      children: children,
    );
  }
}


