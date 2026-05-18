/// User-facing copy for session/auth navigation (LoginModule + AccountScreen).
class AuthSessionMessages {
  AuthSessionMessages._();

  static String forHook({
    required String reason,
    String? hookMessage,
    String? code,
  }) {
    final trimmed = hookMessage?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    if (code == 'SESSION_SUPERSEDED') {
      return 'This account was signed in on another device. Please log in again.';
    }
    switch (reason) {
      case 'api_unauthorized':
        return 'Your session is no longer valid. Please sign in again.';
      case 'refresh_token_expired':
        return 'Refresh token has expired. Please log in again.';
      case 'token_refresh_failed':
        return 'Token refresh failed. Please log in again.';
      case 'session_idle_expired':
        return 'Session expired due to inactivity. Please log in again.';
      case 'auth_error':
        return 'Authentication error occurred. Please log in again.';
      case 'ws_auth_required':
        return 'Please log in to connect to game server.';
      case 'ws_not_ready':
        return 'Unable to connect to game server. Please log in to continue.';
      default:
        return 'Please log in again.';
    }
  }
}
