import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Collapsible section widget that shows a button/overlay when collapsed
/// and reveals the content when expanded
class CollapsibleSectionWidget extends StatefulWidget {
  final String title;
  final Widget child;
  final IconData? icon;
  /// Optional felt / texture behind the header row (e.g. Join Random table tier).
  final Widget? headerBackdrop;
  final bool initiallyExpanded;
  final bool? isExpanded; // External control for accordion behavior (nullable for optional use)
  final VoidCallback? onExpandedChanged; // Callback when expansion state changes

  const CollapsibleSectionWidget({
    Key? key,
    required this.title,
    required this.child,
    this.icon,
    this.headerBackdrop,
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppBorderRadius.large),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.headerBackdrop != null)
                    Positioned.fill(
                      child: widget.headerBackdrop!,
                    ),
                  Container(
                    width: double.infinity,
                    padding: AppPadding.cardPadding,
                    decoration: BoxDecoration(
                      color: widget.headerBackdrop == null
                          ? AppColors.accentColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppBorderRadius.large),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            color: widget.headerBackdrop != null
                                ? AppColors.white
                                : AppColors.textOnAccent,
                            size: AppSizes.iconMedium,
                            shadows: widget.headerBackdrop != null
                                ? const [
                                    Shadow(
                                      color: Color(0x88000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          SizedBox(width: AppPadding.mediumPadding.left),
                        ],
                        Text(
                          widget.title,
                          style: AppTextStyles.headingMedium().copyWith(
                            color: widget.headerBackdrop != null
                                ? AppColors.white
                                : AppColors.textOnAccent,
                            shadows: widget.headerBackdrop != null
                                ? const [
                                    Shadow(
                                      color: Color(0x88000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(width: AppPadding.mediumPadding.left),
                        AnimatedRotation(
                          turns: _isExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: Icon(
                            Icons.expand_more,
                            color: widget.headerBackdrop != null
                                ? AppColors.white
                                : AppColors.textOnAccent,
                            size: AppSizes.iconMedium,
                            shadows: widget.headerBackdrop != null
                                ? const [
                                    Shadow(
                                      color: Color(0x88000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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

