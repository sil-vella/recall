import 'dart:async';
import 'package:dutch/tools/logging/logger.dart';

import '../../../core/managers/state_manager.dart';
import '../../../core/managers/hooks_manager.dart';
import '../../../core/managers/navigation_manager.dart';
import '../../dutch_game/utils/dutch_game_helpers.dart';
import '../../dutch_game/managers/dutch_event_listener_validator.dart';
import '../../dutch_game/managers/dutch_event_handler_callbacks.dart';


class DutchEventManager {
  static const bool LOGGING_SWITCH = false; // Enabled for final round debugging
  static final DutchEventManager _instance = DutchEventManager._internal();
  factory DutchEventManager() => _instance;
  DutchEventManager._internal();

  final Logger _logger = Logger();
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
      _stateManager.registerModuleState("dutch_messages", {
        'session': <Map<String, dynamic>>[],
        'rooms': <String, List<Map<String, dynamic>>>{},
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      // Register hook callbacks for room events
      _registerHookCallbacks();

      // Register dutch-specific event listeners
      _registerDutchEventListeners();

      // Dutch-specific Socket.IO listeners are centralized in DutchGameCoordinator.
      // We subscribe only via WSEventManager callbacks here.
      return true;
      
    } catch (e) {
      return false;
    }
  }

  void _registerDutchEventListeners() {
    // Initialize the event listener validator
    DutchGameEventListenerValidator.instance.initialize();
  }

  // ========================================
  // PUBLIC EVENT HANDLER DELEGATES
  // ========================================

  /// Handle dutch_new_player_joined event
  void handleDutchNewPlayerJoined(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleDutchNewPlayerJoined(data);
  }

  /// Handle dutch_joined_games event
  void handleDutchJoinedGames(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleDutchJoinedGames(data);
  }

  /// Handle game_started event
  void handleGameStarted(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleGameStarted(data);
  }

  /// Handle turn_started event
  void handleTurnStarted(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleTurnStarted(data);
  }

  /// Handle game_state_updated event
  void handleGameStateUpdated(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handleGameStateUpdated(data);
  }

  /// Handle game_state_partial_update event
  void handleGameStatePartialUpdate(Map<String, dynamic> data) {
    _logger.info("handleGameStatePartialUpdate: $data", isOn: LOGGING_SWITCH);
    DutchEventHandlerCallbacks.handleGameStatePartialUpdate(data);
  }

  /// Handle player_state_updated event
  void handlePlayerStateUpdated(Map<String, dynamic> data) {
    DutchEventHandlerCallbacks.handlePlayerStateUpdated(data);
  }


  void _registerHookCallbacks() {
    // Register websocket_connect hook callback
    HooksManager().registerHookWithData('websocket_connect', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      
      if (status == 'connected') {
        // Update dutch game connection status
        DutchGameHelpers.updateConnectionStatus(isConnected: true);
        
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
        // Update dutch game connection status
        DutchGameHelpers.updateConnectionStatus(isConnected: false);
        
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
        // Update dutch game connection status
        DutchGameHelpers.updateConnectionStatus(isConnected: false);
        
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
      final isRandomJoin = data['is_random_join'] == true;
      // For random join rooms, always set isOwner to false
      final isOwner = isRandomJoin ? false : (data['is_owner'] == true);
      
      switch (status) {
        case 'success':
          // Update state for successful room creation
          final roomData = data['room_data'] ?? {};
          final maxPlayers = roomData['max_players'] ?? 4; // Use actual value from backend
          final minPlayers = roomData['min_players'] ?? 2; // Use actual value from backend
          
          DutchGameHelpers.updateUIState({
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
          
          // Navigate to game play screen if this is a random join
          if (isRandomJoin) {
            _logger.info('🎮 Random join room created, navigating to game play screen', isOn: LOGGING_SWITCH);
            
            // Clear the random join flag
            DutchGameHelpers.updateUIState({
              'isRandomJoinInProgress': false,
            });
            
            // Use a small delay to ensure state is fully updated
            Future.delayed(const Duration(milliseconds: 300), () {
              NavigationManager().navigateTo('/dutch/game-play');
            });
          }
          break;
          
        case 'created':
          // Update state for room created event (this contains the full room data)
          final roomData = data['room_data'] ?? {};
          final maxPlayers = roomData['max_players'] ?? 4; // Use actual value from backend
          final minPlayers = roomData['min_players'] ?? 2; // Use actual value from backend
          
          DutchGameHelpers.updateUIState({
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
          DutchGameHelpers.updateUIState({
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
    
    // Register websocket_join_room hook callback (for joining existing rooms)
    HooksManager().registerHookWithData('websocket_join_room', (data) {
      try {
        _logger.info('🔍 websocket_join_room hook triggered with data: $data', isOn: LOGGING_SWITCH);
        
        final status = data['status']?.toString() ?? 'unknown';
        final roomId = data['room_id']?.toString() ?? '';
        
        _logger.info('🔍 websocket_join_room: status=$status, roomId=$roomId', isOn: LOGGING_SWITCH);
        
        // 🎯 CRITICAL: For any successful room join, set currentGameId and currentRoomId
        // This ensures player 2 (and any joining player) has the game ID set before receiving game_state_updated
        if (status == 'success' && roomId.isNotEmpty) {
          final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
          final currentGameId = dutchState['currentGameId']?.toString() ?? '';
          
          // Set currentGameId if not already set (important for player 2 joining)
          if (currentGameId != roomId) {
            _logger.info('🔍 websocket_join_room: Setting currentGameId to $roomId (was: $currentGameId)', isOn: LOGGING_SWITCH);
            DutchGameHelpers.updateUIState({
              'currentGameId': roomId,
              'currentRoomId': roomId,
              'isInRoom': true,
            });
          }
        }
        
        // Check if this is from a random join flow
        final dutchState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final isRandomJoinInProgress = dutchState['isRandomJoinInProgress'] == true;
        
        _logger.info('🔍 websocket_join_room: isRandomJoinInProgress=$isRandomJoinInProgress, dutchState keys: ${dutchState.keys.toList()}', isOn: LOGGING_SWITCH);
        
        if (status == 'success' && isRandomJoinInProgress && roomId.isNotEmpty) {
          _logger.info('🎮 Random join: joined existing room, waiting for game_state_updated before navigating', isOn: LOGGING_SWITCH);
          
          // Clear the random join flag
          DutchGameHelpers.updateUIState({
            'isRandomJoinInProgress': false,
          });
          
          // CRITICAL: Don't navigate immediately - wait for game_state_updated event
          // This ensures the game has actual player data before showing the screen
          // Navigation will be handled by handleGameStateUpdated when it receives valid game state
          _logger.info('🎮 Random join: Deferring navigation until game_state_updated is received', isOn: LOGGING_SWITCH);
        } else {
          _logger.info('🔍 websocket_join_room: Navigation skipped - status=$status, isRandomJoinInProgress=$isRandomJoinInProgress, roomId=$roomId', isOn: LOGGING_SWITCH);
        }
      } catch (e) {
        _logger.error('❌ Error in websocket_join_room hook callback: $e', isOn: LOGGING_SWITCH);
      }
    });
    
    // Register websocket_user_joined_rooms hook callback
    HooksManager().registerHookWithData('websocket_user_joined_rooms', (data) {
      
      // final status = data['status']?.toString() ?? 'unknown';
      // final rooms = data['rooms'] as List<dynamic>? ?? [];
      final totalRooms = data['total_rooms'] ?? 0;
            
              // Update dutch game state to reflect the current room membership
        // When user leaves a room, total_rooms will be 0, so we should clear the joined games
        if (totalRooms == 0) {
          // User is not in any rooms, clear the joined games state
          DutchGameHelpers.updateUIState({
            'joinedGames': <Map<String, dynamic>>[],
            'totalJoinedGames': 0,
            // Removed joinedGamesTimestamp - causes unnecessary state updates
            'currentRoomId': '',
            'isInRoom': false,
            // Removed lastUpdated - causes unnecessary state updates
          });
        
      } else {
        // User is still in some rooms, but we need to update the joined games
        // This will be handled by the dutch_joined_games event when it's sent
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
    
    DutchGameHelpers.updateUIState({
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