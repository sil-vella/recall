import 'validated_event_emitter.dart';
import 'validated_state_updater.dart';
import '../../managers/state_manager.dart';

/// Convenient helper methods for recall game operations
/// Provides type-safe, validated methods for common game actions
class RecallGameHelpers {
  // Singleton instances
  static final _eventEmitter = RecallGameEventEmitter.instance;
  static final _stateUpdater = RecallGameStateUpdater.instance;
  
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
  static Future<Map<String, dynamic>> joinGame(String gameId, String playerName) {
    return _eventEmitter.emit(
      eventType: 'join_game',
      data: {
        'game_id': gameId,
        'player_name': playerName,
      },
    );
  }
  
  /// Start a match with validation
  static Future<Map<String, dynamic>> startMatch(String gameId) {
    return _eventEmitter.emit(
      eventType: 'start_match',
      data: {'game_id': gameId},
    );
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
  
  /// Update UI state (for non-validated transient state like selected cards)
  static void updateUIState(Map<String, dynamic> updates) {
    final stateManager = StateManager();
    final currentState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
    
    stateManager.updateModuleState("recall_game", {
      ...currentState,
      ...updates,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
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
  // CONVENIENCE METHODS
  // ========================================
  
  /// Quick room creation for common scenarios
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
}
