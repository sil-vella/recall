import 'package:flutter/material.dart';

import '../../../../../../core/managers/state_manager.dart';
import '../../../../../../utils/consts/config.dart';
import '../../../../../../utils/consts/theme_consts.dart';

class TableDesignStyleHelpers {
  static String readEquippedTableDesignId(Map<String, dynamic> dutchState) {
    final userStats = dutchState['userStats'] as Map<String, dynamic>? ?? {};
    final inventory = userStats['inventory'] as Map<String, dynamic>? ?? {};
    final cosmetics = inventory['cosmetics'] as Map<String, dynamic>? ?? {};
    final equipped = cosmetics['equipped'] as Map<String, dynamic>? ?? {};
    return equipped['table_design_id']?.toString() ?? '';
  }

  static Color outerBorderColorForDesign(String tableDesignId) {
    switch (tableDesignId.trim()) {
      case 'table_design_neon':
        return AppColors.pokerTableBlue;
      case 'table_design_royal':
        return AppColors.pokerTableCity;
      default:
        return AppColors.casinoOuterBorderColor;
    }
  }

  static Color outerBorderGlowForDesign(String tableDesignId) {
    switch (tableDesignId.trim()) {
      case 'table_design_neon':
        return AppColors.pokerTableBlue.withValues(alpha: 0.55);
      case 'table_design_royal':
        return AppColors.pokerTableCity.withValues(alpha: 0.55);
      default:
        return AppColors.black.withValues(alpha: 0.8);
    }
  }

  static bool isJuventusTableDesign(String tableDesignId) {
    return tableDesignId.trim() == 'table_design_juventus';
  }

  static String buildOverlayUrl({
    required String currentGameId,
    required String equippedTableDesignId,
    int imageVersion = 1,
  }) {
    if (equippedTableDesignId.isNotEmpty) {
      return currentGameId.isNotEmpty
          ? '${Config.apiUrl}/sponsors/media/table_design_overlay.webp?skinId=$equippedTableDesignId&gameId=$currentGameId&v=$imageVersion'
          : '${Config.apiUrl}/sponsors/media/table_design_overlay.webp?skinId=$equippedTableDesignId&v=$imageVersion';
    }
    return currentGameId.isNotEmpty
        ? '${Config.apiUrl}/sponsors/media/table_logo.webp?gameId=$currentGameId&v=2'
        : '${Config.apiUrl}/sponsors/media/table_logo.webp?v=2';
  }
}

/// Juventus side border style:
/// - top/bottom bands: vertical black-white stripes
/// - left/right bands: horizontal black-white stripes
class JuventusStripeBorderPainter extends CustomPainter {
  final double borderWidth;
  final double borderRadius;

  const JuventusStripeBorderPainter({
    required this.borderWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );
    canvas.save();
    canvas.clipRRect(outer);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = AppColors.black;
    canvas.drawRRect(outer, base);

    // Triple Juventus stripe thickness vs original baseline (borderWidth / 2.2).
    final stripe = (borderWidth * 1.36).clamp(10.0, 30.0);
    final white = Paint()..color = AppColors.white;

    for (double x = 0; x < size.width; x += stripe * 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, borderWidth), white);
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - borderWidth, stripe, borderWidth),
        white,
      );
    }

    for (double y = 0; y < size.height; y += stripe * 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, borderWidth, stripe), white);
      canvas.drawRect(
        Rect.fromLTWH(size.width - borderWidth, y, borderWidth, stripe),
        white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant JuventusStripeBorderPainter oldDelegate) {
    return oldDelegate.borderWidth != borderWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}

Map<String, dynamic> currentDutchState() {
  return StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
}
