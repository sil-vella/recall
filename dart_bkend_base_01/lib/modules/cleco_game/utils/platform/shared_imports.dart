// Common Dart core imports
export 'dart:math';
export 'dart:async';
export 'dart:io';

// Backend-specific logger
export '../../../../utils/server_logger.dart';

// Backend server and manager types (export actual classes for backend)
export '../../../../server/websocket_server.dart' hide LOGGING_SWITCH;
export '../../../../server/room_manager.dart';
export '../../../../managers/hooks_manager.dart' hide LOGGING_SWITCH;

// Note: Platform-specific imports (like computer_player_config_parser.dart) 
// should be imported directly in files that need them, not via shared_imports.dart

