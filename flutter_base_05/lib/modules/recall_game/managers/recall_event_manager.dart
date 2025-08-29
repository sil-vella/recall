import 'dart:async';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/hooks_manager.dart';
import '../../../tools/logging/logger.dart';
import '../utils/recall_game_helpers.dart';
import '../utils/recall_event_listener_validator.dart';

class RecallEventManager {
  static final Logger _log = Logger();
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
      _log.info('📨 Initializing RecallEventManager...');
      
      // Register state domains
      _stateManager.registerModuleState("recall_messages", {
        'session': <Map<String, dynamic>>[],
        'rooms': <String, List<Map<String, dynamic>>>{},
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      // Hook to WS events (standard)
      _wireWebsocketEvents();

      // Register hook callbacks for room events
      _registerHookCallbacks();

      // Register recall-specific event listeners
      _registerRecallEventListeners();

      // Recall-specific Socket.IO listeners are centralized in RecallGameCoordinator.
      // We subscribe only via WSEventManager callbacks here.
      _log.info('✅ RecallEventManager initialized successfully');
      return true;
      
    } catch (e) {
      _log.error('❌ RecallEventManager initialization failed: $e');
      return false;
    }
  }

  void _registerRecallEventListeners() {
    _log.info('🎧 Registering recall-specific event listeners...');
    
    // Register recall_new_player_joined event listener
    RecallGameEventListenerValidator.instance.addListener('recall_new_player_joined', (data) {
      _log.info('🎧 [RECALL] Received recall_new_player_joined event');
      
      final roomId = data['room_id']?.toString() ?? '';
      final joinedPlayer = data['joined_player'] as Map<String, dynamic>? ?? {};
      final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
      
      _log.info('🎧 [RECALL] Player ${joinedPlayer['name']} joined room $roomId');
      
      // Get current state to update the games map
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      // Update the specific game in the games map with new player information
      if (currentGames.containsKey(roomId)) {
        final currentGame = currentGames[roomId] as Map<String, dynamic>? ?? {};
        final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        
        // Update the game data with the new game state
        final updatedGameData = Map<String, dynamic>.from(currentGameData);
        updatedGameData['game_state'] = gameState;
        
        // Update the game in the games map
        currentGames[roomId] = {
          ...currentGame,
          'gameData': updatedGameData,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        // Update recall game state with new player information
        RecallGameHelpers.updateUIState({
          'games': currentGames,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }
      
      // Add session message about new player
      _addSessionMessage(
        level: 'info',
        title: 'Player Joined',
        message: '${joinedPlayer['name']} joined the game',
        data: joinedPlayer,
      );
    });
    
    // Register recall_joined_games event listener
    RecallGameEventListenerValidator.instance.addListener('recall_joined_games', (data) {
      _log.info('🎧 [RECALL] Received recall_joined_games event');
      
      final userId = data['user_id']?.toString() ?? '';
      final sessionId = data['session_id']?.toString() ?? '';
      final games = data['games'] as List<dynamic>? ?? [];
      final totalGames = data['total_games'] ?? 0;
      
      _log.info('🎧 [RECALL] User $userId is in $totalGames games');
      
      // Get current state to update the games map
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      // Update the games map with the joined games data
      for (final gameData in games) {
        final gameId = gameData['game_id']?.toString() ?? '';
        if (gameId.isNotEmpty) {
          // Extract game state information
          final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
          final gamePhase = gameState['phase']?.toString() ?? 'waiting';
          final gameStatus = gameState['status']?.toString() ?? 'inactive';
          
          // Determine if current user is room owner
          final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
          final currentUserId = loginState['userId']?.toString() ?? '';
          final isRoomOwner = gameData['owner_id']?.toString() == currentUserId;
          
          // Add/update the game in the games map
          currentGames[gameId] = {
            'gameData': gameData,  // This is the single source of truth
            'gamePhase': gamePhase,
            'gameStatus': gameStatus,
            'isRoomOwner': isRoomOwner,
            'isInGame': true,
            'joinedAt': DateTime.now().toIso8601String(),
          };
        }
      }
      
      // Update recall game state with joined games information using nested structure
      RecallGameHelpers.updateUIState({
        'games': currentGames,
        'joinedGames': games.cast<Map<String, dynamic>>(),
        'totalJoinedGames': totalGames,
        'joinedGamesTimestamp': DateTime.now().toIso8601String(),
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
      // Add session message about joined games
      _addSessionMessage(
        level: 'info',
        title: 'Games Updated',
        message: 'You are now in $totalGames game${totalGames != 1 ? 's' : ''}',
        data: {'total_games': totalGames, 'games': games},
      );
    });
    
    // Register game_started event listener
    RecallGameEventListenerValidator.instance.addListener('game_started', (data) {
      _log.info('🎧 [RECALL] Received game_started event');
      
      final gameId = data['game_id']?.toString() ?? '';
      final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
      final startedBy = data['started_by']?.toString() ?? '';
      final timestamp = data['timestamp']?.toString() ?? '';
      
      _log.info('🎧 [RECALL] Game $gameId started by $startedBy');
      
      // Extract player data
      final players = gameState['players'] as List<dynamic>? ?? [];
      final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
      final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
      final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
      
      // Find the current user's player data
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId']?.toString() ?? '';
      Map<String, dynamic>? myPlayer;
      try {
        myPlayer = players.cast<Map<String, dynamic>>().firstWhere(
          (player) => player['id'] == currentUserId,
        );
      } catch (e) {
        myPlayer = null;
      }
      
      // Extract opponent players (excluding current user)
      final opponents = players.where((player) => player['id'] != currentUserId).toList();
      
      // Get current state to update the games map
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      // Update the specific game in the games map with game started information
      if (currentGames.containsKey(gameId)) {
        final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
        final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        
        // Update the game data with the new game state
        final updatedGameData = Map<String, dynamic>.from(currentGameData);
        updatedGameData['game_state'] = gameState;
        
        // Update the game in the games map
        currentGames[gameId] = {
          ...currentGame,
          'gameData': updatedGameData,
          'gamePhase': gameState['phase'] ?? 'playing',
          'gameStatus': gameState['status'] ?? 'active',
          'isGameActive': true,
          
          // Update game-specific fields for widget slices
          'drawPileCount': drawPile.length,
          'discardPile': discardPile,
          'opponentPlayers': opponents.cast<Map<String, dynamic>>(),
          'currentPlayerIndex': currentPlayer != null ? players.indexOf(currentPlayer) : -1,
          'myHandCards': myPlayer?['hand'] ?? [],
          'selectedCardIndex': -1,
          
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        // Update recall game state with game started information using nested structure
        RecallGameHelpers.updateUIState({
          'games': currentGames,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        _log.info('🎮 [GAME_STARTED] Updated game $gameId in nested structure');
      }
      
      // Add session message about game started
      _addSessionMessage(
        level: 'success',
        title: 'Game Started',
        message: 'Game $gameId has started!',
        data: {
          'game_id': gameId,
          'started_by': startedBy,
          'game_state': gameState,
        },
      );
    });
    
    // Register turn_started event listener
    RecallGameEventListenerValidator.instance.addListener('turn_started', (data) {
      _log.info('🎧 [RECALL] Received turn_started event');
      
      final gameId = data['game_id']?.toString() ?? '';
      final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
      final playerId = data['player_id']?.toString() ?? '';
      final turnTimeout = data['turn_timeout'] as int? ?? 30;
      final timestamp = data['timestamp']?.toString() ?? '';
      
      _log.info('🎧 [RECALL] Turn started for player $playerId in game $gameId (timeout: ${turnTimeout}s)');
      
      // Find the current user's player data
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId']?.toString() ?? '';
      
      // Check if this turn is for the current user
      final isMyTurn = playerId == currentUserId;
      
      if (isMyTurn) {
        _log.info('🎯 [TURN_STARTED] It\'s my turn! Timeout: ${turnTimeout}s');
        
        // Update UI state to show it's the current user's turn
        RecallGameHelpers.updateUIState({
          'isMyTurn': true,
          'turnTimeout': turnTimeout,
          'turnStartTime': DateTime.now().toIso8601String(),
          'statusBar': {
            'currentPhase': 'my_turn',
            'turnTimer': turnTimeout,
            'turnStartTime': DateTime.now().toIso8601String(),
          },
        });
        
        // Add session message about turn started
        _addSessionMessage(
          level: 'info',
          title: 'Your Turn',
          message: 'It\'s your turn! You have ${turnTimeout} seconds to play.',
          data: {
            'game_id': gameId,
            'player_id': playerId,
            'turn_timeout': turnTimeout,
            'is_my_turn': true,
          },
        );
      } else {
        _log.info('🎯 [TURN_STARTED] Turn started for opponent $playerId');
        
        // Update UI state to show it's another player's turn
        RecallGameHelpers.updateUIState({
          'isMyTurn': false,
          'statusBar': {
            'currentPhase': 'opponent_turn',
            'currentPlayer': playerId,
          },
        });
        
        // Add session message about opponent's turn
        _addSessionMessage(
          level: 'info',
          title: 'Opponent\'s Turn',
          message: 'It\'s $playerId\'s turn to play.',
          data: {
            'game_id': gameId,
            'player_id': playerId,
            'is_my_turn': false,
          },
        );
      }
    });
    
    _log.info('✅ Recall-specific event listeners registered');
  }

  void _registerHookCallbacks() {
    _log.info('🎣 Registering hook callbacks for RecallEventManager...');
    
    // Register room_creation hook callback
    HooksManager().registerHookWithData('room_creation', (data) {
      _log.info('🎣 [HOOK] RecallEventManager received room_creation hook: ${data['status']}');
      
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
      _log.info('🎣 [HOOK] RecallEventManager received websocket_user_joined_rooms hook');
      
      final status = data['status']?.toString() ?? 'unknown';
      final sessionId = data['session_id']?.toString() ?? '';
      final rooms = data['rooms'] as List<dynamic>? ?? [];
      final totalRooms = data['total_rooms'] ?? 0;
      
      _log.info('🎣 [HOOK] User joined rooms update: session=$sessionId, total_rooms=$totalRooms');
      
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
        
        _log.info('🎣 [HOOK] Cleared joined games state - user not in any rooms');
      } else {
        // User is still in some rooms, but we need to update the joined games
        // This will be handled by the recall_joined_games event when it's sent
        _log.info('🎣 [HOOK] User still in $totalRooms rooms, waiting for recall_joined_games event');
      }
    });
    
    _log.info('✅ Hook callbacks registered successfully');
  }

  void _wireWebsocketEvents() {
    // Use validated event listener for each message-related event type
    final eventTypes = [
      'connection_status', 'board_message', 'error',
      'game_event', 
    ];
    
    for (final eventType in eventTypes) {
      RecallGameEventListenerExtension.onEvent(eventType, (data) {
        switch (eventType) {
          case 'connection_status':
            final status = data['status']?.toString() ?? 'unknown';
            _addSessionMessage(level: 'info', title: 'Connection', message: 'Status: $status', data: data);
            break;
            
          case 'board_message':
            final roomId = data['room_id']?.toString() ?? '';
            final msg = data['message']?.toString() ?? '';
            if (roomId.isNotEmpty) {
              _addRoomMessage(roomId, level: 'info', title: 'Message', message: msg, data: data);
            } else {
              _addSessionMessage(level: 'info', title: 'Message', message: msg, data: data);
            }
            break;
            
          case 'error':
            _addSessionMessage(level: 'error', title: 'Error', message: data['error']?.toString() ?? 'Error', data: data);
            break;
            
          case 'game_event':
            final scope = data['scope']?.toString();
            if (scope == 'room') {
              final roomId = data['target_id']?.toString() ?? '';
              if (roomId.isNotEmpty) _addRoomMessage(roomId, level: data['level'], title: data['title'], message: data['message'], data: data);
            } else {
              _addSessionMessage(level: data['level'], title: data['title'], message: data['message'], data: data);
            }
            break;

        }
      });
    }
  }

  void _addRoomMessage(String roomId, {required String? level, required String? title, required String? message, Map<String, dynamic>? data}) {
    final entry = _entry(level, title, message, data);
    final list = _roomBoards.putIfAbsent(roomId, () => <Map<String, dynamic>>[]);
    list.add(entry);
    if (list.length > 200) list.removeAt(0);
    _emitState();
  }

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