// Common Dart core imports
export 'dart:math';
export 'dart:async';
// Note: dart:io removed for Flutter compatibility

// Flutter logger (replaces backend server_logger)
export '../../../../tools/logging/logger.dart';

// Type aliases for dependency injection (allows both real and stub implementations)
// These allow the same code to work with real WebSocketServer/RoomManager or practice stubs
typedef WebSocketServer = dynamic;
typedef RoomManager = dynamic;
typedef HooksManager = dynamic;

// Note: Platform-specific imports (like computer_player_config_parser.dart) 
// should be imported directly in files that need them, not via shared_imports.dart

// Platform-specific config paths (Flutter)
const String DECK_CONFIG_PATH = 'assets/deck_config.yaml';

