import 'dart:async';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/hooks_manager.dart';
import '../../../tools/logging/logger.dart';
import '../utils/recall_game_helpers.dart';
import '../utils/recall_event_listener_validator.dart';
import '../utils/validated_state_updater.dart';

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

  // ========================================
  // HELPER METHODS TO REDUCE DUPLICATION
  // ========================================
  
  /// Get current games map from state manager
  Map<String, dynamic> _getCurrentGamesMap() {
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    return Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
  }
  
  /// Update a specific game in the games map and sync to global state
  void _updateGameInMap(String gameId, Map<String, dynamic> updates) {
    final currentGames = _getCurrentGamesMap();
    
    if (currentGames.containsKey(gameId)) {
      final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
      
      // Merge updates with current game data
      currentGames[gameId] = {
        ...currentGame,
        ...updates,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      // Update global state
      RecallGameHelpers.updateUIState({
        'games': currentGames,
      });
      
      _log.info('🎯 [HELPER] Updated game $gameId with: ${updates.keys.join(', ')}');
    } else {
      _log.warning('⚠️ [HELPER] Game $gameId not found in current games map');
    }
  }
  
  /// Update game data within a game's gameData structure
  void _updateGameData(String gameId, Map<String, dynamic> dataUpdates) {
    final currentGames = _getCurrentGamesMap();
    
    if (currentGames.containsKey(gameId)) {
      final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
      final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      
      // Update the game data
      final updatedGameData = Map<String, dynamic>.from(currentGameData);
      updatedGameData.addAll(dataUpdates);
      
      // Update the game with new game data
      _updateGameInMap(gameId, {
        'gameData': updatedGameData,
      });
      
      _log.info('🎯 [HELPER] Updated game data for game $gameId with: ${dataUpdates.keys.join(', ')}');
    }
  }
  
  /// Get current user ID from login state
  String _getCurrentUserId() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    return loginState['userId']?.toString() ?? '';
  }
  
  /// Check if current user is room owner for a specific game
  bool _isCurrentUserRoomOwner(Map<String, dynamic> gameData) {
    final currentUserId = _getCurrentUserId();
    return gameData['owner_id']?.toString() == currentUserId;
  }
  
  /// Add a game to the games map with standard structure
  void _addGameToMap(String gameId, Map<String, dynamic> gameData, {String? gamePhase, String? gameStatus}) {
    final currentGames = _getCurrentGamesMap();
    
    // Determine game phase and status
    final phase = gamePhase ?? gameData['game_state']?['phase']?.toString() ?? 'waiting';
    final status = gameStatus ?? gameData['game_state']?['status']?.toString() ?? 'inactive';
    
    // Add/update the game in the games map
    currentGames[gameId] = {
      'gameData': gameData,  // Single source of truth
      'gamePhase': phase,
      'gameStatus': status,
      'isRoomOwner': _isCurrentUserRoomOwner(gameData),
      'isInGame': true,
      'joinedAt': DateTime.now().toIso8601String(),
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    // Update global state
    RecallGameHelpers.updateUIState({
      'games': currentGames,
    });
    
    _log.info('🎯 [HELPER] Added/updated game $gameId to games map');
  }
  
  /// Update main game state (non-game-specific fields)
  void _updateMainGameState(Map<String, dynamic> updates) {
    RecallGameHelpers.updateUIState({
      ...updates,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    
    _log.info('🎯 [HELPER] Updated main game state with: ${updates.keys.join(', ')}');
  }

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
      
      // Update the game data with the new game state using helper method
      _updateGameData(roomId, {
        'game_state': gameState,
      });
      
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
      
      // Update the games map with the joined games data using helper methods
      for (final gameData in games) {
        final gameId = gameData['game_id']?.toString() ?? '';
        if (gameId.isNotEmpty) {
          // Add/update the game in the games map using helper method
          _addGameToMap(gameId, gameData);
        }
      }
      
      // Update recall game state with joined games information using helper method
      _updateMainGameState({
        'joinedGames': games.cast<Map<String, dynamic>>(),
        'totalJoinedGames': totalGames,
        'joinedGamesTimestamp': DateTime.now().toIso8601String(),
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
      
      // Update the game data with the new game state using helper method
      _updateGameData(gameId, {
        'game_state': gameState,
      });
      
      // Update the game with game started information using helper method
      _updateGameInMap(gameId, {
        'gamePhase': gameState['phase'] ?? 'playing',
        'gameStatus': gameState['status'] ?? 'active',
        'isGameActive': true,
        'isRoomOwner': startedBy == currentUserId,  // ✅ Set ownership based on who started the game
        
        // Update game-specific fields for widget slices
        'drawPileCount': drawPile.length,
        'discardPile': discardPile,
        'opponentPlayers': opponents.cast<Map<String, dynamic>>(),
        'currentPlayerIndex': currentPlayer != null ? players.indexOf(currentPlayer) : -1,
        'myHandCards': myPlayer?['hand'] ?? [],
        'selectedCardIndex': -1,
      });
      
      _log.info('🎮 [GAME_STARTED] Updated game $gameId using helper methods');
      
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
      final playerStatus = data['player_status']?.toString() ?? 'unknown';
      final turnTimeout = data['turn_timeout'] as int? ?? 30;
      final timestamp = data['timestamp']?.toString() ?? '';
      
      _log.info('🎧 [RECALL] Turn started for player $playerId in game $gameId (status: $playerStatus, timeout: ${turnTimeout}s)');
      
      // Find the current user's player data
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId']?.toString() ?? '';
      
      // Check if this turn is for the current user
      final isMyTurn = playerId == currentUserId;
      
      if (isMyTurn) {
        _log.info('🎯 [TURN_STARTED] It\'s my turn! Timeout: ${turnTimeout}s');
        
        // Update UI state to show it's the current user's turn using helper method
        _updateMainGameState({
          'isMyTurn': true,
          'turnTimeout': turnTimeout,
          'turnStartTime': DateTime.now().toIso8601String(),
          'playerStatus': playerStatus,
          'statusBar': {
            'currentPhase': 'my_turn',
            'turnTimer': turnTimeout,
            'turnStartTime': DateTime.now().toIso8601String(),
            'playerStatus': playerStatus,
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
        
        // Update UI state to show it's another player's turn using helper method
        _updateMainGameState({
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
    
    // Register game_state_updated event listener
    RecallGameEventListenerValidator.instance.addListener('game_state_updated', (data) {
      _log.info('🎧 [RECALL] Received game_state_updated event');
      
      final gameId = data['game_id']?.toString() ?? '';
      final gameState = data['game_state'] as Map<String, dynamic>? ?? {};
      final roundNumber = data['round_number'] as int? ?? 1;
      final currentPlayer = data['current_player']?.toString() ?? '';
      final currentPlayerStatus = data['current_player_status']?.toString() ?? 'unknown';
      final roundStatus = data['round_status']?.toString() ?? 'active';
      final timestamp = data['timestamp']?.toString() ?? '';
      
      _log.info('🎧 [RECALL] Game state updated for game $gameId - Round: $roundNumber, Current Player: $currentPlayer ($currentPlayerStatus), Status: $roundStatus');
      
      // Extract pile information from game state
      final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
      final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
      final drawPileCount = drawPile.length;
      final discardPileCount = discardPile.length;
      
      _log.info('🎧 [RECALL] Pile counts - Draw: $drawPileCount, Discard: $discardPileCount');
      
      // Update the main game state with the new information using helper method
      _updateMainGameState({
        'gamePhase': gameState['phase'] ?? 'playing',
        'isGameActive': true,
        'roundNumber': roundNumber,
        'currentPlayer': currentPlayer,
        'currentPlayerStatus': currentPlayerStatus,
        'roundStatus': roundStatus,
      });
      
      // Update the games map with pile information using helper method
      _updateGameInMap(gameId, {
        'drawPileCount': drawPileCount,
        'discardPileCount': discardPileCount,
        'discardPile': discardPile,
      });
      
      _log.info('🎯 [GAME_STATE_UPDATE] Updated pile counts for game $gameId - Draw: $drawPileCount, Discard: $discardPileCount');
      
      // Add session message about game state update
      _addSessionMessage(
        level: 'info',
        title: 'Game State Updated',
        message: 'Round $roundNumber - $currentPlayer is $currentPlayerStatus',
        data: {
          'game_id': gameId,
          'round_number': roundNumber,
          'current_player': currentPlayer,
          'current_player_status': currentPlayerStatus,
          'round_status': roundStatus,
        },
      );
    });
    
    // Register player_state_updated event listener
    RecallGameEventListenerValidator.instance.addListener('player_state_updated', (data) {
      _log.info('🎧 [RECALL] Received player_state_updated event');
      
      final gameId = data['game_id']?.toString() ?? '';
      final playerId = data['player_id']?.toString() ?? '';
      final playerData = data['player_data'] as Map<String, dynamic>? ?? {};
      final timestamp = data['timestamp']?.toString() ?? '';
      
      _log.info('🎧 [RECALL] Player state updated for player $playerId in game $gameId');
      
      // Find the current user's player data
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId']?.toString() ?? '';
      
      // Check if this update is for the current user
      final isMyUpdate = playerId == currentUserId;
      
      if (isMyUpdate) {
        _log.info('🎯 [PLAYER_STATE_UPDATE] Updating my player state');
        
        // Extract player data fields
        final hand = playerData['hand'] as List<dynamic>? ?? [];
        final visibleCards = playerData['visibleCards'] as List<dynamic>? ?? [];
        final score = playerData['score'] as int? ?? 0;
        final status = playerData['status']?.toString() ?? 'unknown';
        final isCurrentPlayer = playerData['isCurrentPlayer'] == true;
        final hasCalledRecall = playerData['hasCalledRecall'] == true;
        
        // Update the main game state with player information using helper method
        _updateMainGameState({
          'playerStatus': status,
          'myScore': score,
          'isMyTurn': isCurrentPlayer,
        });
        
        // Update the games map with hand information using helper method
        _updateGameInMap(gameId, {
          'myHandCards': hand,
          'selectedCardIndex': -1,
          'isMyTurn': isCurrentPlayer,
        });
        
        _log.info('✅ [PLAYER_STATE_UPDATE] My player state updated - Hand: ${hand.length} cards, Score: $score, Status: $status');
        
        // Add session message about player state update
        _addSessionMessage(
          level: 'info',
          title: 'Player State Updated',
          message: 'Hand: ${hand.length} cards, Score: $score, Status: $status',
          data: {
            'game_id': gameId,
            'player_id': playerId,
            'hand_size': hand.length,
            'score': score,
            'status': status,
            'is_current_player': isCurrentPlayer,
          },
        );
      } else {
        _log.info('👥 [PLAYER_STATE_UPDATE] Updating opponent player state for player $playerId');
        
        // Get current opponents and update them using helper method
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
        
        if (currentGames.containsKey(gameId)) {
          final currentGame = currentGames[gameId] as Map<String, dynamic>? ?? {};
          final currentGameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
          final currentOpponents = currentGameData['opponentPlayers'] as List<dynamic>? ?? [];
          
          // Update opponent information in the games map using helper method
          _updateGameData(gameId, {
            'opponentPlayers': currentOpponents.map((opponent) {
              if (opponent['id'] == playerId) {
                return {
                  ...opponent,
                  'hand': playerData['hand'] ?? [],
                  'score': playerData['score'] ?? 0,
                  'status': playerData['status'] ?? 'unknown',
                  'hasCalledRecall': playerData['hasCalledRecall'] ?? false,
                };
              }
              return opponent;
            }).toList(),
          });
        }
        
        _log.info('✅ [PLAYER_STATE_UPDATE] Opponent player state updated for player $playerId');
      }
    });
    
    _log.info('✅ Recall-specific event listeners registered');
  }

  void _registerHookCallbacks() {
    _log.info('🎣 Registering hook callbacks for RecallEventManager...');
    
    // Register websocket_connect hook callback
    HooksManager().registerHookWithData('websocket_connect', (data) {
      _log.info('🎣 [HOOK] RecallEventManager received websocket_connect hook: ${data['status']}');
      
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
        
        _log.info('✅ [HOOK] WebSocket connection status updated to connected');
      } else {
        _log.warning('⚠️ [HOOK] Unexpected websocket_connect status: $status');
      }
    });
    
    // Register websocket_disconnect hook callback
    HooksManager().registerHookWithData('websocket_disconnect', (data) {
      _log.info('🎣 [HOOK] RecallEventManager received websocket_disconnect hook: ${data['status']}');
      
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
        
        _log.info('✅ [HOOK] WebSocket connection status updated to disconnected');
      } else {
        _log.warning('⚠️ [HOOK] Unexpected websocket_disconnect status: $status');
      }
    });
    
    // Register websocket_connect_error hook callback
    HooksManager().registerHookWithData('websocket_connect_error', (data) {
      _log.info('🎣 [HOOK] RecallEventManager received websocket_connect_error hook: ${data['status']}');
      
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
        
        _log.info('✅ [HOOK] WebSocket connection status updated to error (disconnected)');
      } else {
        _log.warning('⚠️ [HOOK] Unexpected websocket_connect_error status: $status');
      }
    });
    
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
      
      _log.info('�� [HOOK] User joined rooms update: session=$sessionId, total_rooms=$totalRooms');
      
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