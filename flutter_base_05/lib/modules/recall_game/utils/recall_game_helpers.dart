import 'validated_event_emitter.dart';
import 'validated_state_updater.dart';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/websockets/websocket_manager.dart';
import '../../../tools/logging/logger.dart';

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
    
}
