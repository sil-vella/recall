import '../../../../core/managers/navigation_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../managers/dutch_event_handler_callbacks.dart';
import '../../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';

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

  /// Hides the game-ended overlay. When [navigateToLobby] is false, keeps the user on
  /// game-play (e.g. rematch waiting / new deal). When true, clears rematch wait and
  /// navigates to the lobby.
  static void dismissOverlay({bool navigateToLobby = false}) {
    if (LOGGING_SWITCH) {
      final dutch =
          StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      customlog(
        'rematch: dismissOverlay navigateToLobby=$navigateToLobby '
        'gamePhase=${dutch['gamePhase']} rematchWaiting=${dutch['rematch_waiting_game_id']} '
        'endGameModalOpen=${dutch['endGameModalOpen']} '
        'roster=${DutchEventHandlerCallbacks.dutchGameRosterLog(
          dutch['rematch_waiting_game_id']?.toString() ??
              dutch['currentGameId']?.toString() ??
              '',
        )}',
      );
    }
    clear();
    final patch = <String, dynamic>{
      'messages': {
        'isVisible': false,
        'title': '',
        'content': '',
        'type': 'info',
        'showCloseButton': true,
        'autoClose': false,
        'autoCloseDelay': 3000,
      },
    };
    if (navigateToLobby) {
      patch['rematch_waiting_game_id'] = '';
    }
    StateManager().updateModuleState('dutch_game', patch);
    if (navigateToLobby) {
      NavigationManager().navigateTo('/dutch/lobby');
    }
  }

  static bool get isPinned => readRaw() != null;
}
