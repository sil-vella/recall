import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../utils/consts/theme_consts.dart';
import '../backend_core/utils/level_matcher.dart';
import 'local_table_bg_image_stub.dart'
    if (dart.library.io) 'local_table_bg_image_io.dart' as table_bg_fs;

/// Parses `#RRGGBB` / `#RRGGBBAA` hex into [Color], or returns null if invalid.
Color? dutchHexToColor(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('#')) {
    s = s.substring(1);
  }
  if (s.length == 6) {
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
  if (s.length == 8) {
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    final a = (v >> 24) & 0xFF;
    final rgb = v & 0x00FFFFFF;
    return Color.fromARGB(a, (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
  }
  return null;
}
/// Per–table-tier styling for the **inset game table** (felt + spotlights), keyed by room **table**
/// tier (`game_level` / `gameLevel` 1–4), not the user's progression level.
///
/// The game play screen body backdrop uses the same tier [feltBackground] as the table.
/// [playScreenBackdropColor] remains available as a neutral default where a fixed backdrop is needed.
///
/// Non-felt UI (chips, borders, cards) continues to use [AppColors] directly until extended here.
class DutchGamePlayTableStyle {
  const DutchGamePlayTableStyle({
    required this.feltBackground,
    required this.spotlightColor,
  });

  /// Felt base color for the **table card** only: [FeltTextureWidget] and matching fill under the clip.
  final Color feltBackground;

  /// Radial spotlight gradients at the table edges (warm casino lighting).
  final Color spotlightColor;
}

/// Maps table tier numbers to [DutchGamePlayTableStyle] and optional **decorative overlay** assets.
///
/// - Level **1** (Home): [AppColors.pokerTableGreen], warm spotlights.
/// - Level **2** (Local): [AppColors.pokerTableBlue], warm spotlights.
/// - Level **3** (Town): [AppColors.pokerTableTown], warm spotlights.
/// - Level **4** (City): [AppColors.pokerTableCity], warm spotlights.
///
/// Tier back illustrations are loaded from server `back_graphic_url` and cached on disk (non-web), not bundled.
class DutchGamePlayTableStyles {
  DutchGamePlayTableStyles._();

  static Widget _tableBackGraphicFeltFallback(int tableLevel) {
    final s = DutchGamePlayTableStyles.forLevel(tableLevel);
    final mid = Color.lerp(s.feltBackground, s.spotlightColor, 0.12);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.35),
          radius: 1.35,
          colors: [
            mid ?? s.feltBackground,
            s.feltBackground,
          ],
          stops: const [0.0, 1.0],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  /// Full-bleed background: `back_graphic_url` → downloaded file cache → felt gradient (no bundled art).
  static Widget tableBackGraphicFill(int tableLevel, {BoxFit fit = BoxFit.cover}) {
    LevelMatcher.ensureHydratedMinimal();
    final styleMap = LevelMatcher.styleForLevel(tableLevel);
    final urlRemote = (styleMap['back_graphic_url'] ?? '').toString().trim();
    final urlOk =
        urlRemote.isNotEmpty && (urlRemote.startsWith('http://') || urlRemote.startsWith('https://'));
    if (urlOk) {
      return Image.network(
        urlRemote,
        fit: fit,
        errorBuilder: (_, __, ___) => _tableBackGraphicFeltFallback(tableLevel),
      );
    }
    if (!kIsWeb) {
      final cachedPath = LevelMatcher.localGraphicPathForLevel(tableLevel);
      final p = cachedPath ?? '';
      if (p.isNotEmpty && table_bg_fs.localTableBackGraphicCached(p)) {
        return table_bg_fs.localTableBgImageFile(p, fit: fit);
      }
    }
    return _tableBackGraphicFeltFallback(tableLevel);
  }

  static Widget _tableBackGraphicEventFeltFallback(
    Map<String, dynamic> styleMap,
    int fallbackTableLevel,
  ) {
    LevelMatcher.ensureHydratedMinimal();
    final felt = dutchHexToColor(styleMap['felt_hex']?.toString()) ??
        DutchGamePlayTableStyles.forLevel(fallbackTableLevel).feltBackground;
    final spot = dutchHexToColor(styleMap['spotlight_hex']?.toString()) ??
        DutchGamePlayTableStyles.forLevel(fallbackTableLevel).spotlightColor;
    final mid = Color.lerp(felt, spot, 0.12);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.35),
          radius: 1.35,
          colors: [
            mid ?? felt,
            felt,
          ],
          stops: const [0.0, 1.0],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  /// Like [tableBackGraphicFill] but for a catalog `special_events` row (filesystem cache keyed by [eventId]).
  static Widget tableBackGraphicFillForSpecialEvent({
    required String eventId,
    required Map<String, dynamic> styleMap,
    BoxFit fit = BoxFit.cover,
    int fallbackTableLevel = 1,
  }) {
    LevelMatcher.ensureHydratedMinimal();
    final trimmedId = eventId.trim();
    final urlRemote = (styleMap['back_graphic_url'] ?? '').toString().trim();
    final urlOk =
        urlRemote.isNotEmpty && (urlRemote.startsWith('http://') || urlRemote.startsWith('https://'));
    if (urlOk) {
      return Image.network(
        urlRemote,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            _tableBackGraphicEventFeltFallback(styleMap, fallbackTableLevel),
      );
    }
    if (!kIsWeb && trimmedId.isNotEmpty) {
      final cachedPath = LevelMatcher.localGraphicPathForEvent(trimmedId);
      final p = cachedPath ?? '';
      if (p.isNotEmpty && table_bg_fs.localTableBackGraphicCached(p)) {
        return table_bg_fs.localTableBgImageFile(p, fit: fit);
      }
    }
    return _tableBackGraphicEventFeltFallback(styleMap, fallbackTableLevel);
  }
  /// Solid fill for the entire play [BaseScreen] body (behind header slot, letterbox, etc.).
  /// Intentionally **not** tier-specific so e.g. table 2 can use blue felt on the table only.
  static const Color playScreenBackdropColor = AppColors.pokerTableGreen;

  static const DutchGamePlayTableStyle _table1Home = DutchGamePlayTableStyle(
    feltBackground: AppColors.pokerTableGreen,
    spotlightColor: AppColors.warmSpotlightColor,
  );

  static const DutchGamePlayTableStyle _table2Local = DutchGamePlayTableStyle(
    feltBackground: AppColors.pokerTableBlue,
    spotlightColor: AppColors.warmSpotlightColor,
  );

  static const DutchGamePlayTableStyle _table3Town = DutchGamePlayTableStyle(
    feltBackground: AppColors.pokerTableTown,
    spotlightColor: AppColors.warmSpotlightColor,
  );

  static const DutchGamePlayTableStyle _table4City = DutchGamePlayTableStyle(
    feltBackground: AppColors.pokerTableCity,
    spotlightColor: AppColors.warmSpotlightColor,
  );

  static DutchGamePlayTableStyle _legacyFallback(int level) {
    switch (level) {
      case 2:
        return _table2Local;
      case 3:
        return _table3Town;
      case 4:
        return _table4City;
      case 1:
      default:
        return _table1Home;
    }
  }

  /// Resolved style — catalog hex when present ([LevelMatcher]); else bundled defaults.
  static DutchGamePlayTableStyle forLevel(int level) {
    LevelMatcher.ensureHydratedMinimal();
    final styleMap = LevelMatcher.styleForLevel(level);
    final felt = dutchHexToColor(styleMap['felt_hex']?.toString());
    final spot = dutchHexToColor(styleMap['spotlight_hex']?.toString());
    final leg = _legacyFallback(level);
    return DutchGamePlayTableStyle(
      feltBackground: felt ?? leg.feltBackground,
      spotlightColor: spot ?? leg.spotlightColor,
    );
  }

  /// Event-aware style resolver. Uses `special_events[].style` when [specialEventId] is present; otherwise tier style.
  static DutchGamePlayTableStyle resolveStyle({
    required int level,
    String? specialEventId,
  }) {
    final eventId = specialEventId?.trim() ?? '';
    if (eventId.isEmpty) return forLevel(level);
    final row = LevelMatcher.specialEventRowById(eventId);
    final styleMap = row?['style'];
    if (styleMap is! Map) return forLevel(level);
    final map = Map<String, dynamic>.from(styleMap);
    final base = forLevel(level);
    return DutchGamePlayTableStyle(
      feltBackground: dutchHexToColor(map['felt_hex']?.toString()) ?? base.feltBackground,
      spotlightColor: dutchHexToColor(map['spotlight_hex']?.toString()) ?? base.spotlightColor,
    );
  }

  /// Event-aware background art resolver. Uses special-event art lane when [specialEventId] is set.
  static Widget tableBackGraphicFillFor({
    required int level,
    String? specialEventId,
    BoxFit fit = BoxFit.cover,
  }) {
    final eventId = specialEventId?.trim() ?? '';
    if (eventId.isEmpty) return tableBackGraphicFill(level, fit: fit);
    final row = LevelMatcher.specialEventRowById(eventId);
    final styleMap = row?['style'];
    if (styleMap is! Map) return tableBackGraphicFill(level, fit: fit);
    return tableBackGraphicFillForSpecialEvent(
      eventId: eventId,
      styleMap: Map<String, dynamic>.from(styleMap),
      fit: fit,
      fallbackTableLevel: level,
    );
  }
  /// Deprecated: table felt is strictly bound to room table level.
  /// Cosmetic table designs should style overlay/border only, not felt color.
  static DutchGamePlayTableStyle forLevelWithDesign(int level, String? designId) {
    return forLevel(level);
  }
}

/// Reads room table tier from `dutch_game` module state (games map / game_state).
int resolveDutchGamePlayTableLevel(Map<String, dynamic>? dutchGameState) {
  if (dutchGameState == null || dutchGameState.isEmpty) {
    return 1;
  }
  final id = dutchGameState['currentGameId']?.toString().trim() ?? '';
  final gameInfo = dutchGameState['gameInfo'] as Map<String, dynamic>?;
  final resolvedId = id.isNotEmpty
      ? id
      : (gameInfo?['currentGameId']?.toString().trim() ?? '');
  if (resolvedId.isEmpty) {
    return 1;
  }
  final games = dutchGameState['games'] as Map<String, dynamic>?;
  final gameEntry = games?[resolvedId] as Map<String, dynamic>?;
  if (gameEntry == null) {
    return 1;
  }

  dynamic gl = gameEntry['gameLevel'] ?? gameEntry['game_level'];
  if (gl == null) {
    final gameData = gameEntry['gameData'] as Map<String, dynamic>?;
    final gameState = gameData?['game_state'] as Map<String, dynamic>?;
    gl = gameState?['gameLevel'] ?? gameState?['game_level'];
  }
  return _parseTableLevelInt(gl);
}

/// Reads active room `special_event_id` from games map / game_state (if any).
String? resolveDutchGamePlaySpecialEventId(Map<String, dynamic>? dutchGameState) {
  if (dutchGameState == null || dutchGameState.isEmpty) {
    return null;
  }
  final id = dutchGameState['currentGameId']?.toString().trim() ?? '';
  final gameInfo = dutchGameState['gameInfo'] as Map<String, dynamic>?;
  final resolvedId = id.isNotEmpty
      ? id
      : (gameInfo?['currentGameId']?.toString().trim() ?? '');
  if (resolvedId.isEmpty) {
    return null;
  }
  final games = dutchGameState['games'] as Map<String, dynamic>?;
  final gameEntry = games?[resolvedId] as Map<String, dynamic>?;
  if (gameEntry == null) {
    return null;
  }

  dynamic raw = gameEntry['special_event_id'];
  if (raw == null) {
    final gameData = gameEntry['gameData'] as Map<String, dynamic>?;
    final gameState = gameData?['game_state'] as Map<String, dynamic>?;
    raw = gameState?['special_event_id'];
  }
  final seId = raw?.toString().trim() ?? '';
  return seId.isEmpty ? null : seId;
}

int _parseTableLevelInt(dynamic gl) {
  LevelMatcher.ensureHydratedMinimal();
  final minL = LevelMatcher.minConfiguredTableLevel;
  final maxL = LevelMatcher.maxConfiguredTableLevel;
  final raw = gl is int
      ? gl
      : gl is num
          ? gl.toInt()
          : int.tryParse('$gl');
  final fallback = LevelMatcher.levelOrder.contains(1) ? 1 : minL;
  return (raw ?? fallback).clamp(minL, maxL);
}
