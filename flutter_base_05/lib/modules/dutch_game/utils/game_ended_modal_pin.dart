import '../../../../core/managers/state_manager.dart';

/// Persists the game-ended standings modal snapshot in [StateManager] so it
/// survives widget remounts and later WS/state merges (promotion, share, achievements).
class GameEndedModalPin {
  GameEndedModalPin._();

  static const String stateKey = 'gameEndedModalSnapshot';

  static Map<String, dynamic>? readRaw() {
    final dutch = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final raw = dutch[stateKey];
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
    }
    return null;
  }

  static void write(Map<String, dynamic> snapshot) {
    StateManager().updateModuleState('dutch_game', {
      stateKey: snapshot,
      'endGameModalOpen': true,
    });
  }

  static void clear() {
    StateManager().updateModuleState('dutch_game', {
      stateKey: null,
      'endGameModalOpen': false,
    });
  }

  static bool get isPinned => readRaw() != null;
}
