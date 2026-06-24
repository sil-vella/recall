import 'package:flutter/material.dart';

import '../../../utils/dutch_dot_lottie.dart';
import 'play_band_lottie_overlay.dart';

export 'play_band_lottie_overlay.dart' show kPlayBandLottieBox;

/// Max Lottie edge in the poof band above myHand (~card width).
const double kSameRankPoofLottieBox = kPlayBandLottieBox;

/// Non-interactive same-rank poof overlay. [triggerToken] increments to play once.
class SameRankPoofOverlay extends StatelessWidget {
  const SameRankPoofOverlay({
    super.key,
    required this.triggerToken,
  });

  final int triggerToken;

  @override
  Widget build(BuildContext context) {
    return PlayBandLottieOverlay(
      triggerToken: triggerToken,
      lottieAsset: kSameRankPoofLottie,
      boxSize: kSameRankPoofLottieBox,
    );
  }
}
