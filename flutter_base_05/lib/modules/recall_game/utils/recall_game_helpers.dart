import '../../../core/managers/module_manager.dart';
import '../../../modules/connections_api_module/connections_api_module.dart';
import '../../../core/managers/websockets/websocket_manager.dart';
import '../managers/validated_event_emitter.dart';
import '../managers/recall_game_state_updater.dart';

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
        '/userauth/recall/find-room',
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
    
}
