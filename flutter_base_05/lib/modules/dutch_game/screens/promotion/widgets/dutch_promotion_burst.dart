import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../../utils/consts/theme_consts.dart';

/// Decoder for `.lottie` (dotlottie zip) assets: picks the first `.json` animation.
/// Mirrors the helper used in `messages_widget.dart` so the same composition
/// loads cleanly here too.
Future<LottieComposition?> _decodeDotLottie(List<int> bytes) {
  return LottieComposition.decodeZip(
    bytes,
    filePicker: (files) {
      for (final f in files) {
        if (f.name.endsWith('.json')) return f;
      }
      return files.isNotEmpty ? files.first : null;
    },
  );
}

Future<LottieComposition?> _loadDotLottieFromAsset(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    return await _decodeDotLottie(bytes).catchError((_, __) => null);
  } catch (_) {
    return null;
  }
}

/// Default celebration animation asset (win / promotion style).
const String kDutchPromotionBurstDefaultLottie = 'assets/lottie/winner01.lottie';

/// Achievement unlock fullscreen asset.
const String kDutchPromotionBurstAchievementLottie = 'assets/lottie/achievement.lottie';

/// Lottie square edge length (sync with fullscreen foreground spacers).
const double kDutchPromotionBurstLottieBox = 234;

/// Top offset inside the full-screen stack (below status bar).
const double kDutchPromotionBurstTopInnerPadding = 8;

const double kDutchPromotionBurstHorizontalPadding = 24;

/// Gap between Lottie bottom and first headline when foreground sits inside [SafeArea]
/// (coordinates start below the notch; matches burst `topInner + lottie + gap`).
const double kDutchPromotionBurstForegroundSpacer =
    kDutchPromotionBurstTopInnerPadding + kDutchPromotionBurstLottieBox + 16;

/// Top-of-stack composition: a **top-aligned** Lottie (~half the former 360px
/// hero size) behind two corner-blast confetti emitters. Owners drive the
/// controllers.
///
/// [centerLottieAsset] — bundle path to a `.lottie` file (no icon fallback;
/// empty space if the asset fails to load).
class DutchPromotionBurst extends StatefulWidget {
  const DutchPromotionBurst({
    super.key,
    required this.leftController,
    required this.rightController,
    this.centerLottieAsset = kDutchPromotionBurstDefaultLottie,
  });

  final ConfettiController leftController;
  final ConfettiController rightController;

  /// Asset key for the top-aligned dotLottie (e.g. [kDutchPromotionBurstDefaultLottie]
  /// or [kDutchPromotionBurstAchievementLottie]).
  final String centerLottieAsset;

  @override
  State<DutchPromotionBurst> createState() => _DutchPromotionBurstState();
}

class _DutchPromotionBurstState extends State<DutchPromotionBurst> {
  late Future<LottieComposition?> _compositionFuture;

  @override
  void initState() {
    super.initState();
    _compositionFuture = _loadDotLottieFromAsset(widget.centerLottieAsset);
  }

  @override
  void didUpdateWidget(DutchPromotionBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centerLottieAsset != widget.centerLottieAsset) {
      _compositionFuture = _loadDotLottieFromAsset(widget.centerLottieAsset);
    }
  }

  /// On-theme palette for confetti. Keeps the celebration feeling on-brand
  /// regardless of the active [ThemePreset].
  List<Color> get _confettiColors => [
        AppColors.matchPotGold,
        AppColors.matchPotGoldLight,
        AppColors.accentColor,
        AppColors.accentColor2,
        AppColors.white,
      ];

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              kDutchPromotionBurstHorizontalPadding,
              topInset + kDutchPromotionBurstTopInnerPadding,
              kDutchPromotionBurstHorizontalPadding,
              0,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: kDutchPromotionBurstLottieBox,
                height: kDutchPromotionBurstLottieBox,
                child: FutureBuilder<LottieComposition?>(
                  future: _compositionFuture,
                  builder: (context, snapshot) {
                    final composition = snapshot.data;
                    if (!snapshot.hasError && composition != null) {
                      return Lottie(
                        composition: composition,
                        fit: BoxFit.contain,
                        repeat: true,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: ConfettiWidget(
              confettiController: widget.leftController,
              blastDirection: math.pi / 4,
              emissionFrequency: 0.04,
              numberOfParticles: 14,
              maxBlastForce: 22,
              minBlastForce: 8,
              gravity: 0.18,
              shouldLoop: false,
              colors: _confettiColors,
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: ConfettiWidget(
              confettiController: widget.rightController,
              blastDirection: 3 * math.pi / 4,
              emissionFrequency: 0.04,
              numberOfParticles: 14,
              maxBlastForce: 22,
              minBlastForce: 8,
              gravity: 0.18,
              shouldLoop: false,
              colors: _confettiColors,
            ),
          ),
        ],
      ),
    );
  }
}
