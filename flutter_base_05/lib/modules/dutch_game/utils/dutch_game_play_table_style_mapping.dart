import 'package:flutter/material.dart';

import '../../../../utils/consts/theme_consts.dart';

/// Per–table-tier styling for the **inset game table** (felt + spotlights), keyed by room **table**
/// tier (`game_level` / `gameLevel` 1–4), not the user's progression level.
///
/// The **full play screen** body (margins around the table) uses
/// [DutchGamePlayTableStyles.playScreenBackdropColor] only — always green so higher tiers can use
/// a different felt on the table without recoloring the whole screen.
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

/// Maps table tier numbers to [DutchGamePlayTableStyle].
///
/// - Level **1** (Home): green felt on the table, warm spotlights.
/// - Level **2** (Local): **blue** felt on the table only; [playScreenBackdropColor] stays green.
/// - Levels **3** and **4**: same as level 1 until distinct art is defined.
class DutchGamePlayTableStyles {
  DutchGamePlayTableStyles._();

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

  /// Resolved style for a room table tier. Unknown or out-of-range values use table 1.
  static DutchGamePlayTableStyle forLevel(int level) {
    switch (level) {
      case 2:
        return _table2Local;
      case 1:
      case 3:
      case 4:
      default:
        return _table1Home;
    }
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

int _parseTableLevelInt(dynamic gl) {
  if (gl is int) return gl.clamp(1, 4);
  if (gl is num) return gl.toInt().clamp(1, 4);
  final p = int.tryParse('$gl');
  return (p ?? 1).clamp(1, 4);
}
