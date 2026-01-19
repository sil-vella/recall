import 'dart:io';

/// Centralized configuration system for Dart backend
/// Similar to Python's config.py pattern
/// Priority: Files > Environment > Default
class Config {
  /// Read secret from file system - checks multiple locations
  /// Priority order:
  /// 1. Kubernetes mounted secrets (/run/secrets/)
  /// 2. Local development secrets (/app/secrets/)
  /// 3. Relative path fallback (./secrets/)
  static String? _readSecretFile(String secretName) {
    final paths = [
      '/run/secrets/$secretName',      // Kubernetes secrets
      '/app/secrets/$secretName',      // Local development secrets
      './secrets/$secretName',         // Relative path fallback
    ];

    for (final path in paths) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          final content = file.readAsStringSync().trim();
          if (content.isNotEmpty) {
            return content;
          }
        }
      } catch (e) {
        // Continue to next path
        continue;
      }
    }
    return null;
  }

  /// Get configuration integer value with priority: Files > Environment > Default
  static int _getConfigInt(String envName, String fileName, int defaultValue) {
    // Try secret file first
    final fileValue = _readSecretFile(fileName);
    if (fileValue != null && fileValue != 'vault_required') {
      return int.tryParse(fileValue) ?? defaultValue;
    }

    // Try environment variable
    final envValue = Platform.environment[envName];
    if (envValue != null && envValue != 'vault_required') {
      return int.tryParse(envValue) ?? defaultValue;
    }

    // Return default value
    return defaultValue;
  }


  // ========= Random Join Configuration =========

  /// Delay in seconds before auto-starting match for random join rooms
  /// Default: 5 seconds
  /// Can be overridden via:
  /// - Environment variable: RANDOM_JOIN_DELAY_SECONDS
  /// - Secret file: random_join_delay_seconds
  static int RANDOM_JOIN_DELAY_SECONDS = _getConfigInt(
    'RANDOM_JOIN_DELAY_SECONDS',
    'random_join_delay_seconds',
    5,
  );

  /// Maximum players for random join rooms
  /// Default: 4
  /// Can be overridden via:
  /// - Environment variable: RANDOM_JOIN_MAX_PLAYERS
  /// - Secret file: random_join_max_players
  static int RANDOM_JOIN_MAX_PLAYERS = _getConfigInt(
    'RANDOM_JOIN_MAX_PLAYERS',
    'random_join_max_players',
    4,
  );

  /// Minimum players required to start a random join game
  /// Default: 2
  /// Can be overridden via:
  /// - Environment variable: RANDOM_JOIN_MIN_PLAYERS
  /// - Secret file: random_join_min_players
  static int RANDOM_JOIN_MIN_PLAYERS = _getConfigInt(
    'RANDOM_JOIN_MIN_PLAYERS',
    'random_join_min_players',
    2,
  );

  // ========= WebSocket Room Configuration =========

  /// Room TTL in seconds (time until room expires)
  /// Default: 86400 (24 hours)
  /// Can be overridden via:
  /// - Environment variable: WS_ROOM_TTL
  /// - Secret file: ws_room_ttl
  static int WS_ROOM_TTL = _getConfigInt(
    'WS_ROOM_TTL',
    'ws_room_ttl',
    86400, // 24 hours
  );

  /// Stale room cleanup age in seconds (rooms older than this are considered stale)
  /// Default: 600 (10 minutes)
  /// Can be overridden via:
  /// - Environment variable: WS_ROOM_CLEANUP_AGE
  /// - Secret file: ws_room_cleanup_age
  static int WS_ROOM_CLEANUP_AGE = _getConfigInt(
    'WS_ROOM_CLEANUP_AGE',
    'ws_room_cleanup_age',
    600, // 10 minutes
  );
}

