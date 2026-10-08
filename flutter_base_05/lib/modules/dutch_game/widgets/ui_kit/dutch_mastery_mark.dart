import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../utils/consts/theme_consts.dart';

const String _kMasteryStarsLottie = 'assets/lottie/MasteryStars.lottie';

/// Decoder for `.lottie` (dotlottie zip) assets: picks the first `.json` animation.
Future<LottieComposition?> _decodeDotLottie(List<int> bytes) {
  return LottieComposition.decodeZip(
    bytes,
    filePicker: (files) {
      for (final f in files) {
        final name = f.name.toLowerCase();
        if (name.endsWith('.json') && !name.endsWith('manifest.json')) {
          return f;
        }
      }
      for (final f in files) {
        if (f.name.endsWith('.json')) return f;
      }
      return files.isNotEmpty ? files.first : null;
    },
  );
}

Future<LottieComposition?> _loadMasteryStarsLottie() async {
  try {
    final data = await rootBundle.load(_kMasteryStarsLottie);
    final bytes = data.buffer.asUint8List();
    return await _decodeDotLottie(bytes).catchError((_, __) => null);
  } catch (_) {
    return null;
  }
}

/// Gold mastery mark. [banner] is the full-width feature block.
/// [chip] is the compact mark used beside a leaderboard name.
class DutchMasteryMark extends StatelessWidget {
  const DutchMasteryMark.banner({
    super.key,
    required this.value,
    this.semanticIdentifier,
    this.showIconBadge = true,
  }) : compact = false;

  const DutchMasteryMark.chip({
    super.key,
    required this.value,
    this.semanticIdentifier,
  })  : compact = true,
        showIconBadge = false;

  final int value;
  final bool compact;
  final String? semanticIdentifier;
  /// When false (e.g. home), stars render without the gold circle behind them.
  final bool showIconBadge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: semanticIdentifier,
      label: 'Mastery $value',
      child: compact ? _chip() : _banner(),
    );
  }

  Widget _banner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.matchPotGold.withValues(alpha: 0.22),
            AppColors.matchPotGoldLight.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: AppColors.matchPotGold, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.matchPotGold.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          showIconBadge
              ? _iconBadge(size: 44, iconSize: 24)
              : const SizedBox(
                  width: 88,
                  height: 88,
                  child: Center(child: DutchMasteryStarsLottie(size: 48)),
                ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MASTERY',
                  style: AppTextStyles.caption(color: AppColors.matchPotGold).copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$value',
                  style: AppTextStyles.headingLarge(color: AppColors.matchPotGold).copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                Text(
                  'How cleanly you finish',
                  style: AppTextStyles.bodySmall(color: AppColors.matchPotGoldLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.matchPotGold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.matchPotGold.withValues(alpha: 0.85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DutchMasteryStarsLottie(size: 14),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: AppTextStyles.bodySmall(color: AppColors.matchPotGold).copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBadge({required double size, required double iconSize}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.matchPotGoldLight,
            AppColors.matchPotGold,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.matchPotGold.withValues(alpha: 0.4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: DutchMasteryStarsLottie(size: iconSize),
      ),
    );
  }
}

/// Mastery stars Lottie at a fixed layout size (home end-match uses 48).
class DutchMasteryStarsLottie extends StatefulWidget {
  const DutchMasteryStarsLottie({super.key, required this.size});

  final double size;

  @override
  State<DutchMasteryStarsLottie> createState() => _DutchMasteryStarsLottieState();
}

class _DutchMasteryStarsLottieState extends State<DutchMasteryStarsLottie> {
  late Future<LottieComposition?> _compositionFuture;

  @override
  void initState() {
    super.initState();
    _compositionFuture = _loadMasteryStarsLottie();
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size;
    return SizedBox(
      width: box,
      height: box,
      child: FutureBuilder<LottieComposition?>(
        future: _compositionFuture,
        builder: (context, snapshot) {
          final composition = snapshot.data;
          if (snapshot.hasError || composition == null) {
            return SizedBox(width: box, height: box);
          }
          return Lottie(
            composition: composition,
            fit: BoxFit.contain,
            repeat: true,
          );
        },
      ),
    );
  }
}
