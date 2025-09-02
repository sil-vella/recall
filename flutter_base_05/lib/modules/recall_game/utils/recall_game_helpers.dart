import '../../../core/managers/module_manager.dart';
import '../../../modules/connections_api_module/connections_api_module.dart';
import '../../../tools/logging/logger.dart';
import '../managers/validated_event_emitter.dart';
import '../managers/validated_state_manager.dart';

/// Convenient helper methods for recall game operations
/// Provides type-safe, validated methods for common game actions
class RecallGameHelpers {
  static final Logger _log = Logger();
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

  /// Fetch available games from the backend API
  static Future<Map<String, dynamic>> fetchAvailableGames() async {
    _log.info('🎮 [RecallGameHelpers.fetchAvailableGames] Fetching available games from API');
    
    try {
      // Get the ConnectionsApiModule instance from the global module manager
      // Note: This requires the module to be initialized in the app context
      final moduleManager = ModuleManager();
      _log.info('🎮 [RecallGameHelpers.fetchAvailableGames] ModuleManager instance: $moduleManager');
      
      final connectionsModule = moduleManager.getModuleByType<ConnectionsApiModule>();
      _log.info('🎮 [RecallGameHelpers.fetchAvailableGames] ConnectionsApiModule: $connectionsModule');
      
      if (connectionsModule == null) {
        _log.error('❌ [RecallGameHelpers.fetchAvailableGames] ConnectionsApiModule not available');
        throw Exception('ConnectionsApiModule not available - ensure it is initialized');
      }
      
      _log.info('🎮 [RecallGameHelpers.fetchAvailableGames] ConnectionsApiModule baseUrl: ${connectionsModule.baseUrl}');

      _log.info('🎮 [RecallGameHelpers.fetchAvailableGames] Making API call to /userauth/recall/get-available-games');
      _log.info('🎮 [RecallGameHelpers.fetchAvailableGames] Full URL will be: ${connectionsModule.baseUrl}/userauth/recall/get-available-games');
      
      // Make API call to fetch available games
      // The endpoint is JWT protected, but AuthInterceptor handles tokens automatically
      final response = await connectionsModule.sendGetRequest('/userauth/recall/get-available-games');
      
      // Check if response contains error
      if (response is Map && response.containsKey('error')) {
        throw Exception(response['message'] ?? response['error'] ?? 'Failed to fetch games');
      }
      
      // Extract games from response
      final games = response['games'] ?? [];
      final message = response['message'] ?? 'Games fetched successfully';
      
      _log.info('🎮 [RecallGameHelpers.fetchAvailableGames] Successfully fetched ${games.length} games');
      
      return {
        'success': true,
        'games': games,
        'message': message,
        'count': games.length,
      };
      
    } catch (e) {
      _log.error('❌ [RecallGameHelpers.fetchAvailableGames] Error: $e');
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

  /// Find a specific game by room ID via API call
  static Future<Map<String, dynamic>> findRoom(String roomId) async {
    _log.info('🎮 [RecallGameHelpers.findRoom] Finding game: $roomId');
    
    try {
      // Get the ConnectionsApiModule instance from the global module manager
      final moduleManager = ModuleManager();
      _log.info('🎮 [RecallGameHelpers.findRoom] ModuleManager instance: $moduleManager');
      
      final connectionsModule = moduleManager.getModuleByType<ConnectionsApiModule>();
      _log.info('🎮 [RecallGameHelpers.findRoom] ConnectionsApiModule: $connectionsModule');
      
      if (connectionsModule == null) {
        _log.error('❌ [RecallGameHelpers.findRoom] ConnectionsApiModule not available');
        throw Exception('ConnectionsApiModule not available - ensure it is initialized');
      }
      
      _log.info('🎮 [RecallGameHelpers.findRoom] Making API call to /userauth/recall/find-room');
      
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
      
      _log.info('✅ [RecallGameHelpers.findRoom] Game found: $roomId');
      
      return {
        'success': true,
        'message': message,
        'game': game,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      _log.error('❌ [RecallGameHelpers.findRoom] Error: $e');
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
