import 'package:flutter/material.dart';

import '../../../../../utils/consts/theme_consts.dart';

/// Visual variant for [DutchPromotionRankBadge].
enum DutchPromotionBadgeKind {
  /// Renders a big level number in the badge core.
  level,

  /// Renders a shield icon with the rank name beneath.
  rank,
}

/// Gold-ringed circular badge used in the level/rank promotion screens.
///
/// The outer gold ring softly pulses (1.0 → 1.06) to draw attention, while the
/// inner core uses the theme accent gradient to stay on-brand across presets.
/// All colors come from `AppColors`; the only literal is the light-gold gradient
/// stop which is exposed as `AppColors.matchPotGoldLight`.
class DutchPromotionRankBadge extends StatefulWidget {
  const DutchPromotionRankBadge({
    super.key,
    required this.kind,
    this.level,
    this.rankLabel,
    this.size = 200,
    this.pulse = true,
    this.semanticIdentifier,
  });

  /// Determines whether to render the level number or rank icon/label.
  final DutchPromotionBadgeKind kind;

  /// Required when [kind] is [DutchPromotionBadgeKind.level].
  final int? level;

  /// Required when [kind] is [DutchPromotionBadgeKind.rank]. Already capitalised.
  final String? rankLabel;

  final double size;

  /// When `true`, the gold ring pulses subtly forever.
  final bool pulse;

  final String? semanticIdentifier;

  @override
  State<DutchPromotionRankBadge> createState() =>
      _DutchPromotionRankBadgeState();
}

class _DutchPromotionRankBadgeState extends State<DutchPromotionRankBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant DutchPromotionRankBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.pulse && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringTween = Tween<double>(begin: 1.0, end: 1.06)
        .chain(CurveTween(curve: Curves.easeInOut));

    return Semantics(
      identifier: widget.semanticIdentifier,
      label: widget.kind == DutchPromotionBadgeKind.level
          ? 'Level ${widget.level ?? '-'}'
          : 'Rank ${widget.rankLabel ?? '-'}',
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final ringScale = ringTween.evaluate(_pulseController);
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: ringScale,
                  child: _buildOuterGoldRing(),
                ),
                _buildInnerCore(),
                _buildContent(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOuterGoldRing() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.matchPotGoldLight,
            AppColors.matchPotGold,
            AppColors.matchPotGoldLight,
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.matchPotGold.withValues(alpha: 0.55),
            blurRadius: 32,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildInnerCore() {
    final innerSize = widget.size - 18;
    return Container(
      width: innerSize,
      height: innerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.accentColor,
            AppColors.accentContrast,
            AppColors.scaffoldDeepPlumColor,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.kind) {
      case DutchPromotionBadgeKind.level:
        return _buildLevelContent();
      case DutchPromotionBadgeKind.rank:
        return _buildRankContent();
    }
  }

  Widget _buildLevelContent() {
    final level = widget.level ?? 0;
    final fontSize = widget.size * 0.42;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'LEVEL',
          style: AppTextStyles.bodySmall(color: AppColors.matchPotGoldLight)
              .copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
            fontSize: widget.size * 0.085,
          ),
        ),
        const SizedBox(height: 2),
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.matchPotGoldLight,
              AppColors.matchPotGold,
            ],
          ).createShader(rect),
          child: Text(
            '$level',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: AppColors.white,
              height: 1.0,
              letterSpacing: -1,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRankContent() {
    final label = (widget.rankLabel ?? '').trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.shield_outlined,
          size: widget.size * 0.42,
          color: AppColors.matchPotGoldLight,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label.isEmpty ? '—' : label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium(color: AppColors.white).copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              fontSize: widget.size * 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact pill rendering of a rank/level for the before/after row.
class DutchPromotionMiniBadge extends StatelessWidget {
  const DutchPromotionMiniBadge({
    super.key,
    required this.kind,
    this.level,
    this.rankLabel,
    this.dim = false,
    this.semanticIdentifier,
  });

  final DutchPromotionBadgeKind kind;
  final int? level;
  final String? rankLabel;

  /// When `true`, the badge is rendered with reduced contrast (used for the "before" pill).
  final bool dim;

  final String? semanticIdentifier;

  @override
  Widget build(BuildContext context) {
    final text = kind == DutchPromotionBadgeKind.level
        ? 'Lvl ${level ?? '-'}'
        : (rankLabel ?? '—').toUpperCase();
    final goldRingColor = dim
        ? AppColors.matchPotGold.withValues(alpha: 0.45)
        : AppColors.matchPotGold;
    final innerColor = dim
        ? AppColors.accentContrast.withValues(alpha: 0.45)
        : AppColors.accentContrast;
    final textColor = dim
        ? AppColors.white.withValues(alpha: 0.7)
        : AppColors.white;

    return Semantics(
      identifier: semanticIdentifier,
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: innerColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: goldRingColor, width: 2),
          boxShadow: dim
              ? null
              : [
                  BoxShadow(
                    color: AppColors.matchPotGold.withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: Text(
          text,
          style: AppTextStyles.bodySmall(color: textColor).copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
