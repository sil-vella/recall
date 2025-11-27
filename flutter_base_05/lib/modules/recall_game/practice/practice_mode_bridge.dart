import 'dart:async';
import 'package:recall/tools/logging/logger.dart';

import '../backend_core/recall_game_main.dart';
import '../backend_core/coordinator/game_event_coordinator.dart';
import '../backend_core/services/game_registry.dart';
import '../backend_core/services/game_state_store.dart';
import '../backend_core/practice/stubs/websocket_server_stub.dart';
import '../backend_core/practice/stubs/room_manager_stub.dart';
import '../managers/recall_event_manager.dart';

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
  late final RecallGameModule _gameModule;
  final GameRegistry _registry = GameRegistry.instance;
  final GameStateStore _store = GameStateStore.instance;
  final RecallEventManager _eventManager = RecallEventManager();

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
      onSendToSession: _handleSendToSession,
      onBroadcastToRoom: _handleBroadcastToRoom,
    );

    // Create a stub HooksManager (minimal implementation for practice mode)
    final hooksManager = _HooksManagerStub();

    // Initialize game module with stubs
    _gameModule = RecallGameModule(_server, _roomManager, hooksManager);

    _initialized = true;
    _logger.info('PracticeModeBridge: Initialized', isOn: false);
  }

  /// Handle a game event (called from event emitter in practice mode)
  Future<void> handleEvent(String event, Map<String, dynamic> data) async {
    if (!_initialized) {
      await initialize();
    }

    // Ensure we have a session/room context
    if (_currentSessionId == null || _currentRoomId == null) {
      _logger.warning('PracticeModeBridge: No active session/room for event $event', isOn: false);
      return;
    }

    try {
      // Route event to coordinator
      await _gameModule.coordinator.handle(_currentSessionId!, event, data);
    } catch (e) {
      _logger.error('PracticeModeBridge: Error handling event $event: $e', isOn: false);
    }
  }

  /// Start a practice game session
  Future<String> startPracticeSession({
    required String userId,
    int? maxPlayers,
    int? minPlayers,
    String? gameType,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    // Create a practice session ID (same as userId for simplicity)
    _currentSessionId = 'practice_session_$userId';
    _currentUserId = userId;

    // Create a practice room
    _currentRoomId = _roomManager.createRoom(
      _currentSessionId!,
      userId,
      maxSize: maxPlayers ?? 4,
      minPlayers: minPlayers ?? 2,
      gameType: gameType ?? 'practice',
      permission: 'private',
    );

    // Trigger room_created hook manually (since we're using stubs)
    await _gameModule.coordinator.handle(_currentSessionId!, 'room_created', {
      'room_id': _currentRoomId,
      'owner_id': userId,
      'max_size': maxPlayers ?? 4,
      'min_players': minPlayers ?? 2,
      'game_type': gameType ?? 'practice',
    });

    // Trigger room_joined hook
    await _gameModule.coordinator.handle(_currentSessionId!, 'room_joined', {
      'room_id': _currentRoomId,
      'user_id': userId,
      'session_id': _currentSessionId,
    });

    _logger.info('PracticeModeBridge: Started practice session in room $_currentRoomId', isOn: false);
    return _currentRoomId!;
  }

  /// End the current practice session
  void endPracticeSession() {
    if (_currentRoomId != null) {
      _registry.dispose(_currentRoomId!);
      _store.clear(_currentRoomId!);
      _roomManager.closeRoom(_currentRoomId!, 'practice_ended');
    }
    _currentRoomId = null;
    _currentSessionId = null;
    _currentUserId = null;
    _logger.info('PracticeModeBridge: Ended practice session', isOn: false);
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
        _logger.info('PracticeModeBridge: Unhandled event: $event', isOn: false);
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

