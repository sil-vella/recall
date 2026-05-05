import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../../../../core/managers/module_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../animations_module/animations_module.dart';
import '../../../audio_module/audio_module.dart';
import '../../widgets/ui_kit/dutch_animated_cta_button.dart';
import 'widgets/dutch_promotion_burst.dart';

/// Full-screen celebration shown when the current user wins a match.
/// This mirrors the promotion visual language (burst + confetti + headline),
/// but keeps content focused on the win outcome.
class DutchWinCelebrationScreen extends StatefulWidget {
  const DutchWinCelebrationScreen({
    super.key,
    required this.winnerMessage,
  });

  final String winnerMessage;

  @override
  State<DutchWinCelebrationScreen> createState() => _DutchWinCelebrationScreenState();
}

class _DutchWinCelebrationScreenState extends State<DutchWinCelebrationScreen>
    with SingleTickerProviderStateMixin {
  static const bool LOGGING_SWITCH = true;
  static final Logger _logger = Logger();
  static const Duration _secondaryBurstDelay = Duration(milliseconds: 1500);

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
    _playWinSound();
    _scheduleSecondaryBurst();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entryController.forward();
      _leftConfetti.play();
      _rightConfetti.play();
      if (LOGGING_SWITCH) {
        _logger.info('DutchWinCelebrationScreen: opened');
      }
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

  void _playWinSound() {
    try {
      final audio = ModuleManager().getModuleByType<AudioModule>();
      audio?.playSound('level_up_1');
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('DutchWinCelebrationScreen: sound failed: $e');
      }
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

  @override
  void dispose() {
    _disposed = true;
    _secondaryBurstTimer?.cancel();
    _entryController.dispose();
    _leftConfetti.stop();
    _rightConfetti.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entryFade = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: const Interval(0.0, 0.5, curve: Curves.easeOut)))
        .animate(_entryController);
    final entryScale = Tween<double>(begin: 0.4, end: 1.0)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_entryController);

    return Semantics(
      identifier: 'win_celebration_screen',
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
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: entryFade,
                      child: _buildHeadline(),
                    ),
                    const SizedBox(height: 18),
                    ScaleTransition(
                      scale: entryScale,
                      child: Icon(
                        Icons.emoji_events_rounded,
                        size: 156,
                        color: AppColors.matchPotGold,
                        shadows: [
                          Shadow(
                            color: AppColors.matchPotGold.withValues(alpha: 0.55),
                            blurRadius: 22,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FadeTransition(
                      opacity: entryFade,
                      child: Text(
                        widget.winnerMessage,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyLarge(color: AppColors.white).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: entryFade,
                      child: DutchAnimatedCtaButton(
                        label: 'Continue',
                        onPressed: _close,
                        leadingIcon: Icons.check_circle_outline,
                        expand: false,
                        semanticIdentifier: 'win_celebration_continue',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: Material(
                color: Colors.black.withValues(alpha: 0.32),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _close,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadline() {
    return ShaderMask(
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
        'YOU WON!',
        textAlign: TextAlign.center,
        style: AppTextStyles.headingLarge(color: AppColors.white).copyWith(
          fontSize: 44,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
          height: 1.0,
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
}
