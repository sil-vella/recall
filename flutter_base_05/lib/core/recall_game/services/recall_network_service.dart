import 'dart:async';


import '../models/player.dart';
import '../models/game_state.dart';

// Removed notifier dependency
import '../../managers/websockets/websocket_manager.dart';
import '../../managers/state_manager.dart';
import '../../../tools/logging/logger.dart';

/// Service for handling network communication and WebSocket events
/// This extracts network logic from the manager/notifier pattern
class RecallNetworkService {
  static final _log = Logger();
  
  // No notifier; we write to StateManager
  final WebSocketManager _webSocketManager;
  
  bool _isInitialized = false;
  bool _isDisposed = false;

  RecallNetworkService({
    required WebSocketManager webSocketManager,
  }) : _webSocketManager = webSocketManager;

  /// Initialize the network service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _log.info('🌐 Initializing RecallNetworkService...');
      
      // Ensure WebSocket is connected
      if (!_webSocketManager.isConnected) {
        await _connectWebSocket();
      }
      
      _isInitialized = true;
      _log.info('✅ RecallNetworkService initialized');
      
    } catch (e) {
      _log.error('❌ Failed to initialize RecallNetworkService: $e');
      rethrow;
    }
  }

  /// Connect to WebSocket if not already connected
  Future<void> _connectWebSocket() async {
    try {
      if (!_webSocketManager.isConnected) {
        await _webSocketManager.connect();
        StateManager().updateModuleState('recall_game', {
          'isConnected': _webSocketManager.isConnected,
          'isLoading': false,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      _log.error('Failed to connect WebSocket: $e');
      StateManager().updateModuleState('recall_game', {
        'isConnected': false,
        'isLoading': false,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      rethrow;
    }
  }

  /// Refresh available rooms list
  Future<void> refreshRooms() async {
    if (!_isInitialized || _isDisposed) {
      throw Exception('Network service not ready');
    }

    try {
      _log.info('🔄 Refreshing rooms list...');
      
      // Send request to get rooms
      await _sendCustomEvent('recall_get_rooms', {});
      
    } catch (e) {
      _log.error('Failed to refresh rooms: $e');
      rethrow;
    }
  }

  /// Create a new room
  Future<bool> createRoom({
    required String roomName,
    required int maxPlayers,
    bool isPrivate = false,
  }) async {
    if (!_isInitialized || _isDisposed) {
      throw Exception('Network service not ready');
    }

    try {
      _log.info('🏠 Creating room: $roomName');
      
      final data = {
        'room_name': roomName,
        'max_players': maxPlayers,
        'is_private': isPrivate,
      };
      
      await _sendCustomEvent('recall_create_room', data);
      return true;
      
    } catch (e) {
      _log.error('Failed to create room: $e');
      return false;
    }
  }

  /// Join a room
  Future<bool> joinRoom(String roomId, {String? playerName}) async {
    if (!_isInitialized || _isDisposed) {
      throw Exception('Network service not ready');
    }

    try {
      _log.info('🚪 Joining room: $roomId');
      
      // Get player name from auth state if not provided
      final effectivePlayerName = playerName ?? _getPlayerName();
      
      final data = {
        'game_id': roomId,
        'player_name': effectivePlayerName,
        'player_type': 'human',
      };
      
      await _sendCustomEvent('recall_join_game', data);
      return true;
      
    } catch (e) {
      _log.error('Failed to join room: $e');
      return false;
    }
  }

  /// Leave current room
  Future<bool> leaveRoom() async {
    if (!_isInitialized || _isDisposed) {
      throw Exception('Network service not ready');
    }

    try {
      final roomId = StateManager().getModuleState<Map<String, dynamic>>('recall_game')?['currentRoomId'] as String?;
      if (roomId == null) {
        _log.warning('No current room to leave');
        return true;
      }
      
      _log.info('🚪 Leaving room: $roomId');
      
      final data = {'game_id': roomId};
      await _sendCustomEvent('recall_leave_game', data);
      return true;
      
    } catch (e) {
      _log.error('Failed to leave room: $e');
      return false;
    }
  }

  /// Start a match
  Future<bool> startMatch() async {
    if (!_isInitialized || _isDisposed) {
      throw Exception('Network service not ready');
    }

    try {
      final roomId = StateManager().getModuleState<Map<String, dynamic>>('recall_game')?['currentRoomId'] as String?;
      if (roomId == null) {
        throw Exception('No current room');
      }
      
      _log.info('🎮 Starting match in room: $roomId');
      
      final data = {
        'game_id': roomId,
        'room_id': roomId,
      };
      
      await _sendCustomEvent('recall_start_match', data);
      return true;
      
    } catch (e) {
      _log.error('Failed to start match: $e');
      return false;
    }
  }

  /// Send custom event to backend
  Future<void> _sendCustomEvent(String eventType, Map<String, dynamic> data) async {
    try {
      await _webSocketManager.sendCustomEvent(eventType, data);
      _log.debug('📤 Sent event: $eventType');
    } catch (e) {
      _log.error('Failed to send event $eventType: $e');
      rethrow;
    }
  }

  /// Get player name from auth state
  String _getPlayerName() {
    try {
      final stateManager = StateManager();
      final authState = stateManager.getModuleState<Map<String, dynamic>>('auth') ?? {};
      final user = authState['user'] as Map<String, dynamic>?;
      return user?['name']?.toString() ?? 'Player';
    } catch (e) {
      _log.warning('Failed to get player name from auth state: $e');
      return 'Player';
    }
  }

  /// Handle Recall game events from WebSocket
  void handleRecallGameEvent(Map<String, dynamic> data) {
    try {
      final eventType = data['type'] as String?;
      if (eventType == null) return;
      
      _log.debug('📥 Handling event: $eventType');
      
      switch (eventType) {
        case 'recall_rooms_list':
          _handleRoomsList(data);
          break;
        case 'recall_room_created':
          _handleRoomCreated(data);
          break;
        case 'recall_game_joined':
        case 'game_joined':
          _handleGameJoined(data);
          break;
        case 'recall_game_left':
        case 'game_left':
          _handleGameLeft(data);
          break;
        case 'recall_player_joined':
        case 'player_joined':
          _handlePlayerJoined(data);
          break;
        case 'recall_player_left':
        case 'player_left':
          _handlePlayerLeft(data);
          break;
        case 'recall_game_started':
        case 'game_started':
          _handleGameStarted(data);
          break;
        case 'recall_game_ended':
        case 'game_ended':
          _handleGameEnded(data);
          break;
        case 'recall_turn_changed':
        case 'turn_changed':
          _handleTurnChanged(data);
          break;
        case 'recall_card_played':
        case 'card_played':
          _handleCardPlayed(data);
          break;
        case 'recall_card_drawn':
        case 'card_drawn':
          _handleCardDrawn(data);
          break;
        case 'recall_game_state_update':
        case 'game_state_update':
          _handleGameStateUpdate(data);
          break;
        case 'recall_error':
          _handleError(data);
          break;
        default:
          _log.debug('Unhandled event type: $eventType');
      }
      
    } catch (e) {
      _log.error('Error handling Recall game event: $e');
    }
  }

  /// Handle rooms list update
  void _handleRoomsList(Map<String, dynamic> data) {
    try {
      final roomsData = data['rooms'] as List<dynamic>?;
      if (roomsData == null) return;
      
      final rooms = roomsData
          .map((r) => r as Map<String, dynamic>)
          .toList();
      final sm = StateManager();
      final current = sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      sm.updateModuleState('recall_game', {
        ...current,
        'rooms': rooms,
        'isLoading': false,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      _log.info('📋 Updated rooms list: ${rooms.length} rooms');
      
    } catch (e) {
      _log.error('Failed to handle rooms list: $e');
    }
  }

  /// Handle room created event
  void _handleRoomCreated(Map<String, dynamic> data) {
    try {
      final roomData = data['room'] as Map<String, dynamic>?;
      if (roomData != null) {
        final room = roomData;
        final sm = StateManager();
        final current = sm.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        sm.updateModuleState('recall_game', {
          ...current,
          'currentRoom': room,
          'currentRoomId': room['id'],
          'isRoomOwner': true,
          'gamePhase': GamePhase.waiting.name,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        _log.info('🏠 Room created and joined: ${room['name']}');
      }
      
      StateManager().updateModuleState('recall_game', {'isLoading': false, 'lastUpdated': DateTime.now().toIso8601String()});
      
    } catch (e) {
      _log.error('Failed to handle room created: $e');
    }
  }

  /// Handle game joined event
  void _handleGameJoined(Map<String, dynamic> data) {
    try {
      final gameId = data['game_id'] as String?;
      final playerId = data['player_id'] as String?;
      final isOwner = data['is_owner'] as bool? ?? false;
      
      if (gameId != null) {
        // Update room info if available
        final roomData = data['room'] as Map<String, dynamic>?;
        if (roomData != null) {
          final room = roomData;
          final sm1 = StateManager();
          final current1 = sm1.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
          sm1.updateModuleState('recall_game', {
            ...current1,
            'currentRoom': room,
            'currentRoomId': room['id'],
            'lastUpdated': DateTime.now().toIso8601String(),
          });
        } else {
          // Create minimal room info
          final room = {
            'id': gameId,
            'name': 'Room $gameId',
            'playerCount': 1,
            'maxPlayers': 4,
            'createdAt': DateTime.now().toIso8601String(),
          };
          final sm2 = StateManager();
          final current2 = sm2.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
          sm2.updateModuleState('recall_game', {
            ...current2,
            'currentRoom': room,
            'currentRoomId': room['id'],
            'lastUpdated': DateTime.now().toIso8601String(),
          });
        }
        
        final sm3 = StateManager();
        final current3 = sm3.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        sm3.updateModuleState('recall_game', {
          ...current3,
          'myPlayerId': playerId,
          'isRoomOwner': isOwner,
          'gamePhase': GamePhase.waiting.name,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        _log.info('🚪 Joined game: $gameId as $playerId');
      }
      
      // Update players if provided
      _handlePlayersUpdate(data);
      StateManager().updateModuleState('recall_game', {'isLoading': false, 'lastUpdated': DateTime.now().toIso8601String()});
      
    } catch (e) {
      _log.error('Failed to handle game joined: $e');
    }
  }

  /// Handle game left event
  void _handleGameLeft(Map<String, dynamic> data) {
    try {
      final sm4 = StateManager();
      final current4 = sm4.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      sm4.updateModuleState('recall_game', {
        ...current4,
        'currentRoom': null,
        'currentRoomId': '',
        'isRoomOwner': false,
        'players': <Map<String, dynamic>>[],
        'myHand': <Map<String, dynamic>>[],
        'playerHands': <String, dynamic>{},
        'myPlayerId': null,
        'gamePhase': GamePhase.waiting.name,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      _log.info('🚪 Left game');
      
    } catch (e) {
      _log.error('Failed to handle game left: $e');
    }
  }

  /// Handle player joined event
  void _handlePlayerJoined(Map<String, dynamic> data) {
    try {
      _handlePlayersUpdate(data);
      
      final playerName = data['player_name'] as String?;
      if (playerName != null) {
        _log.info('👤 Player joined: $playerName');
      }
      
    } catch (e) {
      _log.error('Failed to handle player joined: $e');
    }
  }

  /// Handle player left event
  void _handlePlayerLeft(Map<String, dynamic> data) {
    try {
      _handlePlayersUpdate(data);
      
      final playerName = data['player_name'] as String?;
      if (playerName != null) {
        _log.info('👤 Player left: $playerName');
      }
      
    } catch (e) {
      _log.error('Failed to handle player left: $e');
    }
  }

  /// Handle game started event
  void _handleGameStarted(Map<String, dynamic> data) {
    try {
      StateManager().updateModuleState('recall_game', {'gamePhase': GamePhase.playing.name, 'lastUpdated': DateTime.now().toIso8601String()});
      
      // Handle initial game state
      _handleGameStateUpdate(data);
      
      _log.info('🎮 Game started!');
      
    } catch (e) {
      _log.error('Failed to handle game started: $e');
    }
  }

  /// Handle game ended event
  void _handleGameEnded(Map<String, dynamic> data) {
    try {
      StateManager().updateModuleState('recall_game', {'gamePhase': GamePhase.finished.name, 'lastUpdated': DateTime.now().toIso8601String()});
      
      final winner = data['winner'] as String?;
      if (winner != null) {
        _log.info('🏁 Game ended! Winner: $winner');
      } else {
        _log.info('🏁 Game ended');
      }
      
    } catch (e) {
      _log.error('Failed to handle game ended: $e');
    }
  }

  /// Handle turn changed event
  void _handleTurnChanged(Map<String, dynamic> data) {
    try {
      final currentTurn = data['current_turn'] as Map<String, dynamic>?;
      if (currentTurn != null) {
        final sm5 = StateManager();
        final current5 = sm5.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        sm5.updateModuleState('recall_game', {
          ...current5,
          'currentTurnIndex': currentTurn['index'] as int? ?? 0,
          'currentTurnPlayerId': currentTurn['player_id'] as String?,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }
      
      // Update game state if provided
      _handleGameStateUpdate(data);
      
      _log.debug('🔄 Turn changed');
      
    } catch (e) {
      _log.error('Failed to handle turn changed: $e');
    }
  }

  /// Handle card played event
  void _handleCardPlayed(Map<String, dynamic> data) {
    try {
      // Delegate to game service for business logic
      // business logic moved out
      
    } catch (e) {
      _log.error('Failed to handle card played: $e');
    }
  }

  /// Handle card drawn event
  void _handleCardDrawn(Map<String, dynamic> data) {
    try {
      // Delegate to game service for business logic
      // business logic moved out
      
    } catch (e) {
      _log.error('Failed to handle card drawn: $e');
    }
  }

  /// Handle game state update
  void _handleGameStateUpdate(Map<String, dynamic> data) {
    try {
      // Delegate to game service for business logic
      // business logic moved out
      
    } catch (e) {
      _log.error('Failed to handle game state update: $e');
    }
  }

  /// Handle players update (common logic for join/leave events)
  void _handlePlayersUpdate(Map<String, dynamic> data) {
    try {
      final playersData = data['players'] as List<dynamic>?;
      if (playersData != null) {
        final players = playersData
            .map((p) => Player.fromJson(p as Map<String, dynamic>).toJson())
            .toList();
        final sm6 = StateManager();
        final current6 = sm6.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        sm6.updateModuleState('recall_game', {
          ...current6,
          'players': players,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }
      
      // Update current room player count
      final recall = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentRoom = recall['currentRoom'] as Map<String, dynamic>?;
      if (currentRoom != null && playersData != null) {
        currentRoom['playerCount'] = playersData.length;
        currentRoom['playerNames'] = playersData.map((p) => (p as Map<String, dynamic>)['name']?.toString() ?? 'Player').toList();
        StateManager().updateModuleState('recall_game', {
          ...recall,
          'currentRoom': currentRoom,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }
      
    } catch (e) {
      _log.error('Failed to handle players update: $e');
    }
  }

  /// Handle error event
  void _handleError(Map<String, dynamic> data) {
    try {
      final message = data['message'] as String? ?? 'Unknown error';
      final sm7 = StateManager();
      final current7 = sm7.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      sm7.updateModuleState('recall_game', {
        ...current7,
        'error': message,
        'isLoading': false,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      _log.warning('❌ Recall game error: $message');
      
    } catch (e) {
      _log.error('Failed to handle error: $e');
    }
  }

  /// Dispose the service
  void dispose() {
    if (_isDisposed) return;
    
    _log.info('🗑️ Disposing RecallNetworkService...');
    _isDisposed = true;
    
    // Clean up any resources
  }
}
