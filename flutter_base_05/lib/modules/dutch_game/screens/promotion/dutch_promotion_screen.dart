import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../animations_module/animations_module.dart';
import '../../../audio_module/audio_module.dart';
import '../../backend_core/utils/dutch_rank_level_change_checker.dart';
import '../../widgets/ui_kit/dutch_animated_cta_button.dart';
import 'widgets/dutch_promotion_before_after.dart';
import 'widgets/dutch_promotion_burst.dart'
    show DutchPromotionBurst, kDutchPromotionBurstForegroundSpacer;
import 'widgets/dutch_promotion_rank_badge.dart';

/// Which kind of promotion is being celebrated.
enum DutchPromotionKind {
  levelUp,
  rankUp,
}

/// Full-screen hype celebration shown when the player's stored level or rank
/// progresses after a match. Pushed via `Navigator.push(MaterialPageRoute(...,
/// fullscreenDialog: true))` so multiple promotions can be sequenced (level
/// first, then rank) by simply awaiting `pop()` between pushes.
class DutchPromotionScreen extends StatefulWidget {
  const DutchPromotionScreen({
    super.key,
    required this.kind,
    required this.change,
  });

  final DutchPromotionKind kind;
  final DutchRankLevelChangeResult change;

  @override
  State<DutchPromotionScreen> createState() => _DutchPromotionScreenState();
}

class _DutchPromotionScreenState extends State<DutchPromotionScreen>
    with SingleTickerProviderStateMixin {
  /// Promotion-screen lifecycle/animation trace. Set to `false` once the
  /// sequenced fullscreen flow has been verified end-to-end.
  /// Delay before the secondary confetti burst for sustained energy.
  static const Duration _secondaryBurstDelay = Duration(milliseconds: 1600);

  late final ConfettiController _leftConfetti;
  late final ConfettiController _rightConfetti;

  late final AnimationController _entryController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  Timer? _secondaryBurstTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _initConfetti();
    _playLevelUpSound();
    _scheduleSecondaryBurst();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entryController.forward();
      _leftConfetti.play();
      _rightConfetti.play();
      
    });
  }

  void _initConfetti() {
    final animations = ModuleManager().getModuleByType<AnimationsModule>();
    if (animations != null) {
      _leftConfetti = animations.createConfettiController(
        duration: const Duration(seconds: 4),
      );
      _rightConfetti = animations.createConfettiController(
        duration: const Duration(seconds: 4),
      );
    } else {
      _leftConfetti = ConfettiController(duration: const Duration(seconds: 4));
      _rightConfetti = ConfettiController(duration: const Duration(seconds: 4));
    }
  }

  void _playLevelUpSound() {
    try {
      final audio = ModuleManager().getModuleByType<AudioModule>();
      audio?.playSound('level_up_1');
    } catch (e) {
      
    }
  }

  void _scheduleSecondaryBurst() {
    _secondaryBurstTimer = Timer(_secondaryBurstDelay, () {
      if (!mounted || _disposed) return;
      _leftConfetti.play();
      _rightConfetti.play();
    });
  }

  void _close() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  void _onContinue() {
    _close();
  }

  void _onViewLeaderboard() {
    _close();
    NavigationManager().navigateTo('/dutch/leaderboard');
  }

  @override
  void dispose() {
    _disposed = true;
    _secondaryBurstTimer?.cancel();
    _entryController.dispose();
    // Confetti controllers were created via AnimationsModule (which retains
    // and disposes them on module dispose); stopping here is sufficient.
    _leftConfetti.stop();
    _rightConfetti.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLevel = widget.kind == DutchPromotionKind.levelUp;
    final headline = isLevel ? 'LEVEL UP!' : 'RANK UP!';
    final semanticRoot = isLevel
        ? 'promotion_screen_level'
        : 'promotion_screen_rank';

    return Semantics(
      identifier: semanticRoot,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(),
            DutchPromotionBurst(
              leftController: _leftConfetti,
              rightController: _rightConfetti,
            ),
            _buildForeground(headline, isLevel),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: _buildCloseButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.1,
              colors: [
                AppColors.scaffoldBackgroundColor,
                AppColors.scaffoldDeepPlumColor,
                Colors.black,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
        ),
        Opacity(
          opacity: 0.22,
          child: Image.asset(
            'assets/images/backgrounds/main-screens-background.webp',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildForeground(String headline, bool isLevel) {
    final entryFade = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: const Interval(0.0, 0.5, curve: Curves.easeOut)))
        .animate(_entryController);
    final entryScale = Tween<double>(begin: 0.4, end: 1.0)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_entryController);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: kDutchPromotionBurstForegroundSpacer),
              FadeTransition(
                opacity: entryFade,
                child: _buildHeadline(headline),
              ),
              const SizedBox(height: 18),
              ScaleTransition(
                scale: entryScale,
                child: _buildBadge(isLevel),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: entryFade,
                child: Align(
                  alignment: Alignment.center,
                  child: DutchPromotionBeforeAfter(
                    kind: isLevel
                        ? DutchPromotionBadgeKind.level
                        : DutchPromotionBadgeKind.rank,
                    beforeLevel: widget.change.levelBefore,
                    afterLevel: widget.change.levelAfter,
                    beforeRank: _capitalise(widget.change.rankBefore),
                    afterRank: _capitalise(widget.change.rankAfter),
                    semanticIdentifier: 'promotion_before_after',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FadeTransition(
                opacity: entryFade,
                child: _buildSubline(isLevel),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: entryFade,
                child: _buildActions(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeadline(String headline) {
    return Semantics(
      identifier: 'promotion_headline',
      header: true,
      label: headline,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.matchPotGoldLight,
            AppColors.matchPotGold,
            AppColors.matchPotGoldLight,
          ],
          stops: [0.0, 0.5, 1.0],
        ).createShader(rect),
        child: Text(
          headline,
          textAlign: TextAlign.center,
          style: AppTextStyles.headingLarge(color: AppColors.white).copyWith(
            fontSize: 44,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            height: 1.0,
            shadows: [
              Shadow(
                color: AppColors.matchPotGold.withValues(alpha: 0.55),
                blurRadius: 22,
              ),
              Shadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(bool isLevel) {
    return DutchPromotionRankBadge(
      kind: isLevel
          ? DutchPromotionBadgeKind.level
          : DutchPromotionBadgeKind.rank,
      level: widget.change.levelAfter,
      rankLabel: _capitalise(widget.change.rankAfter),
      size: 100,
      semanticIdentifier: 'promotion_main_badge',
    );
  }

  Widget _buildSubline(bool isLevel) {
    final wins = widget.change.winsAfter;
    final winsLine = wins != null ? '  •  $wins wins' : '';
    final text = isLevel
        ? 'You leveled up!$winsLine'
        : "You're now a ${_capitalise(widget.change.rankAfter) ?? 'Champion'}!$winsLine";

    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppTextStyles.bodyLarge(color: AppColors.white).copyWith(
        fontWeight: FontWeight.w600,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final isRankPromotion = widget.kind == DutchPromotionKind.rankUp;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: DutchAnimatedCtaButton(
            label: 'Continue',
            onPressed: _onContinue,
            leadingIcon: Icons.check_circle_outline,
            expand: false,
            semanticIdentifier: 'promotion_continue',
          ),
        ),
        if (isRankPromotion) ...[
          const SizedBox(width: 12),
          Flexible(
            child: DutchAnimatedCtaButton(
              label: 'Leaderboard',
              onPressed: _onViewLeaderboard,
              leadingIcon: Icons.emoji_events_outlined,
              variant: DutchCtaVariant.ghost,
              expand: false,
              semanticIdentifier: 'promotion_leaderboard',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCloseButton() {
    return Semantics(
      identifier: 'promotion_close',
      button: true,
      label: 'Close',
      child: Material(
        color: Colors.black.withValues(alpha: 0.32),
        shape: const CircleBorder(),
          child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _onContinue,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(
              Icons.close_rounded,
              color: AppColors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  String? _capitalise(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }
}
