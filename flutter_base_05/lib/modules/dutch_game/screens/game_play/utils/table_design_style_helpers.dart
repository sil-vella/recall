import 'package:flutter/material.dart';

import '../../../../../../core/managers/state_manager.dart';
import '../../../../../../utils/consts/config.dart';
import '../../../../../../utils/consts/theme_consts.dart';
import '../../../utils/consumables_catalog_bootstrap.dart';
import '../../../backend_core/utils/level_matcher.dart';

class TableDesignStyleHelpers {
  /// Bundled defaults when no cosmetic is equipped (not loaded from API).
  static const String defaultTableOverlayAsset = 'assets/images/table_logo.webp';
  static const String defaultCardBackAsset = 'assets/images/card_back.webp';

  static String readEquippedTableDesignId(Map<String, dynamic> dutchState) {
    final userStats = dutchState['userStats'] as Map<String, dynamic>? ?? {};
    final inventory = userStats['inventory'] as Map<String, dynamic>? ?? {};
    final cosmetics = inventory['cosmetics'] as Map<String, dynamic>? ?? {};
    final equipped = cosmetics['equipped'] as Map<String, dynamic>? ?? {};
    return equipped['table_design_id']?.toString().trim() ?? '';
  }

  static Color outerBorderColorForDesign(String tableDesignId) {
    return outerBorderColorFromStyle(ConsumablesCatalogBootstrap.getStyleForItem(tableDesignId));
  }

  static Color outerBorderGlowForDesign(String tableDesignId) {
    return outerBorderGlowFromStyle(ConsumablesCatalogBootstrap.getStyleForItem(tableDesignId));
  }

  static bool isJuventusTableDesign(String tableDesignId) {
    return isStripeBorderFromStyle(ConsumablesCatalogBootstrap.getStyleForItem(tableDesignId));
  }

  static String borderStyleForDesign(String tableDesignId) {
    return borderStyleFromStyle(ConsumablesCatalogBootstrap.getStyleForItem(tableDesignId));
  }

  static List<Color> borderColorsForDesign(String tableDesignId) {
    return borderColorsFromStyle(ConsumablesCatalogBootstrap.getStyleForItem(tableDesignId));
  }

  /// Declarative rim colors from catalog / special-event ``style`` map.
  static Color outerBorderColorFromStyle(Map<String, dynamic> style) {
    final colors = borderColorsFromStyle(style);
    if (colors.isNotEmpty) return colors.first;
    return AppColors.casinoOuterBorderColor;
  }

  static Color outerBorderGlowFromStyle(Map<String, dynamic> style) {
    final colors = borderColorsFromStyle(style);
    if (colors.isNotEmpty) return colors.first.withValues(alpha: 0.55);
    return AppColors.black.withValues(alpha: 0.8);
  }

  static bool isStripeBorderFromStyle(Map<String, dynamic> style) {
    return borderStyleFromStyle(style) == 'stripes';
  }

  static String borderStyleFromStyle(Map<String, dynamic> style) {
    final borderStyle = style['border_style']?.toString().trim().toLowerCase() ?? '';
    if (borderStyle == 'stripes') return 'stripes';
    return 'solid';
  }

  static List<Color> borderColorsFromStyle(Map<String, dynamic> style) {
    final raw = style['border_colors'];
    if (raw is! List) return const <Color>[];
    final out = <Color>[];
    for (final item in raw.take(2)) {
      final c = _parseHexColor(item?.toString());
      if (c != null) out.add(c);
    }
    return out;
  }

  static Map<String, dynamic> specialEventBorderStyleMap(String? specialEventId) {
    final eid = specialEventId?.trim() ?? '';
    if (eid.isEmpty) return const {};
    final row = LevelMatcher.specialEventRowById(eid);
    final st = row?['style'];
    if (st is Map) {
      return Map<String, dynamic>.from(st.map((k, v) => MapEntry(k.toString(), v)));
    }
    return const {};
  }

  static Color? _parseHexColor(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final hex = v.startsWith('#') ? v.substring(1) : v;
    if (hex.length != 6 && hex.length != 8) return null;
    final full = hex.length == 6 ? 'FF$hex' : hex;
    final parsed = int.tryParse(full, radix: 16);
    if (parsed == null) return null;
    return Color(parsed);
  }

  /// Network URL for an equipped table design overlay, or null when the bundled default applies.
  static String? buildOverlayNetworkUrl({
    required String currentGameId,
    required String equippedTableDesignId,
    int imageVersion = 1,
  }) {
    final id = equippedTableDesignId.trim();
    if (id.isEmpty) return null;
    return currentGameId.isNotEmpty
        ? '${Config.apiUrl}/app_media/media/table_design_overlay.webp?skinId=$id&gameId=$currentGameId&v=$imageVersion'
        : '${Config.apiUrl}/app_media/media/table_design_overlay.webp?skinId=$id&v=$imageVersion';
  }

  /// Bundled default table overlay (no equipped shop cosmetic).
  static Widget defaultTableOverlayImage({
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
  }) {
    return Image.asset(
      defaultTableOverlayAsset,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

/// Juventus side border style:
/// - top/bottom bands: vertical black-white stripes
/// - left/right bands: horizontal black-white stripes
class JuventusStripeBorderPainter extends CustomPainter {
  final double borderWidth;
  final double borderRadius;
  final List<Color> stripeColors;

  const JuventusStripeBorderPainter({
    required this.borderWidth,
    required this.borderRadius,
    this.stripeColors = const [AppColors.black, AppColors.white],
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
      ..color = stripeColors.first;
    canvas.drawRRect(outer, base);

    // Triple Juventus stripe thickness vs original baseline (borderWidth / 2.2).
    final stripe = (borderWidth * 1.36).clamp(10.0, 30.0);
    final stripePaint = Paint()
      ..color = stripeColors.length > 1 ? stripeColors[1] : stripeColors.first;

    for (double x = 0; x < size.width; x += stripe * 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, borderWidth), stripePaint);
      canvas.drawRect(
        Rect.fromLTWH(x, size.height - borderWidth, stripe, borderWidth),
        stripePaint,
      );
    }

    for (double y = 0; y < size.height; y += stripe * 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, borderWidth, stripe), stripePaint);
      canvas.drawRect(
        Rect.fromLTWH(size.width - borderWidth, y, borderWidth, stripe),
        stripePaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant JuventusStripeBorderPainter oldDelegate) {
    return oldDelegate.borderWidth != borderWidth ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.stripeColors != stripeColors;
  }
}

Map<String, dynamic> currentDutchState() {
  return StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
}
