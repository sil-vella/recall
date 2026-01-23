import '../state_manager.dart';
import '../module_manager.dart';
import 'ws_event_handler.dart';
import 'native_websocket_adapter.dart';
import '../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = false; // Enabled for final round debugging and game creation loops

/// WebSocket Event Listener
/// Centralized Socket.IO event listener registration and management
class WSEventListener {
  final NativeWebSocketAdapter? _socket;
  final WSEventHandler _eventHandler;
  final StateManager _stateManager;
  final ModuleManager _moduleManager;
  static final Logger _logger = Logger();

  WSEventListener({
    required NativeWebSocketAdapter? socket,
    required WSEventHandler eventHandler,
    required StateManager stateManager,
    required ModuleManager moduleManager,
  })  : _socket = socket,
        _eventHandler = eventHandler,
        _stateManager = stateManager,
        _moduleManager = moduleManager;

  /// Register all Socket.IO event listeners
  void registerAllListeners() {
    if (LOGGING_SWITCH) {
      _logger.info('🎧 Registering all WebSocket event listeners');
    }
    
    // Connection events
    _registerConnectListener();
    _registerDisconnectListener();
    _registerConnectErrorListener();

    // Session events
    _registerSessionDataListener();

    // Room events
    _registerRoomJoinedListener();
    _registerJoinRoomSuccessListener();
    _registerAlreadyJoinedListener();
    _registerJoinRoomErrorListener();
    _registerCreateRoomSuccessListener();
    _registerRoomCreatedListener();
    _registerCreateRoomErrorListener();
    _registerLeaveRoomSuccessListener();
    _registerLeaveRoomErrorListener();
    _registerRoomClosedListener();
    _registerUserJoinedRoomsListener();
    _registerRoomsListListener();

    // Message events
    _registerMessageListener();

    // Error events
    _registerErrorListener();
    
    // Game event acknowledgment listeners
    _registerGameEventAcknowledgmentListeners();
    
    // Authentication events
    _registerAuthenticationListeners();
    
    if (LOGGING_SWITCH) {
      _logger.info('✅ All WebSocket event listeners registered successfully');
    }
  }

  /// Register connection event listener
  void _registerConnectListener() {
    if (LOGGING_SWITCH) {
      _logger.debug('🎧 Registering connect event listener');
    }
    _socket?.on('connected', (data) {
      if (LOGGING_SWITCH) {
        _logger.debug('📡 Connected event received');
      }
      _eventHandler.handleConnect(data);
    });
  }

  /// Register disconnect event listener
  void _registerDisconnectListener() {
    if (LOGGING_SWITCH) {
      _logger.debug('🎧 Registering disconnect event listener');
    }
    _socket?.on('disconnect', (data) {
      if (LOGGING_SWITCH) {
        _logger.debug('📡 Disconnect event received');
      }
      _eventHandler.handleDisconnect(data);
    });
  }

  /// Register connection error listener
  void _registerConnectErrorListener() {
    _socket?.on('connect_error', (data) {
      _eventHandler.handleConnectError(data);
    });
  }

  /// Register session data listener
  void _registerSessionDataListener() {
    _socket?.on('session_data', (data) {
      _eventHandler.handleSessionData(data);
    });
  }

  /// Register room joined listener
  void _registerRoomJoinedListener() {
    _socket?.on('room_joined', (data) {
      _eventHandler.handleRoomJoined(data);
    });
  }

  /// Register join room success listener
  void _registerJoinRoomSuccessListener() {
    if (LOGGING_SWITCH) {
      _logger.debug('🎧 Registering join_room_success event listener');
    }
    _socket?.on('join_room_success', (data) {
      if (LOGGING_SWITCH) {
        _logger.info('📡 join_room_success event received in WSEventListener');
      }
      if (LOGGING_SWITCH) {
        _logger.debug('join_room_success data: $data');
      }
      _eventHandler.handleJoinRoomSuccess(data);
    });
  }

  /// Register already joined listener
  void _registerAlreadyJoinedListener() {
    _socket?.on('already_joined', (data) {
      _eventHandler.handleAlreadyJoined(data);
    });
  }

  /// Register join room error listener
  void _registerJoinRoomErrorListener() {
    _socket?.on('join_room_error', (data) {
      _eventHandler.handleJoinRoomError(data);
    });
  }

  /// Register create room success listener
  void _registerCreateRoomSuccessListener() {
    _socket?.on('create_room_success', (data) {
      _eventHandler.handleCreateRoomSuccess(data);
    });
  }

  /// Register room created listener
  void _registerRoomCreatedListener() {
    _socket?.on('room_created', (data) {
      _eventHandler.handleRoomCreated(data);
    });
  }

  /// Register create room error listener
  void _registerCreateRoomErrorListener() {
    _socket?.on('create_room_error', (data) {
      _eventHandler.handleCreateRoomError(data);
    });
  }

  /// Register leave room success listener
  void _registerLeaveRoomSuccessListener() {
    _socket?.on('leave_room_success', (data) {
      _eventHandler.handleLeaveRoomSuccess(data);
    });
  }

  /// Register leave room error listener
  void _registerLeaveRoomErrorListener() {
    _socket?.on('leave_room_error', (data) {
      _eventHandler.handleLeaveRoomError(data);
    });
  }

  /// Register room closed event listener
  void _registerRoomClosedListener() {
    _socket?.on('room_closed', (data) {
      _eventHandler.handleRoomClosed(data);
    });
  }

  /// Register message listener
  void _registerMessageListener() {
    _socket?.on('message', (data) {
      _eventHandler.handleMessage(data);
    });
  }

  /// Register error listener
  void _registerErrorListener() {
    _socket?.on('error', (data) {
      _eventHandler.handleError(data);
    });
  }

  /// Register user joined rooms listener
  void _registerUserJoinedRoomsListener() {
    _socket?.on('user_joined_rooms', (data) {
      _eventHandler.handleUserJoinedRooms(data);
    });
  }

  /// Register a custom event listener
  void registerCustomListener(String eventName, Function(dynamic) handler) {
    _socket?.on(eventName, (data) {
      try {
        handler(data);
      } catch (e) {
        // Handler error
      }
    });
  }

  /// Register rooms list listener
  void _registerRoomsListListener() {
    if (LOGGING_SWITCH) {
      _logger.debug('🎧 Registering rooms_list event listener');
    }
    _socket?.on('rooms_list', (data) {
      if (LOGGING_SWITCH) {
        _logger.debug('📡 rooms_list event received');
      }
      _eventHandler.handleRoomsList(data);
    });
  }

  /// Unregister all listeners
  void unregisterAllListeners() {
    _socket?.off('connect');
    _socket?.off('disconnect');
    _socket?.off('connect_error');
    _socket?.off('session_data');
    _socket?.off('room_joined');
    _socket?.off('join_room_success');
    _socket?.off('join_room_error');
    _socket?.off('create_room_success');
    _socket?.off('room_created');
    _socket?.off('create_room_error');
    _socket?.off('leave_room_success');
    _socket?.off('leave_room_error');
    _socket?.off('room_closed');
    _socket?.off('user_joined_rooms');
    _socket?.off('rooms_list');
    _socket?.off('message');
    _socket?.off('error');
  }

  /// Unregister a specific listener
  void unregisterListener(String eventName) {
    _socket?.off(eventName);
  }
  
  /// Register game event acknowledgment listeners
  void _registerGameEventAcknowledgmentListeners() {
    if (LOGGING_SWITCH) {
      _logger.debug('🎧 Registering game event acknowledgment listeners');
    }
    
    final gameEvents = [
      'start_match', 'draw_card', 'play_card', 'discard_card',
      'take_from_discard', 'call_dutch', 'same_rank_play',
      'jack_swap', 'queen_peek', 'completed_initial_peek'
    ];
    
    for (final event in gameEvents) {
      _socket?.on('${event}_acknowledged', (data) {
        if (LOGGING_SWITCH) {
          _logger.info('✅ Acknowledged: $event');
        }
        _eventHandler.handleCustomEvent(event, data);
      });
    }
  }
  
  /// Register authentication event listeners
  void _registerAuthenticationListeners() {
    if (LOGGING_SWITCH) {
      _logger.debug('🎧 Registering authentication event listeners');
    }
    
    _socket?.on('authenticated', (data) {
      if (LOGGING_SWITCH) {
        _logger.info('🔐 Authentication successful');
      }
      _eventHandler.handleAuthenticationSuccess(data);
    });
    
    _socket?.on('authentication_failed', (data) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Authentication failed');
      }
      _eventHandler.handleAuthenticationFailed(data);
    });
    
    _socket?.on('authentication_error', (data) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Authentication error');
      }
      _eventHandler.handleAuthenticationError(data);
    });
  }
} 