import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

    // For home screen buttons: vertical snap-scroll; only item centered in viewport is tappable
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

    final side = calculatedHeight;
    final iconSize = (side * 0.4).clamp(40.0, 96.0);

    const borderRadius = BorderRadius.all(Radius.circular(12));
    return Center(
      child: Container(
        width: side,
        height: side,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: AppColors.matchPotGold,
            width: 5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (feature.backgroundColor != null)
                Container(
                  decoration: BoxDecoration(
                    color: feature.backgroundColor,
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: feature.onTap,
                  borderRadius: borderRadius,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (feature.iconSvgPath != null) ...[
                            SvgPicture.asset(
                              feature.iconSvgPath!,
                              width: iconSize,
                              height: iconSize,
                              colorFilter: ColorFilter.mode(
                                AppColors.accentColor,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else if (feature.icon != null) ...[
                            Icon(
                              feature.icon,
                              size: iconSize,
                              color: AppColors.textOnPrimary,
                            ),
                            const SizedBox(height: 8),
                          ],
                        Text(
                          feature.text,
                          style: feature.textStyle ?? AppTextStyles.headingLarge().copyWith(
                            color: AppColors.textOnPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 56, // Double the default headingLarge size (28 * 2)
                          ),
                          textAlign: TextAlign.center,
                          softWrap: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
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

/// Hides platform scrollbars for the home feature strip (drag / wheel still scrolls).
class _HomeScreenCarouselScrollBehavior extends MaterialScrollBehavior {
  const _HomeScreenCarouselScrollBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// Vertical snap list: item aligned to viewport center is “in focus” (opacity 1.0); others [kDimmedCardOpacity].
/// Only the focused row accepts taps ([IgnorePointer] on the rest).
class _HomeScreenCarousel extends StatefulWidget {
  final List<FeatureDescriptor> features;
  final List<Widget> widgets;

  const _HomeScreenCarousel({
    required this.features,
    required this.widgets,
  });

  static const double kDimmedCardOpacity = 0.3;
  /// Viewport height as a fraction of screen — list scrolls inside this band.
  static const double kViewportHeightFraction = 0.42;

  @override
  State<_HomeScreenCarousel> createState() => _HomeScreenCarouselState();
}

class _HomeScreenCarouselState extends State<_HomeScreenCarousel> {
  final ScrollController _scrollController = ScrollController();
  int _focusedIndex = 0;
  late List<FeatureDescriptor> _sortedFeatures;
  late List<Widget> _sortedWidgets;
  bool _initialScrollScheduled = false;
  bool _snapScheduled = false;

  @override
  void initState() {
    super.initState();
    final order = List<int>.generate(widget.features.length, (i) => i)
      ..sort((a, b) => widget.features[a].priority.compareTo(widget.features[b].priority));
    _sortedFeatures = order.map((i) => widget.features[i]).toList();
    _sortedWidgets = order.map((i) => widget.widgets[i]).toList();
    _scrollController.addListener(_syncFocusFromScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncFocusFromScroll);
    _scrollController.dispose();
    super.dispose();
  }

  double _itemStride(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safeH = mq.size.height - mq.padding.vertical;
    var side = 80.0;
    for (final f in _sortedFeatures) {
      if (f is HomeScreenButtonFeatureDescriptor) {
        if (f.heightPercentage != null) {
          side = math.max(side, safeH * f.heightPercentage!);
        } else {
          side = math.max(side, (f.height ?? 80).toDouble());
        }
      }
    }
    return side + 16.0;
  }

  void _syncFocusFromScroll() {
    if (!_scrollController.hasClients) return;
    final mq = MediaQuery.of(context);
    final vp = mq.size.height * _HomeScreenCarousel.kViewportHeightFraction;
    final itemH = _itemStride(context);
    final topPad = math.max(0.0, (vp - itemH) / 2.0);
    final n = _sortedWidgets.length;
    final i = _indexForOffset(_scrollController.offset, topPad, itemH, vp, n);
    if (i != _focusedIndex) setState(() => _focusedIndex = i);
  }

  int _indexForOffset(double offset, double topPad, double itemH, double vp, int n) {
    final center = offset + vp / 2.0;
    var i = ((center - topPad - itemH / 2.0) / itemH).round();
    i = i.clamp(0, n - 1);
    return i;
  }

  double _offsetToCenterIndex(int index, double topPad, double itemH, double vp) {
    return topPad + index * itemH + itemH / 2.0 - vp / 2.0;
  }

  void _snapToNearest() {
    if (!_scrollController.hasClients || !mounted) return;
    final mq = MediaQuery.of(context);
    final vp = mq.size.height * _HomeScreenCarousel.kViewportHeightFraction;
    final itemH = _itemStride(context);
    final topPad = math.max(0.0, (vp - itemH) / 2.0);
    final n = _sortedWidgets.length;
    final i = _indexForOffset(_scrollController.offset, topPad, itemH, vp, n);
    final target = _offsetToCenterIndex(i, topPad, itemH, vp);
    final maxScroll = math.max(0.0, _scrollController.position.maxScrollExtent);
    final clamped = target.clamp(0.0, maxScroll).toDouble();
    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _scheduleSnap() {
    if (_snapScheduled) return;
    _snapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapScheduled = false;
      if (mounted) _snapToNearest();
    });
  }

  void _animateToIndex(int index) {
    if (!_scrollController.hasClients || !mounted) return;
    final mq = MediaQuery.of(context);
    final vp = mq.size.height * _HomeScreenCarousel.kViewportHeightFraction;
    final itemH = _itemStride(context);
    final topPad = math.max(0.0, (vp - itemH) / 2.0);
    final n = _sortedWidgets.length;
    final i = index.clamp(0, n - 1);
    final maxScroll = math.max(0.0, _scrollController.position.maxScrollExtent);
    final target =
        _offsetToCenterIndex(i, topPad, itemH, vp).clamp(0.0, maxScroll).toDouble();
    setState(() => _focusedIndex = i);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToPrevious() {
    if (_focusedIndex > 0) _animateToIndex(_focusedIndex - 1);
  }

  void _goToNext() {
    if (_focusedIndex < _sortedWidgets.length - 1) {
      _animateToIndex(_focusedIndex + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.features.isEmpty) {
      return const SizedBox.shrink();
    }

    final mq = MediaQuery.of(context);
    final vp = mq.size.height * _HomeScreenCarousel.kViewportHeightFraction;
    final itemH = _itemStride(context);
    final topPad = math.max(0.0, (vp - itemH) / 2.0);
    final n = _sortedWidgets.length;

    if (!_initialScrollScheduled) {
      _initialScrollScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final mq2 = MediaQuery.of(context);
        final vp2 = mq2.size.height * _HomeScreenCarousel.kViewportHeightFraction;
        final itemH2 = _itemStride(context);
        final topPad2 = math.max(0.0, (vp2 - itemH2) / 2.0);
        final maxScroll = _scrollController.position.maxScrollExtent;
        final target = _offsetToCenterIndex(0, topPad2, itemH2, vp2).clamp(0.0, maxScroll).toDouble();
        _scrollController.jumpTo(target);
        _syncFocusFromScroll();
      });
    }

    final canGoUp = _focusedIndex > 0;
    final canGoDown = _focusedIndex < n - 1;

    return SizedBox(
      height: vp,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ScrollConfiguration(
            behavior: const _HomeScreenCarouselScrollBehavior(),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification &&
                    notification.metrics.axis == Axis.vertical) {
                  _scheduleSnap();
                }
                return false;
              },
              child: ListView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  SizedBox(height: topPad),
                  ...List.generate(n, (i) {
                    return SizedBox(
                      height: itemH,
                      child: Center(
                        child: Opacity(
                          opacity: i == _focusedIndex
                              ? 1.0
                              : _HomeScreenCarousel.kDimmedCardOpacity,
                          child: IgnorePointer(
                            ignoring: i != _focusedIndex,
                            child: _sortedWidgets[i],
                          ),
                        ),
                      ),
                    );
                  }),
                  SizedBox(height: topPad),
                ],
              ),
            ),
          ),
          if (canGoUp)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _goToPrevious,
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
                        Icons.keyboard_arrow_up,
                        color: AppColors.textOnPrimary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (canGoDown)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _goToNext,
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
                        Icons.keyboard_arrow_down,
                        color: AppColors.textOnPrimary,
                        size: 28,
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
