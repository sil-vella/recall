import 'validated_event_emitter.dart';
import 'validated_state_updater.dart';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../tools/logging/logger.dart';
import '../services/game_service.dart';

/// Convenient helper methods for recall game operations
/// Provides type-safe, validated methods for common game actions
class RecallGameHelpers {
  static final Logger _log = Logger();
  // Singleton instances
  static final _eventEmitter = RecallGameEventEmitter.instance;
  static final _stateUpdater = RecallGameStateUpdater.instance;
  static final _gameService = GameService();
  
  // ========================================
  // EVENT EMISSION HELPERS
  // ========================================
  
  /// Create a new room with validation
  static Future<Map<String, dynamic>> createRoom({
    required String roomName,
    required String permission,
    required int maxPlayers,
    required int minPlayers,
    String gameType = 'classic',
    int turnTimeLimit = 30,
    bool autoStart = false,
    String? password,
  }) {
    final data = {
      'room_name': roomName,
      'permission': permission,
      'max_players': maxPlayers,
      'min_players': minPlayers,
      'game_type': gameType,
      'turn_time_limit': turnTimeLimit,
      'auto_start': autoStart,
    };
    
    // Add password for private rooms
    if (permission == 'private' && password != null) {
      data['password'] = password;
    }
    
    return _eventEmitter.emit(
      eventType: 'create_room',
      data: data,
    );
  }
  
  /// Join a game with validation
  static Future<Map<String, dynamic>> joinGame(String gameId, String playerName, {int? maxPlayers}) {
    final data = <String, dynamic>{
      'game_id': gameId,
      'player_name': playerName,
    };
    
    // Add max_players if provided
    if (maxPlayers != null) {
      data['max_players'] = maxPlayers;
    }
    
    return _eventEmitter.emit(
      eventType: 'join_game',
      data: data,
    );
  }
  
  /// Start a match with validation
  static Future<Map<String, dynamic>> startMatch(String gameId) {
    _log.info('🎮 [RecallGameHelpers.startMatch] Called with gameId: $gameId');
    _log.info('🎮 [RecallGameHelpers.startMatch] gameId type: ${gameId.runtimeType}');
    _log.info('🎮 [RecallGameHelpers.startMatch] gameId length: ${gameId.length}');
    
    // Log WebSocket connection debug info before starting match
    final wsManager = WebSocketManager.instance;
    wsManager.logConnectionDebugInfo('START_MATCH');
    
    try {
      _log.info('🎮 [RecallGameHelpers.startMatch] About to emit start_match event');
      _log.info('🎮 [RecallGameHelpers.startMatch] Event data: {game_id: $gameId}');
      
      final result = _eventEmitter.emit(
        eventType: 'start_match',
        data: {'game_id': gameId},
      );
      
      _log.info('🎮 [RecallGameHelpers.startMatch] emit call completed');
      _log.info('🎮 [RecallGameHelpers.startMatch] emit result: $result');
      
      // Log debug info again after emit
      wsManager.logConnectionDebugInfo('POST_START_MATCH_EMIT');
      
      return result;
    } catch (e) {
      _log.error('❌ [RecallGameHelpers.startMatch] Error in emit: $e');
      _log.error('❌ [RecallGameHelpers.startMatch] Error type: ${e.runtimeType}');
      _log.error('❌ [RecallGameHelpers.startMatch] Stack trace: ${StackTrace.current}');
      
      // Log debug info on error too
      wsManager.logConnectionDebugInfo('START_MATCH_ERROR');
      
      rethrow;
    }
  }
  

  
  /// Play a card with validation
  static Future<Map<String, dynamic>> playCard({
    required String gameId,
    required String cardId,
    required String playerId,
    int? replaceIndex,
  }) {
    final data = <String, dynamic>{
      'game_id': gameId,
      'card_id': cardId,
      'player_id': playerId,
    };
    
    if (replaceIndex != null) {
      data['replace_index'] = replaceIndex;
    }
    
    return _eventEmitter.emit(
      eventType: 'play_card',
      data: data,
    );
  }
  
  /// Replace a card in hand with the drawn card
  static Future<Map<String, dynamic>> replaceDrawnCard({
    required String gameId,
    required String playerId,
    required int cardIndex,
  }) {
    return _eventEmitter.emit(
      eventType: 'replace_drawn_card',
      data: {
        'game_id': gameId,
        'player_id': playerId,
        'card_index': cardIndex,
      },
    );
  }
  
  /// Place the drawn card and play it
  static Future<Map<String, dynamic>> placeDrawnCard({
    required String gameId,
    required String playerId,
  }) {
    return _eventEmitter.emit(
      eventType: 'play_drawn_card',
      data: {
        'game_id': gameId,
        'player_id': playerId,
      },
    );
  }
  
  /// Call recall with validation
  static Future<Map<String, dynamic>> callRecall({
    required String gameId,
    required String playerId,
  }) {
    return _eventEmitter.emit(
      eventType: 'call_recall',
      data: {
        'game_id': gameId,
        'player_id': playerId,
      },
    );
  }
  
  /// Leave a game with validation
  static Future<Map<String, dynamic>> leaveGame({
    required String gameId,
    String? reason,
  }) {
    final data = {'game_id': gameId};
    
    if (reason != null) {
      data['reason'] = reason;
    }
    
    return _eventEmitter.emit(
      eventType: 'leave_game',
      data: data,
    );
  }
  
  /// Draw a card with validation
  static Future<Map<String, dynamic>> drawCard({
    required String gameId,
    required String playerId,
    required String source, // 'deck' or 'discard'
  }) {
    return _eventEmitter.emit(
      eventType: 'draw_card',
      data: {
        'game_id': gameId,
        'player_id': playerId,
        'source': source,
      },
    );
  }
  
  /// Play out-of-turn with validation
  static Future<Map<String, dynamic>> playOutOfTurn({
    required String gameId,
    required String cardId,
    required String playerId,
  }) {
    return _eventEmitter.emit(
      eventType: 'play_out_of_turn',
      data: {
        'game_id': gameId,
        'card_id': cardId,
        'player_id': playerId,
      },
    );
  }

  /// Add event listener with validation
  static void onEvent(String eventType, Function(Map<String, dynamic>) callback) {
    // This method is deprecated - use RecallGameEventListenerExtension.onEvent instead
    throw UnsupportedError('Use RecallGameEventListenerExtension.onEvent instead');
  }

  /// Use special power with validation
  static Future<Map<String, dynamic>> useSpecialPower({
    required String gameId,
    required String cardId,
    required String playerId,
    Map<String, dynamic>? powerData,
  }) {
    final data = <String, dynamic>{
      'game_id': gameId,
      'card_id': cardId,
      'player_id': playerId,
    };
    
    if (powerData != null) {
      data['power_data'] = powerData;
    }
    
    return _eventEmitter.emit(
      eventType: 'use_special_power',
      data: data,
    );
  }
  
  // ========================================
  // STATE UPDATE HELPERS
  // ========================================
  
  /// Set user authentication info
  static void setUserInfo({
    required String userId,
    required String username,
  }) {
    _stateUpdater.updateState({
      'userId': userId,
      'username': username,
    });
  }
  
  /// Set room ownership status
  static void setRoomOwnership({
    required bool isOwner,
    required String roomId,
    String? roomName,
  }) {
    final updates = {
      'isRoomOwner': isOwner,
      'currentRoomId': roomId,
      'isInRoom': true,
    };
    
    if (roomName != null) {
      updates['roomName'] = roomName;
    }
    
    _stateUpdater.updateState(updates);
  }
  
  /// Set game active status
  static void setGameActive({
    required bool isActive,
    required String gameId,
    String? playerId,
  }) {
    final updates = <String, dynamic>{
      'isGameActive': isActive,
      'currentGameId': gameId,
      'gameStatus': isActive ? 'active' : 'inactive',
      'gamePhase': isActive ? 'playing' : 'waiting',
    };
    
    if (playerId != null) {
      updates['playerId'] = playerId;
    }
    
    _stateUpdater.updateState(updates);
  }
  
  /// Update player turn status
  static void updatePlayerTurn({
    required bool isMyTurn,
    required bool canPlayCard,
    required bool canCallRecall,
  }) {
    _stateUpdater.updateState({
      'isMyTurn': isMyTurn,
      'canPlayCard': canPlayCard,
      'canCallRecall': canCallRecall,
    });
  }
  
  /// Update room info
  static void updateRoomInfo({
    String? roomId,
    String? roomName,
    String? permission,
    int? currentSize,
    int? maxSize,
    int? minSize,
    bool? isInRoom,
  }) {
    final updates = <String, dynamic>{};
    
    if (roomId != null) updates['currentRoomId'] = roomId;
    if (roomName != null) updates['roomName'] = roomName;
    if (permission != null) updates['permission'] = permission;
    if (currentSize != null) updates['currentSize'] = currentSize;
    if (maxSize != null) updates['maxSize'] = maxSize;
    if (minSize != null) updates['minSize'] = minSize;
    if (isInRoom != null) updates['isInRoom'] = isInRoom;
    
    if (updates.isNotEmpty) {
      _stateUpdater.updateState(updates);
    }
  }
  
  /// Update game info
  static void updateGameInfo({
    String? gameId,
    String? gamePhase,
    String? gameStatus,
    bool? isGameActive,
    int? turnNumber,
    int? roundNumber,
    int? playerCount,
  }) {
    final updates = <String, dynamic>{};
    
    if (gameId != null) updates['currentGameId'] = gameId;
    if (gamePhase != null) updates['gamePhase'] = gamePhase;
    if (gameStatus != null) updates['gameStatus'] = gameStatus;
    if (isGameActive != null) updates['isGameActive'] = isGameActive;
    if (turnNumber != null) updates['turnNumber'] = turnNumber;
    if (roundNumber != null) updates['roundNumber'] = roundNumber;
    if (playerCount != null) updates['playerCount'] = playerCount;
    
    if (updates.isNotEmpty) {
      _stateUpdater.updateState(updates);
    }
  }
  
  /// Update connection status
  static void updateConnectionStatus({
    required bool isConnected,
    bool? isLoading,
    String? lastError,
  }) {
    final updates = <String, dynamic>{
      'isConnected': isConnected,
    };
    
    if (isLoading != null) updates['isLoading'] = isLoading;
    if (lastError != null) updates['lastError'] = lastError;
    
    _stateUpdater.updateState(updates);
  }
  
  /// Clear game state (when leaving game)
  static void clearGameState() {
    _stateUpdater.updateState({
      'currentGameId': null,
      'playerId': null,
      'isGameActive': false,
      'gamePhase': 'waiting',
      'gameStatus': 'inactive',
      'turnNumber': 0,
      'roundNumber': 0,
      'playerCount': 0,
      'isMyTurn': false,
      'canPlayCard': false,
      'canCallRecall': false,
    });
  }
  
  /// Clear room state (when leaving room)
  static void clearRoomState() {
    _stateUpdater.updateState({
      'currentRoomId': null,
      'roomName': null,
      'isInRoom': false,
      'isRoomOwner': false,
      'currentSize': 0,
      'maxSize': 4,
      'minSize': 2,
      'permission': 'public',
    });
  }
  
  /// Set loading state
  static void setLoading(bool isLoading, {String? error}) {
    final updates = <String, dynamic>{'isLoading': isLoading};
    
    if (error != null) {
      updates['lastError'] = error;
    } else if (!isLoading) {
      // Clear error when loading completes successfully
      updates['lastError'] = null;
    }
    
    _stateUpdater.updateState(updates);
  }
  
  // ========================================
  // UI STATE HELPERS (for transient UI state not in validated schema)
  // ========================================
  
  /// Update UI state using validated state updater
  static void updateUIState(Map<String, dynamic> updates) {
    _log.info('🎯 [RecallGameHelpers] updateUIState called with: ${updates.keys.join(', ')}');
    
    // Debug specific fields
    if (updates.containsKey('isRoomOwner')) {
      _log.info('  - isRoomOwner: ${updates['isRoomOwner']}');
    }
    if (updates.containsKey('isGameActive')) {
      _log.info('  - isGameActive: ${updates['isGameActive']}');
    }
    
    _stateUpdater.updateState(updates);
  }
  
  /// Set selected card (UI state)
  static void setSelectedCard(Map<String, dynamic>? cardJson, int? cardIndex) {
    updateUIState({
      'selectedCard': cardJson,
      'selectedCardIndex': cardIndex,
    });
  }
  
  /// Clear selected card (UI state)
  static void clearSelectedCard() {
    updateUIState({
      'selectedCard': null,
      'selectedCardIndex': null,
    });
  }
  
  // ========================================
  // GAME TRACKING METHODS
  // ========================================
  
  /// Register a new active game
  static void registerActiveGame({
    required String gameId,
    required String gamePhase,
    required String gameStatus,
    required int playerCount,
    required String roomName,
    String? ownerId,
    Map<String, dynamic>? additionalData,
  }) {
    final stateManager = StateManager();
    final currentState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    final activeGames = Map<String, Map<String, dynamic>>.from(currentState['activeGames'] ?? {});
    
    activeGames[gameId] = {
      'gameId': gameId,
      'roomId': gameId, // Same as game ID
      'roomName': roomName,
      'gamePhase': gamePhase,
      'gameStatus': gameStatus,
      'playerCount': playerCount,
      'ownerId': ownerId,
      'createdAt': DateTime.now().toIso8601String(),
      'lastUpdated': DateTime.now().toIso8601String(),
      ...?additionalData,
    };
    
    _stateUpdater.updateState({'activeGames': activeGames});
  }
  
  /// Update an existing active game
  static void updateActiveGame({
    required String gameId,
    String? gamePhase,
    String? gameStatus,
    int? playerCount,
    Map<String, dynamic>? additionalData,
  }) {
    final stateManager = StateManager();
    final currentState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    final activeGames = Map<String, Map<String, dynamic>>.from(currentState['activeGames'] ?? {});
    
    if (activeGames.containsKey(gameId)) {
      final gameData = Map<String, dynamic>.from(activeGames[gameId]!);
      
      if (gamePhase != null) gameData['gamePhase'] = gamePhase;
      if (gameStatus != null) gameData['gameStatus'] = gameStatus;
      if (playerCount != null) gameData['playerCount'] = playerCount;
      if (additionalData != null) gameData.addAll(additionalData);
      
      gameData['lastUpdated'] = DateTime.now().toIso8601String();
      activeGames[gameId] = gameData;
      
      _stateUpdater.updateState({'activeGames': activeGames});
    }
  }
  
  /// Remove a game from active tracking
  static void removeActiveGame(String gameId) {
    final stateManager = StateManager();
    final currentState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    final activeGames = Map<String, Map<String, dynamic>>.from(currentState['activeGames'] ?? {});
    
    if (activeGames.containsKey(gameId)) {
      activeGames.remove(gameId);
      _stateUpdater.updateState({'activeGames': activeGames});
    }
  }
  
  /// Get active game info by ID
  static Map<String, dynamic>? getActiveGame(String gameId) {
    final stateManager = StateManager();
    final currentState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    final activeGames = Map<String, Map<String, dynamic>>.from(currentState['activeGames'] ?? {});
    
    return activeGames[gameId];
  }
  
  /// Get all active games
  static Map<String, Map<String, dynamic>> getAllActiveGames() {
    final stateManager = StateManager();
    final currentState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    return Map<String, Map<String, dynamic>>.from(currentState['activeGames'] ?? {});
  }
  
  /// Check if a game is active
  static bool isGameActive(String gameId) {
    final gameInfo = getActiveGame(gameId);
    return gameInfo != null && gameInfo['gameStatus'] == 'active';
  }
  
  /// Get active games count
  static int getActiveGamesCount() {
    return getAllActiveGames().length;
  }
  
  /// Get active games for a specific room/game ID
  static List<Map<String, dynamic>> getActiveGamesForRoom(String roomId) {
    final activeGames = getAllActiveGames();
    return activeGames.values.where((game) => game['roomId'] == roomId).toList();
  }
  
  /// Clean up ended games (remove games with 'ended' status)
  static void cleanupEndedGames() {
    final stateManager = StateManager();
    final currentState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    final activeGames = Map<String, Map<String, dynamic>>.from(currentState['activeGames'] ?? {});
    
    final endedGameIds = <String>[];
    for (final entry in activeGames.entries) {
      if (entry.value['gameStatus'] == 'ended') {
        endedGameIds.add(entry.key);
      }
    }
    
    for (final gameId in endedGameIds) {
      activeGames.remove(gameId);
    }
    
    if (endedGameIds.isNotEmpty) {
      _stateUpdater.updateState({'activeGames': activeGames});
    }
  }

  // ========================================
  // ROOM QUERY METHODS
  // ========================================

  /// Get list of pending (public, not started) games
  static Future<Map<String, dynamic>> getPendingGames() {
    return _eventEmitter.emit(
      eventType: 'get_public_rooms',
      data: {
        'filter': {
          'status': 'waiting', // Only games that haven't started
          'permission': 'public',
        },
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // ========================================
  // CONVENIENCE METHODS
  // ========================================
  
  /// Quick public room creation with default settings
  static Future<Map<String, dynamic>> createPublicRoom({
    required String roomName,
    int maxPlayers = 4,
    int minPlayers = 2,
  }) {
    return createRoom(
      roomName: roomName,
      permission: 'public',
      maxPlayers: maxPlayers,
      minPlayers: minPlayers,
    );
  }
  
  /// Quick private room creation
  static Future<Map<String, dynamic>> createPrivateRoom({
    required String roomName,
    required String password,
    int maxPlayers = 4,
    int minPlayers = 2,
  }) {
    return createRoom(
      roomName: roomName,
      permission: 'private',
      password: password,
      maxPlayers: maxPlayers,
      minPlayers: minPlayers,
    );
  }
  
  /// Complete room setup after creation
  static void setupRoomOwnership({
    required String roomId,
    required String roomName,
    required String permission,
    required int currentSize,
    required int maxSize,
    required int minSize,
  }) {
    _stateUpdater.updateState({
      'isRoomOwner': true,
      'currentRoomId': roomId,
      'roomName': roomName,
      'permission': permission,
      'currentSize': currentSize,
      'maxSize': maxSize,
      'minSize': minSize,
      'isInRoom': true,
    });
  }
  
  /// Complete game setup after joining
  static void setupGameSession({
    required String gameId,
    required String playerId,
    required bool isGameActive,
    int playerCount = 1,
  }) {
    _stateUpdater.updateState({
      'currentGameId': gameId,
      'playerId': playerId,
      'isGameActive': isGameActive,
      'gamePhase': isGameActive ? 'playing' : 'waiting',
      'gameStatus': isGameActive ? 'active' : 'inactive',
      'playerCount': playerCount,
    });
  }
  
  // ========================================
  // BUSINESS LOGIC DELEGATION METHODS
  // ========================================
  
  /// Validate game state using GameService
  static bool isValidGameState(dynamic gameState) {
    return _gameService.isValidGameState(gameState);
  }
  
  /// Check if player can play card using GameService
  static bool canPlayerPlayCard(String playerId, dynamic gameState) {
    return _gameService.canPlayerPlayCard(playerId, gameState);
  }
  
  /// Check if game is ready to start using GameService
  static bool isGameReadyToStart(dynamic gameState) {
    return _gameService.isGameReadyToStart(gameState);
  }
  
  /// Check if player can call recall using GameService
  static bool canPlayerCallRecall(String playerId, dynamic gameState) {
    return _gameService.canPlayerCallRecall(playerId, gameState);
  }
  
  /// Get valid cards for player using GameService
  static List<dynamic> getValidCardsForPlayer(String playerId, dynamic gameState) {
    return _gameService.getValidCardsForPlayer(playerId, gameState);
  }
  
  /// Get game winner using GameService
  static dynamic getWinner(dynamic gameState) {
    return _gameService.getWinner(gameState);
  }
  
  /// Get game statistics using GameService
  static Map<String, dynamic> getGameStatistics(dynamic gameState) {
    return _gameService.getGameStatistics(gameState);
  }
}
