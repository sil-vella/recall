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

Future<LottieComposition?> _loadWinnerLottieSafe() async {
  try {
    final data = await rootBundle.load('assets/lottie/winner01.lottie');
    final bytes = data.buffer.asUint8List();
    return await _decodeDotLottie(bytes).catchError((_, __) => null);
  } catch (_) {
    return null;
  }
}

/// Top-of-stack composition: a centered Winner Lottie behind two corner-blast
/// confetti emitters. Pure presentation — owners drive the controllers.
class DutchPromotionBurst extends StatefulWidget {
  const DutchPromotionBurst({
    super.key,
    required this.leftController,
    required this.rightController,
  });

  final ConfettiController leftController;
  final ConfettiController rightController;

  @override
  State<DutchPromotionBurst> createState() => _DutchPromotionBurstState();
}

class _DutchPromotionBurstState extends State<DutchPromotionBurst> {
  late final Future<LottieComposition?> _compositionFuture =
      _loadWinnerLottieSafe();

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
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: SizedBox(
              width: 360,
              height: 360,
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
                  return Icon(
                    Icons.emoji_events,
                    size: 220,
                    color: AppColors.matchPotGold.withValues(alpha: 0.55),
                  );
                },
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
