import 'package:flutter/material.dart';

import '../consts/theme_consts.dart';

/// Plain gold coin glyph without a currency symbol.
///
/// Prefer this over [Icons.monetization_on] (which shows a dollar sign).
/// For APIs that require [IconData] only (e.g. navigation drawer), use [kCoinIconData].
class CoinIcon extends StatelessWidget {
  const CoinIcon({
    super.key,
    this.size = 24,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final coinColor = color ?? AppColors.matchPotGold;
    final rim = size * 0.09;
    final inner = size * 0.52;

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: coinColor,
          border: Border.all(
            color: AppColors.matchPotGoldLight.withValues(alpha: 0.75),
            width: rim,
          ),
          boxShadow: [
            BoxShadow(
              color: coinColor.withValues(alpha: 0.3),
              blurRadius: size * 0.08,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: inner,
            height: inner,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.matchPotGoldLight.withValues(alpha: 0.45),
                width: size * 0.035,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Material coin icon without a currency symbol — for [IconData]-only APIs (drawer, etc.).
const IconData kCoinIconData = Icons.toll;
