import '../../../core/managers/auth_manager.dart';
import '../../../core/managers/hooks_manager.dart';
import '../../../core/managers/state_manager.dart';
import 'dutch_game_helpers.dart';

/// Gates multiplayer lobby actions until startup JWT validation and WS authenticate both succeed.
class MultiplayerSessionReadiness {
  MultiplayerSessionReadiness._();

  static const _loginModule = 'login';

  static Map<String, dynamic> _loginState() =>
      StateManager().getModuleState<Map<String, dynamic>>(_loginModule) ?? {};

  static bool get isLoggedIn => _loginState()['isLoggedIn'] == true;

  static bool get isStartupPending => _loginState()['sessionStartupPending'] == true;

  static bool get isChecking => _loginState()['multiplayerSessionChecking'] == true;

  static bool get isReady => _loginState()['multiplayerSessionReady'] == true;

  static String? get blockReason {
    final raw = _loginState()['multiplayerSessionBlockReason'];
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static void markStartupPending() {
    StateManager().updateModuleState(_loginModule, {
      'sessionStartupPending': true,
      'multiplayerSessionReady': false,
      'multiplayerSessionChecking': true,
      'multiplayerSessionBlockReason': null,
    });
  }

  static void markStartupCompleteNotLoggedIn() {
    StateManager().updateModuleState(_loginModule, {
      'sessionStartupPending': false,
      'multiplayerSessionReady': false,
      'multiplayerSessionChecking': false,
      'multiplayerSessionBlockReason': null,
    });
  }

  static void markStartupFailed({required String message}) {
    StateManager().updateModuleState(_loginModule, {
      'sessionStartupPending': false,
      'multiplayerSessionReady': false,
      'multiplayerSessionChecking': false,
      'multiplayerSessionBlockReason': message,
    });
  }

  static void _markReady() {
    StateManager().updateModuleState(_loginModule, {
      'sessionStartupPending': false,
      'multiplayerSessionReady': true,
      'multiplayerSessionChecking': false,
      'multiplayerSessionBlockReason': null,
    });
  }

  static void _markBlocked(String message) {
    StateManager().updateModuleState(_loginModule, {
      'sessionStartupPending': false,
      'multiplayerSessionReady': false,
      'multiplayerSessionChecking': false,
      'multiplayerSessionBlockReason': message,
    });
  }

  static void _markChecking() {
    StateManager().updateModuleState(_loginModule, {
      'multiplayerSessionChecking': true,
    });
  }

  static void markNotReady({String? reason}) {
    StateManager().updateModuleState(_loginModule, {
      'multiplayerSessionReady': false,
      if (reason != null && reason.trim().isNotEmpty)
        'multiplayerSessionBlockReason': reason.trim(),
    });
  }

  /// Called from [AppManager] after [AuthManager.validateSessionOnStartup] returns logged in.
  static Future<bool> completeStartupReadiness() async {
    return refreshReadiness(triggerSessionExpiredOnAuthFailure: true);
  }

  /// Re-validates JWT + WS auth (login success, lobby entry, before multiplayer actions).
  static Future<bool> refreshReadiness({
    bool triggerSessionExpiredOnAuthFailure = false,
  }) async {
    if (!isLoggedIn) {
      _markBlocked('Please log in to play multiplayer.');
      return false;
    }

    _markChecking();

    final hasValidJwt = await AuthManager().hasValidToken();
    if (!hasValidJwt) {
      const message = 'Session expired. Please log in again.';
      _markBlocked(message);
      if (triggerSessionExpiredOnAuthFailure) {
        HooksManager().triggerHookWithData('auth_required', {
          'status': 'token_expired',
          'reason': 'token_expired',
          'message': message,
        });
      }
      return false;
    }

    final wsReady = await DutchGameHelpers.ensureWebSocketReady();
    if (!wsReady) {
      _markBlocked(
        'Not connected to the game server yet. Check your network, then try again.',
      );
      return false;
    }

    final wsState =
        StateManager().getModuleState<Map<String, dynamic>>('websocket') ?? {};
    if (wsState['is_authenticated'] != true) {
      _markBlocked(
        'Could not verify your session with the game server. Please try again.',
      );
      return false;
    }

    _markReady();
    return true;
  }

  /// Block Quick join / create room until startup + WS auth are both OK.
  static Future<bool> ensureReadyForMultiplayerAction() async {
    if (!isLoggedIn) {
      DutchGameHelpers.navigateToAccountScreen(
        'ws_auth_required',
        'Please log in to connect to the game server.',
      );
      return false;
    }

    if (isReady) {
      final wsState =
          StateManager().getModuleState<Map<String, dynamic>>('websocket') ??
              {};
      if (wsState['is_authenticated'] == true) {
        return true;
      }
    }

    if (isStartupPending || isChecking) {
      return refreshReadiness(triggerSessionExpiredOnAuthFailure: true);
    }

    if (isReady) {
      return true;
    }

    return refreshReadiness(triggerSessionExpiredOnAuthFailure: true);
  }
}
