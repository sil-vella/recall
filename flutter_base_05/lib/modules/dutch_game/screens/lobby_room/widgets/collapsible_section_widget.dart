import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Collapsible section widget that shows a button/overlay when collapsed
/// and reveals the content when expanded
class CollapsibleSectionWidget extends StatefulWidget {
  final String title;
  final Widget child;
  final IconData? icon;
  final bool initiallyExpanded;
  final bool? isExpanded; // External control for accordion behavior (nullable for optional use)
  final VoidCallback? onExpandedChanged; // Callback when expansion state changes

  const CollapsibleSectionWidget({
    Key? key,
    required this.title,
    required this.child,
    this.icon,
    this.initiallyExpanded = false,
    this.isExpanded,
    this.onExpandedChanged,
  }) : super(key: key);

  @override
  State<CollapsibleSectionWidget> createState() => _CollapsibleSectionWidgetState();
}

class _CollapsibleSectionWidgetState extends State<CollapsibleSectionWidget>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isExpanded ?? widget.initiallyExpanded;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(CollapsibleSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update expansion state if externally controlled
    if (widget.isExpanded != null && widget.isExpanded != _isExpanded) {
      _isExpanded = widget.isExpanded!;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    final newExpanded = !_isExpanded;
    setState(() {
      _isExpanded = newExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
    // Notify parent of expansion change for accordion behavior
    widget.onExpandedChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Button/Overlay (always visible)
        GestureDetector(
          onTap: _toggleExpanded,
          child: Container(
            margin: EdgeInsets.symmetric(
              horizontal: AppPadding.defaultPadding.left,
              vertical: AppPadding.smallPadding.top,
            ),
            padding: AppPadding.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.accentColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  widget.title,
                  style: AppTextStyles.headingMedium().copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(width: 12),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Icons.expand_more,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Expandable content
        SizeTransition(
          sizeFactor: _expandAnimation,
          child: ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.child,
                SizedBox(height: AppPadding.smallPadding.top),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

