import 'dart:async';

import '../../dutch_game/backend_core/dutch_game_main.dart';
import '../backend_core/services/game_registry.dart';
import '../backend_core/services/game_state_store.dart';
import '../utils/platform/practice/stubs/websocket_server_stub.dart';
import '../utils/platform/practice/stubs/room_manager_stub.dart';
import '../../dutch_game/managers/dutch_event_manager.dart';


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
    
  }

  /// Handle a game event (called from event emitter in practice mode)
  Future<void> handleEvent(String event, Map<String, dynamic> data) async {
    if (!_initialized) {
      await initialize();
    }

    // Ensure we have a session/room context (required for coordinator.handle)
    if (_currentSessionId == null || _currentRoomId == null) {
      
      throw StateError(
        'PracticeModeBridge: No active practice session. '
        'Start Match may have been pressed after clearing or without starting practice from lobby.',
      );
    }

    try {
      
      // Route event to coordinator
      await _gameModule.coordinator.handle(_currentSessionId!, event, data);
      
    } catch (e) {
      
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

    
    
    // Create a practice room
    _currentRoomId = _roomManager.createRoom(
      _currentSessionId!,
      userId,
      maxSize: maxPlayers ?? 4,
      minPlayers: minPlayers ?? 2,
      gameType: gameType ?? 'practice',
      permission: 'private',
    );
    
    

    // Trigger room_created hook through hooksManager (matches backend behavior)
    
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
    

    // Trigger room_joined hook through hooksManager (matches backend behavior)
    
    _hooksManager.triggerHook('room_joined', data: {
      'room_id': _currentRoomId,
      'user_id': userId,
      'session_id': _currentSessionId,
      'owner_id': userId,
      'current_size': 1,
    });
    

    
    return _currentRoomId!;
  }

  /// End the current practice session
  void endPracticeSession() {
    try {
      final roomIdToDispose = _currentRoomId;
      if (roomIdToDispose != null) {
        
        try {
          _registry.dispose(roomIdToDispose);
        } catch (e) {
          
        }
        try {
          _store.clear(roomIdToDispose);
        } catch (e) {
          
        }
        try {
          _roomManager.closeRoom(roomIdToDispose, 'practice_ended');
        } catch (e) {
          
        }
      } else {
        
      }
      _currentRoomId = null;
      _currentSessionId = null;
      _currentUserId = null;
      
    } catch (e, stackTrace) {
      
      
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
      case 'game_animation':
        _eventManager.handleGameAnimation(message);
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

