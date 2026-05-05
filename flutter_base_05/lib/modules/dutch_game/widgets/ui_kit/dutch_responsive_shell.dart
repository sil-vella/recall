import 'package:flutter/material.dart';

/// Adapted from `assets/games-main/samples/multiplayer/lib/style/responsive_screen.dart`.
///
/// Splits a screen into a "squarish" hero area (e.g. logo, podium, profile
/// header) and a rectangular menu area (CTAs / sections). Switches between
/// portrait (column) and landscape (row) automatically. Designed to be used
/// **inside** `BaseScreenState.buildContent` — it does not replace
/// `BaseScreen` and adds no `Scaffold`.
class DutchResponsiveShell extends StatelessWidget {
  const DutchResponsiveShell({
    super.key,
    required this.hero,
    required this.menu,
    this.topMessage,
    this.maxWidth = 1000,
    this.heroFlexLandscape = 5,
    this.menuFlexLandscape = 3,
    this.heroFlexLandscapeLarge = 7,
  });

  /// The "hero" of the screen — typically near-square content.
  final Widget hero;

  /// Secondary area that holds CTAs / menu sections.
  final Widget menu;

  /// Optional small status / info area docked near the top.
  final Widget? topMessage;

  /// Max content width to keep desktop layouts readable.
  final double maxWidth;

  /// Landscape flex distribution.
  final int heroFlexLandscape;
  final int menuFlexLandscape;

  /// On wide screens (>900px) we let the hero take more horizontal room.
  final int heroFlexLandscapeLarge;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final padding = EdgeInsets.all(size.shortestSide / 30);
        final isPortrait = size.height >= size.width;

        final content = isPortrait
            ? _buildPortrait(padding)
            : _buildLandscape(padding, size.width > 900);

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildPortrait(EdgeInsets padding) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topMessage != null)
          SafeArea(
            bottom: false,
            child: Padding(padding: padding, child: topMessage),
          ),
        Expanded(
          child: SafeArea(
            top: false,
            bottom: false,
            minimum: padding,
            child: hero,
          ),
        ),
        SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          child: Padding(
            padding: padding,
            child: Center(child: menu),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscape(EdgeInsets padding, bool isLarge) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: isLarge ? heroFlexLandscapeLarge : heroFlexLandscape,
          child: SafeArea(
            right: false,
            maintainBottomViewPadding: true,
            minimum: padding,
            child: hero,
          ),
        ),
        Expanded(
          flex: menuFlexLandscape,
          child: Column(
            children: [
              if (topMessage != null)
                SafeArea(
                  bottom: false,
                  left: false,
                  maintainBottomViewPadding: true,
                  child: Padding(padding: padding, child: topMessage),
                ),
              Expanded(
                child: SafeArea(
                  top: false,
                  left: false,
                  maintainBottomViewPadding: true,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(padding: padding, child: menu),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
