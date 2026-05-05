import 'package:flutter/material.dart';

import '../../../../../utils/consts/theme_consts.dart';
import 'dutch_promotion_rank_badge.dart';

/// Renders the `before -> after` delta row for the promotion screen.
///
/// Layout: [before mini badge]  [animated arrow]  [after mini badge]. The
/// "after" badge animates in with an elastic scale so it visually pops compared
/// to the dimmed "before" state.
class DutchPromotionBeforeAfter extends StatefulWidget {
  const DutchPromotionBeforeAfter({
    super.key,
    required this.kind,
    this.beforeLevel,
    this.afterLevel,
    this.beforeRank,
    this.afterRank,
    this.semanticIdentifier,
  });

  final DutchPromotionBadgeKind kind;
  final int? beforeLevel;
  final int? afterLevel;
  final String? beforeRank;
  final String? afterRank;
  final String? semanticIdentifier;

  @override
  State<DutchPromotionBeforeAfter> createState() =>
      _DutchPromotionBeforeAfterState();
}

class _DutchPromotionBeforeAfterState extends State<DutchPromotionBeforeAfter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaleTween = Tween<double>(begin: 0.4, end: 1.0)
        .chain(CurveTween(curve: Curves.elasticOut));
    final fadeTween = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: const Interval(0.0, 0.4, curve: Curves.easeOut)));

    return Semantics(
      identifier: widget.semanticIdentifier,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DutchPromotionMiniBadge(
            kind: widget.kind,
            level: widget.beforeLevel,
            rankLabel: widget.beforeRank,
            dim: true,
            semanticIdentifier: 'promotion_before_badge',
          ),
          const SizedBox(width: 12),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Opacity(
                opacity: fadeTween.evaluate(_controller),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.matchPotGoldLight,
                  size: 28,
                  shadows: [
                    Shadow(
                      color: AppColors.matchPotGold.withValues(alpha: 0.6),
                      blurRadius: 12,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: scaleTween.evaluate(_controller),
                child: child,
              );
            },
            child: DutchPromotionMiniBadge(
              kind: widget.kind,
              level: widget.afterLevel,
              rankLabel: widget.afterRank,
              dim: false,
              semanticIdentifier: 'promotion_after_badge',
            ),
          ),
        ],
      ),
    );
  }
}
