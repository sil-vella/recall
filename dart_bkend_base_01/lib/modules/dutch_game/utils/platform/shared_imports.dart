// Common Dart core imports
export 'dart:math';
export 'dart:async';
export 'dart:io';

// Backend server and manager types (export actual classes for backend)
export '../../../../server/websocket_server.dart';
export '../../../../server/room_manager.dart';
export '../../../../managers/hooks_manager.dart';

// Note: Platform-specific imports (like computer_player_config_parser.dart) 
// should be imported directly in files that need them, not via shared_imports.dart

// Platform-specific config paths (Dart backend)
const String DECK_CONFIG_PATH = 'assets/deck_config.yaml';
const String COMPUTER_PLAYER_CONFIG_PATH = 'assets/computer_player_config.yaml';
