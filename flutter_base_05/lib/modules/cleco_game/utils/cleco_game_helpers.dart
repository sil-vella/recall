import '../../../core/managers/module_manager.dart';
import '../../../core/managers/state_manager.dart';
import '../../connections_api_module/connections_api_module.dart';
import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../tools/logging/logger.dart';
import '../managers/validated_event_emitter.dart';
import '../../cleco_game/managers/cleco_game_state_updater.dart';

/// Convenient helper methods for cleco game operations
/// Provides type-safe, validated methods for common game actions
class ClecoGameHelpers {
  // Singleton instances
  static final _eventEmitter = ClecoGameEventEmitter.instance;
  static final _stateUpdater = ClecoGameStateUpdater.instance;
  static final _logger = Logger();
  
  static const bool LOGGING_SWITCH = false; // Enabled for cleanup testing
  
  // ========================================
  // EVENT EMISSION HELPERS
  // ========================================
  
  /// Create a new room with validation
  static Future<Map<String, dynamic>> createRoom({
    required String permission,
    required int maxPlayers,
    required int minPlayers,
    String gameType = 'classic',
    int turnTimeLimit = 30,
    bool autoStart = false,
    String? password,
  }) {
    final data = {
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

  /// Join an existing room with validation
  static Future<Map<String, dynamic>> joinRoom({
    required String roomId,
  }) {
    final data = {
      'room_id': roomId,
    };
    
    return _eventEmitter.emit(
      eventType: 'join_room',
      data: data,
    );
  }

  /// Fetch available games from the Dart backend via WebSocket
  /// Uses list_rooms WebSocket event to get all available rooms
  static Future<Map<String, dynamic>> fetchAvailableGames() async {
    try {
      // Ensure WebSocket is connected
      final wsManager = WebSocketManager.instance;
      if (!wsManager.isConnected) {
        final connected = await wsManager.connect();
        if (!connected) {
          throw Exception('WebSocket not connected - cannot fetch games');
        }
      }
      
      // Emit list_rooms event via validated event emitter
      // The response will come back as 'rooms_list' event
      await _eventEmitter.emit(
        eventType: 'list_rooms',
        data: {},
      );
      
      // The emit returns immediately, but the actual response comes via WebSocket event
      // The 'rooms_list' event handler will update the state automatically
      // Return success - the actual games will be updated via event handler
      return {
        'success': true,
        'message': 'Fetching games...',
        'games': [],
        'count': 0,
      };
      
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to fetch available games: $e',
        'games': [],
        'count': 0,
      };
    }
  }
  


  // ========================================
  // STATE UPDATE HELPERS
  // ========================================
  
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

  /// Update UI state using validated state updater
  static void updateUIState(Map<String, dynamic> updates) {
    _stateUpdater.updateState(updates);
  }

  /// Join a random available game or auto-create and start a new one
  /// Uses join_random_game WebSocket event
  static Future<Map<String, dynamic>> joinRandomGame() async {
    try {
      // Ensure WebSocket is connected
      final wsManager = WebSocketManager.instance;
      if (!wsManager.isConnected) {
        final connected = await wsManager.connect();
        if (!connected) {
          throw Exception('WebSocket not connected - cannot join random game');
        }
      }
      
      // Set flag to indicate we're in a random join flow (for navigation)
      // IMPORTANT: Use updateStateSync to ensure synchronous update before emitting event
      // Using updateUIState goes through StateQueueValidator which is async and can cause race conditions
      _stateUpdater.updateStateSync({
        'isRandomJoinInProgress': true,
      });
      _logger.info('🎯 Set isRandomJoinInProgress=true using updateStateSync', isOn: LOGGING_SWITCH);
      
      // Emit join_random_game event via validated event emitter
      await _eventEmitter.emit(
        eventType: 'join_random_game',
        data: {},
      );
      
      // The emit returns immediately, but the actual response comes via WebSocket events
      // Return success - the actual join/creation will be handled via event handlers
      return {
        'success': true,
        'message': 'Searching for available game...',
      };
      
    } catch (e) {
      // Clear flag on error
      updateUIState({
        'isRandomJoinInProgress': false,
      });
      return {
        'success': false,
        'error': 'Failed to join random game: $e',
      };
    }
  }

  /// Find a specific game by room ID via API call
  static Future<Map<String, dynamic>> findRoom(String roomId) async {
    try {
      // Get the ConnectionsApiModule instance from the global module manager
      final moduleManager = ModuleManager();
      
      final connectionsModule = moduleManager.getModuleByType<ConnectionsApiModule>();
      
      if (connectionsModule == null) {
        throw Exception('ConnectionsApiModule not available - ensure it is initialized');
      }
      
      // Make API call to find game
      final response = await connectionsModule.sendPostRequest(
        '/userauth/cleco/find-room',
        {'room_id': roomId},
      );
      
      // Check if response contains error
      if (response is Map && response.containsKey('error')) {
        throw Exception(response['message'] ?? response['error'] ?? 'Failed to find game');
      }
      
      // Extract game info from response
      final game = response['game'];
      final message = response['message'] ?? 'Game found successfully';
      
      return {
        'success': true,
        'message': message,
        'game': game,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Failed to find game',
        'game': null,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Remove player from specific game in games map and clear current game references
  /// This is called when a player leaves a game (after timer expires)
  /// Only clears game state, not websocket state (websocket module handles that)
  static void removePlayerFromGame({required String gameId}) {
    try {
      _logger.info('🧹 ClecoGameHelpers: Removing player from game $gameId', isOn: LOGGING_SWITCH);
      
      final clecoState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final games = Map<String, dynamic>.from(clecoState['games'] as Map<String, dynamic>? ?? {});
      
      // Remove the specific game from games map
      if (games.containsKey(gameId)) {
        games.remove(gameId);
        _logger.info('🧹 ClecoGameHelpers: Removed game $gameId from games map', isOn: LOGGING_SWITCH);
      }
      
      // Clear currentGameId if it matches the game we're leaving
      final currentGameId = clecoState['currentGameId']?.toString() ?? '';
      final shouldClearCurrentGameId = currentGameId == gameId;
      
      // Update state to remove game and clear current game references
      // This will trigger widget updates through StateManager
      final updates = <String, dynamic>{
        'games': games,
      };
      
      if (shouldClearCurrentGameId) {
        updates['currentGameId'] = '';
        updates['currentRoomId'] = '';
        updates['isInRoom'] = false;
        updates['isRoomOwner'] = false;
        updates['isGameActive'] = false;
        updates['gamePhase'] = 'waiting';
        updates['gameStatus'] = 'inactive';
        
        // Clear widget-specific state slices
        updates['discardPile'] = <Map<String, dynamic>>[];
        updates['drawPileCount'] = 0;
        updates['discardPileCount'] = 0;
        updates['turn_events'] = <Map<String, dynamic>>[];
        
        // Clear round information
        updates['roundNumber'] = 0;
        updates['currentPlayer'] = null;
        updates['currentPlayerStatus'] = '';
        updates['roundStatus'] = '';
        
        _logger.info('🧹 ClecoGameHelpers: Cleared current game references', isOn: LOGGING_SWITCH);
      }
      
      // Update state (this triggers widget rebuilds)
      _stateUpdater.updateState(updates);
      
      _logger.info('✅ ClecoGameHelpers: Player removed from game $gameId, widgets will update', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ ClecoGameHelpers: Error removing player from game: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Clear all game state when leaving game play screen
  /// This should be called when navigating away from the game play screen
  /// to prevent stale data from affecting new games
  static void clearGameState({String? gameId}) {
    try {
      _logger.info('🧹 ClecoGameHelpers: Clearing game state${gameId != null ? " for game $gameId" : ""}', isOn: LOGGING_SWITCH);
      
      // Clear all game-related state
      _stateUpdater.updateState({
        // Clear game identifiers
        'currentGameId': '',
        'currentRoomId': '',
        
        // Clear games map
        'games': <String, dynamic>{},
        
        // Clear game phase and status
        'gamePhase': 'waiting',
        'gameStatus': 'inactive',
        'isGameActive': false,
        'isInRoom': false,
        'isRoomOwner': false,
        
        // Clear round information
        'roundNumber': 0,
        'currentPlayer': null,
        'currentPlayerStatus': '',
        'roundStatus': '',
        
        // Clear widget-specific state slices
        'discardPile': <Map<String, dynamic>>[],
        'drawPileCount': 0,
        'discardPileCount': 0,
        
        // Clear turn events and animation data
        'turn_events': <Map<String, dynamic>>[],
        
        // Clear messages state (including modal state)
        'messages': {
          'session': <Map<String, dynamic>>[],
          'rooms': <String, List<Map<String, dynamic>>>{},
          'isVisible': false,
          'title': '',
          'content': '',
          'type': 'info',
          'showCloseButton': false,
          'autoClose': false,
          'autoCloseDelay': 3000,
        },
        
        // Clear instructions state
        'instructions': {
          'isVisible': false,
          'title': '',
          'content': '',
          'key': '',
          'dontShowAgain': <String, bool>{},
        },
        
        // Clear joined games list
        'joinedGames': <Map<String, dynamic>>[],
        'totalJoinedGames': 0,
        'joinedGamesTimestamp': '',
      });
      
      _logger.info('✅ ClecoGameHelpers: Game state cleared successfully', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ ClecoGameHelpers: Error clearing game state: $e', isOn: LOGGING_SWITCH);
    }
  }
    
}
