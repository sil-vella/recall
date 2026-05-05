import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../utils/consts/theme_consts.dart';

/// Visual variants for [DutchAnimatedCtaButton].
enum DutchCtaVariant {
  /// Filled accent button — used for the dominant action on a screen.
  primary,

  /// Outlined button using `accentContrast` — used for secondary actions.
  secondary,

  /// Text-only button — used for tertiary / dismissive actions.
  ghost,
}

/// Adapted from `assets/games-main/samples/multiplayer/lib/style/my_button.dart`
/// (Apache 2.0 / BSD-licensed Flutter sample). Adds a subtle hover wobble
/// while remaining within the existing Dutch theme tokens (`AppColors`,
/// `AppTextStyles`, `AppPadding`).
class DutchAnimatedCtaButton extends StatefulWidget {
  const DutchAnimatedCtaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = DutchCtaVariant.primary,
    this.leadingIcon,
    this.expand = true,
    this.semanticIdentifier,
  });

  final String label;
  final VoidCallback? onPressed;
  final DutchCtaVariant variant;
  final IconData? leadingIcon;

  /// When `true`, the button stretches to fill its parent's width.
  final bool expand;

  /// Optional `flt-semantics-identifier` value (web automation hook).
  final String? semanticIdentifier;

  @override
  State<DutchAnimatedCtaButton> createState() => _DutchAnimatedCtaButtonState();
}

class _DutchAnimatedCtaButtonState extends State<DutchAnimatedCtaButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 320),
    vsync: this,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;

    final child = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leadingIcon != null) ...[
          Icon(widget.leadingIcon, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final button = _buildVariantButton(child: child, isEnabled: isEnabled);

    final wrapped = Semantics(
      identifier: widget.semanticIdentifier,
      button: true,
      enabled: isEnabled,
      child: MouseRegion(
        onEnter: (_) {
          if (isEnabled) _controller.repeat();
        },
        onExit: (_) => _controller.stop(canceled: false),
        child: RotationTransition(
          turns: _controller.drive(const _SineWobbleTween(0.004)),
          child: button,
        ),
      ),
    );

    if (!widget.expand) return wrapped;
    return SizedBox(width: double.infinity, child: wrapped);
  }

  Widget _buildVariantButton({required Widget child, required bool isEnabled}) {
    switch (widget.variant) {
      case DutchCtaVariant.primary:
        return FilledButton(
          onPressed: widget.onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentColor,
            foregroundColor: AppColors.textOnAccent,
            disabledBackgroundColor: AppColors.disabledColor,
            disabledForegroundColor: AppColors.textOnAccent.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: AppBorderRadius.largeRadius,
            ),
            textStyle: AppTextStyles.buttonText(),
          ),
          child: child,
        );
      case DutchCtaVariant.secondary:
        return OutlinedButton(
          onPressed: widget.onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.white,
            side: BorderSide(
              color: AppColors.accentContrast.withValues(alpha: 0.7),
              width: 1.5,
            ),
            backgroundColor: AppColors.accentContrast.withValues(alpha: 0.18),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
            shape: RoundedRectangleBorder(
              borderRadius: AppBorderRadius.largeRadius,
            ),
            textStyle: AppTextStyles.buttonText(color: AppColors.white),
          ),
          child: child,
        );
      case DutchCtaVariant.ghost:
        return TextButton(
          onPressed: widget.onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.accentColor2,
            backgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: AppBorderRadius.mediumRadius,
            ),
            textStyle: AppTextStyles.buttonText(color: AppColors.accentColor2),
          ),
          child: child,
        );
    }
  }
}

/// Sine-wobble tween (game-sample inspired) — produces a soft attention pulse.
class _SineWobbleTween extends Animatable<double> {
  const _SineWobbleTween(this.maxExtent);

  final double maxExtent;

  @override
  double transform(double t) => sin(t * 2 * pi) * maxExtent;
}
