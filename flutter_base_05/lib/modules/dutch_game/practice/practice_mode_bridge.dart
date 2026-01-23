import 'dart:async';
import 'package:dutch/tools/logging/logger.dart';

import '../../dutch_game/backend_core/dutch_game_main.dart';
import '../backend_core/services/game_registry.dart';
import '../backend_core/services/game_state_store.dart';
import '../utils/platform/practice/stubs/websocket_server_stub.dart';
import '../utils/platform/practice/stubs/room_manager_stub.dart';
import '../../dutch_game/managers/dutch_event_manager.dart';

const bool LOGGING_SWITCH = false; // Enabled for mode switching debugging

/// Practice Mode Bridge
/// 
/// Bridges the cloned backend game logic to Flutter practice mode.
/// Routes game events directly to the backend coordinator and converts
/// backend broadcasts into Flutter event manager callbacks.
class PracticeModeBridge {
  static PracticeModeBridge? _instance;
  static PracticeModeBridge get instance {
    _instance ??= PracticeModeBridge._internal();
    return _instance!;
  }

  PracticeModeBridge._internal();

  final Logger _logger = Logger();
  final RoomManagerStub _roomManager = RoomManagerStub();
  late final WebSocketServerStub _server;
  late final DutchGameModule _gameModule;
  late final _HooksManagerStub _hooksManager;
  final GameRegistry _registry = GameRegistry.instance;
  final GameStateStore _store = GameStateStore.instance;
  final DutchEventManager _eventManager = DutchEventManager();

  String? _currentRoomId;
  String? _currentSessionId;
  String? _currentUserId;

  bool _initialized = false;

  /// Initialize the practice bridge
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize event manager
    await _eventManager.initialize();

    // Create WebSocket server stub with callbacks to route to event manager
    _server = WebSocketServerStub(
      roomManager: _roomManager,
      onSendToSession: _handleSendToSession,
      onBroadcastToRoom: _handleBroadcastToRoom,
      onTriggerHook: (hookName, {data, context}) {
        // Route hooks through hooksManager
        _hooksManager.triggerHook(hookName, data: data, context: context);
      },
    );

    // Create a stub HooksManager (minimal implementation for practice mode)
    _hooksManager = _HooksManagerStub();

    // Initialize game module with stubs (this registers the hooks)
    _gameModule = DutchGameModule(_server, _roomManager, _hooksManager);

    _initialized = true;
    if (LOGGING_SWITCH) {
      _logger.info('🎮 PracticeModeBridge: Initialized with stubs');
    }
  }

  /// Handle a game event (called from event emitter in practice mode)
  Future<void> handleEvent(String event, Map<String, dynamic> data) async {
    if (!_initialized) {
      await initialize();
    }

    // Ensure we have a session/room context
    if (_currentSessionId == null || _currentRoomId == null) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️ PracticeModeBridge: No active session/room for event $event');
      }
      return;
    }

    try {
      if (LOGGING_SWITCH) {
        _logger.info('📨 PracticeModeBridge: Handling event $event for room $_currentRoomId');
      }
      // Route event to coordinator
      await _gameModule.coordinator.handle(_currentSessionId!, event, data);
      if (LOGGING_SWITCH) {
        _logger.info('✅ PracticeModeBridge: Successfully handled event $event');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ PracticeModeBridge: Error handling event $event: $e');
      }
    }
  }

  /// Start a practice game session
  Future<String> startPracticeSession({
    required String userId,
    int? maxPlayers,
    int? minPlayers,
    String? gameType,
    String? difficulty, // Practice difficulty from lobby selection
  }) async {
    if (!_initialized) {
      await initialize();
    }

    // Create a practice session ID (same as userId for simplicity)
    _currentSessionId = 'practice_session_$userId';
    _currentUserId = userId;

    if (LOGGING_SWITCH) {
      _logger.info('🏗️ PracticeModeBridge: Creating practice room for user $userId with difficulty: $difficulty');
    }
    
    // Create a practice room
    _currentRoomId = _roomManager.createRoom(
      _currentSessionId!,
      userId,
      maxSize: maxPlayers ?? 4,
      minPlayers: minPlayers ?? 2,
      gameType: gameType ?? 'practice',
      permission: 'private',
    );
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ PracticeModeBridge: Created practice room $_currentRoomId');
    }

    // Trigger room_created hook through hooksManager (matches backend behavior)
    if (LOGGING_SWITCH) {
      _logger.info('🎣 PracticeModeBridge: Triggering room_created hook for room $_currentRoomId');
    }
    _hooksManager.triggerHook('room_created', data: {
      'room_id': _currentRoomId,
      'owner_id': userId,
      'session_id': _currentSessionId, // Include session_id for player ID
      'max_size': maxPlayers ?? 4,
      'min_players': minPlayers ?? 2,
      'game_type': gameType ?? 'practice',
      'difficulty': difficulty ?? 'medium', // Pass difficulty from lobby selection
      'current_size': 1,
      'permission': 'private',
      'created_at': DateTime.now().toIso8601String(),
    });
    if (LOGGING_SWITCH) {
      _logger.info('✅ PracticeModeBridge: room_created hook completed');
    }

    // Trigger room_joined hook through hooksManager (matches backend behavior)
    if (LOGGING_SWITCH) {
      _logger.info('🎣 PracticeModeBridge: Triggering room_joined hook for user $userId');
    }
    _hooksManager.triggerHook('room_joined', data: {
      'room_id': _currentRoomId,
      'user_id': userId,
      'session_id': _currentSessionId,
      'owner_id': userId,
      'current_size': 1,
    });
    if (LOGGING_SWITCH) {
      _logger.info('✅ PracticeModeBridge: room_joined hook completed');
    }

    if (LOGGING_SWITCH) {
      _logger.info('🎮 PracticeModeBridge: Practice session started successfully in room $_currentRoomId');
    }
    return _currentRoomId!;
  }

  /// End the current practice session
  void endPracticeSession() {
    try {
      final roomIdToDispose = _currentRoomId;
      if (roomIdToDispose != null) {
        if (LOGGING_SWITCH) {
          _logger.info('🏁 PracticeModeBridge: Ending practice session for room: $roomIdToDispose');
        }
        try {
          _registry.dispose(roomIdToDispose);
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ PracticeModeBridge: Error disposing registry for $roomIdToDispose: $e');
          }
        }
        try {
          _store.clear(roomIdToDispose);
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ PracticeModeBridge: Error clearing store for $roomIdToDispose: $e');
          }
        }
        try {
          _roomManager.closeRoom(roomIdToDispose, 'practice_ended');
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ PracticeModeBridge: Error closing room $roomIdToDispose: $e');
          }
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('🏁 PracticeModeBridge: No active practice session to end');
        }
      }
      _currentRoomId = null;
      _currentSessionId = null;
      _currentUserId = null;
      if (LOGGING_SWITCH) {
        _logger.info('✅ PracticeModeBridge: Ended practice session successfully');
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ PracticeModeBridge: Error ending practice session: $e');
      }
      if (LOGGING_SWITCH) {
        _logger.error('❌ PracticeModeBridge: Stack trace:\n$stackTrace');
      }
      // Still clear state even if there was an error
      _currentRoomId = null;
      _currentSessionId = null;
      _currentUserId = null;
    }
  }

  /// Handle sendToSession from backend (routes to event manager)
  void _handleSendToSession(String sessionId, Map<String, dynamic> message) {
    final event = message['event'] as String?;
    if (event == null) return;

    // Route to appropriate event manager handler
    switch (event) {
      case 'game_state_updated':
        _eventManager.handleGameStateUpdated(message);
        break;
      case 'player_status_updated':
        _eventManager.handlePlayerStateUpdated(message);
        break;
      case 'discard_pile_updated':
        // Handle discard pile update
        break;
      case 'action_error':
        // Handle action error
        break;
      default:
        if (LOGGING_SWITCH) {
          _logger.info('ℹ️ PracticeModeBridge: Unhandled event: $event');
        }
    }
  }

  /// Handle broadcastToRoom from backend (routes to event manager)
  void _handleBroadcastToRoom(String roomId, Map<String, dynamic> message) {
    // Same as sendToSession for practice mode (single player)
    _handleSendToSession(_currentSessionId ?? 'practice_session', message);
  }

  /// Get current room ID
  String? get currentRoomId => _currentRoomId;

  /// Get current session ID
  String? get currentSessionId => _currentSessionId;
}

/// Minimal stub for HooksManager (practice mode doesn't need full hook system)
class _HooksManagerStub {
  final Map<String, List<Function>> _hooks = {};

  void registerHook(String hookName) {
    _hooks[hookName] = [];
  }

  void registerHookCallback(String hookName, Function callback, {int priority = 0}) {
    _hooks.putIfAbsent(hookName, () => []).add(callback);
  }

  void triggerHook(String hookName, {Map<String, dynamic>? data, String? context}) {
    final callbacks = _hooks[hookName];
    if (callbacks != null) {
      for (final callback in callbacks) {
        try {
          callback(data ?? {});
        } catch (e) {
          // Ignore errors in practice mode
        }
      }
    }
  }
}

