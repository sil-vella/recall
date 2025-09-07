import 'dart:async';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/hooks_manager.dart';
import '../utils/recall_game_helpers.dart';
import 'recall_event_listener_validator.dart';
import 'recall_event_handler_callbacks.dart';


class RecallEventManager {
  static final RecallEventManager _instance = RecallEventManager._internal();
  factory RecallEventManager() => _instance;
  RecallEventManager._internal();

  final StateManager _stateManager = StateManager();

  final StreamController<List<Map<String, dynamic>>> _roomMessagesController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _sessionMessagesController = StreamController<List<Map<String, dynamic>>>.broadcast();

  // In-memory boards (roomId -> list), session board (global for this client)
  final Map<String, List<Map<String, dynamic>>> _roomBoards = {};
  final List<Map<String, dynamic>> _sessionBoard = [];



  Stream<List<Map<String, dynamic>>> roomMessages(String roomId) {
    return _roomMessagesController.stream.where((_) => true);
  }

  Stream<List<Map<String, dynamic>>> get sessionMessages => _sessionMessagesController.stream;

  Future<bool> initialize() async {
    try {
      // Register state domains
      _stateManager.registerModuleState("recall_messages", {
        'session': <Map<String, dynamic>>[],
        'rooms': <String, List<Map<String, dynamic>>>{},
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      // Register hook callbacks for room events
      _registerHookCallbacks();

      // Register recall-specific event listeners
      _registerRecallEventListeners();

      // Recall-specific Socket.IO listeners are centralized in RecallGameCoordinator.
      // We subscribe only via WSEventManager callbacks here.
      return true;
      
    } catch (e) {
      return false;
    }
  }

  void _registerRecallEventListeners() {
    // Initialize the event listener validator
    RecallGameEventListenerValidator.instance.initialize();
  }

  // ========================================
  // PUBLIC EVENT HANDLER DELEGATES
  // ========================================

  /// Handle recall_new_player_joined event
  void handleRecallNewPlayerJoined(Map<String, dynamic> data) {
    RecallEventHandlerCallbacks.handleRecallNewPlayerJoined(data);
  }

  /// Handle recall_joined_games event
  void handleRecallJoinedGames(Map<String, dynamic> data) {
    RecallEventHandlerCallbacks.handleRecallJoinedGames(data);
  }

  /// Handle game_started event
  void handleGameStarted(Map<String, dynamic> data) {
    RecallEventHandlerCallbacks.handleGameStarted(data);
  }

  /// Handle turn_started event
  void handleTurnStarted(Map<String, dynamic> data) {
    RecallEventHandlerCallbacks.handleTurnStarted(data);
  }

  /// Handle game_state_updated event
  void handleGameStateUpdated(Map<String, dynamic> data) {
    RecallEventHandlerCallbacks.handleGameStateUpdated(data);
  }

  /// Handle game_state_partial_update event
  void handleGameStatePartialUpdate(Map<String, dynamic> data) {
    RecallEventHandlerCallbacks.handleGameStatePartialUpdate(data);
  }

  /// Handle player_state_updated event
  void handlePlayerStateUpdated(Map<String, dynamic> data) {
    RecallEventHandlerCallbacks.handlePlayerStateUpdated(data);
  }

  void _registerHookCallbacks() {
    // Register websocket_connect hook callback
    HooksManager().registerHookWithData('websocket_connect', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      
      if (status == 'connected') {
        // Update recall game connection status
        RecallGameHelpers.updateConnectionStatus(isConnected: true);
        
        _addSessionMessage(
          level: 'success',
          title: 'WebSocket Connected',
          message: 'Successfully connected to game server',
          data: data,
        );
      }
    });
    
    // Register websocket_disconnect hook callback
    HooksManager().registerHookWithData('websocket_disconnect', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      
      if (status == 'disconnected') {
        // Update recall game connection status
        RecallGameHelpers.updateConnectionStatus(isConnected: false);
        
        _addSessionMessage(
          level: 'warning',
          title: 'WebSocket Disconnected',
          message: 'Disconnected from game server',
          data: data,
        );
      }
    });
    
    // Register websocket_connect_error hook callback
    HooksManager().registerHookWithData('websocket_connect_error', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      
      if (status == 'error') {
        // Update recall game connection status
        RecallGameHelpers.updateConnectionStatus(isConnected: false);
        
        _addSessionMessage(
          level: 'error',
          title: 'WebSocket Connection Error',
          message: 'Failed to connect to game server',
          data: data,
        );
      }
    });
    
    // Register room_creation hook callback
    HooksManager().registerHookWithData('room_creation', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      final roomId = data['room_id']?.toString() ?? '';
      final isOwner = data['is_owner'] == true;
      
      switch (status) {
        case 'success':
          // Update state for successful room creation
          final roomData = data['room_data'] ?? {};
          final maxPlayers = roomData['max_players'] ?? 4; // Use actual value from backend
          final minPlayers = roomData['min_players'] ?? 2; // Use actual value from backend
          
          RecallGameHelpers.updateUIState({
            'currentRoomId': roomId,
            'isRoomOwner': isOwner,
            'isInRoom': true,
            'gamePhase': 'waiting',
            'gameStatus': 'inactive',
            'isGameActive': false,
            'playerCount': 1, // Room creator is first player
            'currentSize': 1,
            'maxSize': maxPlayers, // Use actual max_players from backend
            'minSize': minPlayers, // Use actual min_players from backend
          });
          
          _addSessionMessage(
            level: 'success',
            title: 'Room Created',
            message: 'Successfully created room: $roomId',
            data: data,
          );
          break;
          
        case 'created':
          // Update state for room created event (this contains the full room data)
          final roomData = data['room_data'] ?? {};
          final maxPlayers = roomData['max_players'] ?? 4; // Use actual value from backend
          final minPlayers = roomData['min_players'] ?? 2; // Use actual value from backend
          
          RecallGameHelpers.updateUIState({
            'currentRoomId': roomId,
            'isInRoom': true,
            'gamePhase': 'waiting',
            'gameStatus': 'inactive',
            'isGameActive': false,
            'maxSize': maxPlayers, // Use actual max_players from backend
            'minSize': minPlayers, // Use actual min_players from backend
          });
          
          _addSessionMessage(
            level: 'info',
            title: 'Room Created',
            message: 'Room created: $roomId',
            data: data,
          );
          break;
          
        case 'error':
          // Update state for room creation error
          RecallGameHelpers.updateUIState({
            'currentRoomId': '',
            'isRoomOwner': false,
            'isInRoom': false,
            'lastError': data['error']?.toString() ?? 'Room creation failed',
          });
          
          final error = data['error']?.toString() ?? 'Unknown error';
          final details = data['details']?.toString() ?? '';
          _addSessionMessage(
            level: 'error',
            title: 'Room Creation Failed',
            message: '$error${details.isNotEmpty ? ': $details' : ''}',
            data: data,
          );
          break;
          
        default:
          _addSessionMessage(
            level: 'info',
            title: 'Room Event',
            message: 'Room event: $status',
            data: data,
          );
          break;
      }
    });
    
    // Register websocket_user_joined_rooms hook callback
    HooksManager().registerHookWithData('websocket_user_joined_rooms', (data) {
      
      // final status = data['status']?.toString() ?? 'unknown';
      // final rooms = data['rooms'] as List<dynamic>? ?? [];
      final totalRooms = data['total_rooms'] ?? 0;
            
              // Update recall game state to reflect the current room membership
        // When user leaves a room, total_rooms will be 0, so we should clear the joined games
        if (totalRooms == 0) {
          // User is not in any rooms, clear the joined games state
          RecallGameHelpers.updateUIState({
            'joinedGames': <Map<String, dynamic>>[],
            'totalJoinedGames': 0,
            'joinedGamesTimestamp': DateTime.now().toIso8601String(),
            'currentRoomId': '',
            'isInRoom': false,
            'lastUpdated': DateTime.now().toIso8601String(),
          });
        
      } else {
        // User is still in some rooms, but we need to update the joined games
        // This will be handled by the recall_joined_games event when it's sent
      }
    });
    
  }


  // void _addRoomMessage(String roomId, {required String? level, required String? title, required String? message, Map<String, dynamic>? data}) {
  //   final entry = _entry(level, title, message, data);
  //   final list = _roomBoards.putIfAbsent(roomId, () => <Map<String, dynamic>>[]);
  //   list.add(entry);
  //   if (list.length > 200) list.removeAt(0);
  //   _emitState();
  // }

  void _addSessionMessage({required String? level, required String? title, required String? message, Map<String, dynamic>? data}) {
    final entry = _entry(level, title, message, data);
    _sessionBoard.add(entry);
    if (_sessionBoard.length > 200) _sessionBoard.removeAt(0);
    _emitState();
  }

  Map<String, dynamic> _entry(String? level, String? title, String? message, Map<String, dynamic>? data) {
    return {
      'level': (level ?? 'info'),
      'title': title ?? '',
      'message': message ?? '',
      'data': data ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  void _emitState() {
    // Push to StateManager using validated state updater
    final roomsCopy = <String, List<Map<String, dynamic>>>{};
    _roomBoards.forEach((k, v) => roomsCopy[k] = List<Map<String, dynamic>>.from(v));
    
    RecallGameHelpers.updateUIState({
      'messages': {
        'session': List<Map<String, dynamic>>.from(_sessionBoard),
        'rooms': roomsCopy,
      },
    });
  }

  List<Map<String, dynamic>> getSessionBoard() => List<Map<String, dynamic>>.from(_sessionBoard);
  List<Map<String, dynamic>> getRoomBoard(String roomId) => List<Map<String, dynamic>>.from(_roomBoards[roomId] ?? const []);

  void dispose() {
    _roomMessagesController.close();
    _sessionMessagesController.close();
  }
}