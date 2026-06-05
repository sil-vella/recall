import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../../core/managers/module_manager.dart';
import '../../modules/animations_module/animations_module.dart';
import '../../modules/audio_module/audio_module.dart';
import '../../modules/dutch_game/screens/promotion/widgets/dutch_promotion_burst.dart'
    show
        DutchPromotionBurst,
        kDutchPromotionBurstCoinStackLottie,
        kDutchPromotionBurstForegroundSpacer;
import '../../modules/dutch_game/widgets/ui_kit/dutch_animated_cta_button.dart';
import '../../utils/consts/theme_consts.dart';

/// Full-screen celebration after a successful native coin purchase (iOS / Android).
/// Visual language matches [DutchWinCelebrationScreen] and [DutchAchievementCelebrationScreen].
class CoinPurchaseCelebrationScreen extends StatefulWidget {
  const CoinPurchaseCelebrationScreen({
    super.key,
    required this.successMessage,
  });

  final String successMessage;

  @override
  State<CoinPurchaseCelebrationScreen> createState() => _CoinPurchaseCelebrationScreenState();
}

class _CoinPurchaseCelebrationScreenState extends State<CoinPurchaseCelebrationScreen>
    with SingleTickerProviderStateMixin {
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
    _playSound();
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

  void _playSound() {
    try {
      final audio = ModuleManager().getModuleByType<AudioModule>();
      audio?.playSound('level_up_1');
    } catch (_) {}
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

    return Semantics(
      identifier: 'coin_purchase_celebration_screen',
      label: 'Coin purchase successful: ${widget.successMessage}',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(),
            DutchPromotionBurst(
              leftController: _leftConfetti,
              rightController: _rightConfetti,
              centerLottieAsset: kDutchPromotionBurstCoinStackLottie,
            ),
            SafeArea(
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
                        child: _buildHeadline(),
                      ),
                      const SizedBox(height: 20),
                      FadeTransition(
                        opacity: entryFade,
                        child: Text(
                          widget.successMessage,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyLarge(color: AppColors.white).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FadeTransition(
                        opacity: entryFade,
                        child: Center(
                          child: DutchAnimatedCtaButton(
                            label: 'Continue',
                            onPressed: _close,
                            leadingIcon: Icons.check_circle_outline,
                            expand: false,
                            semanticIdentifier: 'coin_purchase_celebration_continue',
                          ),
                        ),
                      ),
                    ],
                  ),
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
        'COINS ADDED!',
        textAlign: TextAlign.center,
        style: AppTextStyles.headingLarge(color: AppColors.white).copyWith(
          fontSize: 40,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
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
