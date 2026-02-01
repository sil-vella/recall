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

    // For home screen buttons, return as swipeable carousel
    if (widget.contract == 'home_screen_button') {
      return _HomeScreenCarousel(features: features, widgets: widgets);
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
            width: double.infinity,
            padding: feature.padding ?? const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    width: constraints.maxWidth,
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
                      softWrap: true,
                    ),
                  );
                },
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

/// Swipeable carousel widget for home screen features
/// Shows current item at full opacity, with previous/next items visible at 50% opacity
class _HomeScreenCarousel extends StatefulWidget {
  final List<FeatureDescriptor> features;
  final List<Widget> widgets;

  const _HomeScreenCarousel({
    required this.features,
    required this.widgets,
  });

  @override
  State<_HomeScreenCarousel> createState() => _HomeScreenCarouselState();
}

class _HomeScreenCarouselState extends State<_HomeScreenCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  late List<Widget> _sortedWidgets;

  @override
  void initState() {
    super.initState();
    
    // Sort features by priority (ascending - lower priority first)
    // Demo has priority 90, Play has priority 100, so demo comes first
    final sortedFeatures = List<MapEntry<int, Widget>>.generate(
      widget.features.length,
      (index) => MapEntry(
        widget.features[index].priority,
        widget.widgets[index],
      ),
    )..sort((a, b) => a.key.compareTo(b.key));

    _sortedWidgets = sortedFeatures.map((entry) => entry.value).toList();

    // Find demo button index (priority 90) to start there
    final demoIndex = sortedFeatures.indexWhere((entry) => entry.key == 90);
    _currentPage = demoIndex >= 0 ? demoIndex : 0;

    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: 0.7, // Each item takes 70% of viewport
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPreviousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNextPage() {
    if (_currentPage < _sortedWidgets.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.features.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final availableHeight = screenHeight * 0.5; // 50% of screen height
    final canGoLeft = _currentPage > 0;
    final canGoRight = _currentPage < _sortedWidgets.length - 1;

    return SizedBox(
      height: availableHeight,
      child: Stack(
        children: [
          // PageView carousel
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: _sortedWidgets.length,
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double opacity = 0.5; // Default to 50% for side items
                  
                  if (_pageController.position.haveDimensions) {
                    final page = _pageController.page!;
                    final distance = (page - index).abs();
                    
                    // Current page (or very close to it) gets full opacity
                    // Adjacent pages get 50% opacity
                    if (distance < 0.5) {
                      opacity = 1.0 - (distance * 1.0); // Smooth transition from 1.0 to 0.5
                      opacity = opacity.clamp(0.5, 1.0);
                    } else {
                      opacity = 0.5;
                    }
                  } else {
                    // Before PageView is ready, use simple distance calculation
                    final distance = (index - _currentPage).abs();
                    opacity = distance == 0 ? 1.0 : 0.5;
                  }

                  return Opacity(
                    opacity: opacity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: _sortedWidgets[index],
                    ),
                  );
                },
              );
            },
          ),
          
          // Left arrow button
          if (canGoLeft)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _goToPreviousPage,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.accentColor.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_back_ios,
                        color: AppColors.textOnPrimary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          
          // Right arrow button
          if (canGoRight)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _goToNextPage,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.accentColor.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios,
                        color: AppColors.textOnPrimary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
