import '../../utils/platform/shared_imports.dart';
import '../../../cleco_game/backend_core/shared_logic/cleco_game_round.dart';
import '../shared_logic/game_state_callback.dart';
import '../utils/state_queue_validator.dart';
import 'game_state_store.dart';

const bool LOGGING_SWITCH = false;

/// Holds active ClecoGameRound instances per room and wires their callbacks
/// to the WebSocket server through ServerGameStateCallback.
class GameRegistry {
  static final GameRegistry instance = GameRegistry._internal();
  final Map<String, ClecoGameRound> _roomIdToRound = {};
  final Logger _logger = Logger();

  GameRegistry._internal();

  ClecoGameRound getOrCreate(String roomId, WebSocketServer server) {
    return _roomIdToRound.putIfAbsent(roomId, () {
      final callback = ServerGameStateCallbackImpl(roomId, server);
      final round = ClecoGameRound(callback, roomId);
      _logger.info('GameRegistry: Created ClecoGameRound for $roomId', isOn: LOGGING_SWITCH);
      return round;
    });
  }

  void dispose(String roomId) {
    _roomIdToRound.remove(roomId);
    GameStateStore.instance.clear(roomId);
    _logger.info('GameRegistry: Disposed game for $roomId', isOn: LOGGING_SWITCH);
  }
}

/// Server implementation of GameStateCallback for backend-authoritative play.
class ServerGameStateCallbackImpl implements GameStateCallback {
  final String roomId;
  final WebSocketServer server;
  final _store = GameStateStore.instance;
  final Logger _logger = Logger();
  final StateQueueValidator _validator = StateQueueValidator.instance;

  ServerGameStateCallbackImpl(this.roomId, this.server) {
    // Initialize state queue validator with logger callback
    _validator.setLogCallback((String message, {bool isError = false}) {
      if (isError) {
        _logger.error(message, isOn: LOGGING_SWITCH);
      } else {
        _logger.info(message, isOn: LOGGING_SWITCH);
      }
    });
    
    // Set update handler to apply validated updates to GameStateStore
    _validator.setUpdateHandler((Map<String, dynamic> validatedUpdates) {
      _applyValidatedUpdates(validatedUpdates);
    });
  }

  @override
  void onGameStateChanged(Map<String, dynamic> updates) {
    // Log turn_events if present in updates
    if (updates.containsKey('turn_events')) {
      final turnEvents = updates['turn_events'] as List<dynamic>? ?? [];
      _logger.info('🔍 TURN_EVENTS DEBUG - onGameStateChanged received turn_events: ${turnEvents.length} events', isOn: LOGGING_SWITCH);
      _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${turnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}', isOn: LOGGING_SWITCH);
    } else {
      _logger.info('🔍 TURN_EVENTS DEBUG - onGameStateChanged received NO turn_events in updates. Keys: ${updates.keys.toList()}', isOn: LOGGING_SWITCH);
    }
    
    // Use StateQueueValidator to validate and queue the update
    // The validator will call our update handler with validated updates
    _validator.enqueueUpdate(updates);
  }

  @override
  void sendGameStateToPlayer(String playerId, Map<String, dynamic> updates) {
    // Validate and apply updates to state store (same as onGameStateChanged)
    // But send only to the specific player instead of broadcasting
    _logger.info('📤 sendGameStateToPlayer: Sending state update to player $playerId', isOn: LOGGING_SWITCH);
    
    try {
      // Validate updates using the same validator (direct validation, not queued)
      final validatedUpdates = _validator.validateUpdate(updates);
      
      // Apply validated updates to state store
      _store.mergeRoot(roomId, validatedUpdates);
      
      // Read the full state after merge
      final state = _store.getState(roomId);
      final gameState = state['game_state'] as Map<String, dynamic>? ?? {};
      
      // Extract turn_events from root state
      final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
      
      // Handle phase normalization (same as _applyValidatedUpdates)
      if (validatedUpdates.containsKey('gamePhase')) {
        final phase = validatedUpdates['gamePhase']?.toString();
        if (phase != null) {
          String normalizedPhase = phase;
          if (phase == 'special_play_window') {
            normalizedPhase = 'special_play_window';
          } else if (phase == 'same_rank_window') {
            normalizedPhase = 'same_rank_window';
          } else if (phase == 'player_turn') {
            normalizedPhase = 'playing';
          } else if (phase == 'ending_round') {
            normalizedPhase = 'ending_round';
          } else if (phase == 'ending_turn') {
            normalizedPhase = 'ending_turn';
          }
          gameState['phase'] = normalizedPhase;
        }
      }
      
      // Ensure phase key and playerCount
      gameState['phase'] = gameState['phase'] ?? 'playing';
      gameState['playerCount'] = (gameState['players'] as List<dynamic>? ?? []).length;
      
      // Owner info for gating
      final ownerId = server.getRoomOwner(roomId);
      
      // Send to single player (playerId = sessionId in this system)
      server.sendToSession(playerId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gameState,
        'turn_events': turnEvents,
        if (ownerId != null) 'owner_id': ownerId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _logger.info('✅ sendGameStateToPlayer: Sent state update to player $playerId', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ sendGameStateToPlayer: Error sending state update to player $playerId: $e', isOn: LOGGING_SWITCH);
    }
  }

  @override
  void broadcastGameStateExcept(String excludePlayerId, Map<String, dynamic> updates) {
    // Validate and apply updates to state store (same as onGameStateChanged)
    // But broadcast to all players except the excluded one
    _logger.info('📤 broadcastGameStateExcept: Broadcasting state update to all except player $excludePlayerId', isOn: LOGGING_SWITCH);
    
    try {
      // Validate updates using the same validator (direct validation, not queued)
      final validatedUpdates = _validator.validateUpdate(updates);
      
      // Apply validated updates to state store
      _store.mergeRoot(roomId, validatedUpdates);
      
      // Read the full state after merge
      final state = _store.getState(roomId);
      final gameState = state['game_state'] as Map<String, dynamic>? ?? {};
      
      // Extract turn_events from root state
      final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
      
      // Handle phase normalization (same as _applyValidatedUpdates)
      if (validatedUpdates.containsKey('gamePhase')) {
        final phase = validatedUpdates['gamePhase']?.toString();
        if (phase != null) {
          String normalizedPhase = phase;
          if (phase == 'special_play_window') {
            normalizedPhase = 'special_play_window';
          } else if (phase == 'same_rank_window') {
            normalizedPhase = 'same_rank_window';
          } else if (phase == 'player_turn') {
            normalizedPhase = 'playing';
          } else if (phase == 'ending_round') {
            normalizedPhase = 'ending_round';
          } else if (phase == 'ending_turn') {
            normalizedPhase = 'ending_turn';
          } else if (phase == 'game_ended') {
            normalizedPhase = 'game_ended'; // Pass through game_ended as-is
          }
          gameState['phase'] = normalizedPhase;
        }
      }
      
      // Ensure phase key and playerCount
      gameState['phase'] = gameState['phase'] ?? 'playing';
      gameState['playerCount'] = (gameState['players'] as List<dynamic>? ?? []).length;
      
      // Extract winners from validatedUpdates (if present) - needed for game end notification
      final winners = validatedUpdates['winners'] as List<dynamic>?;
      
      // Owner info for gating
      final ownerId = server.getRoomOwner(roomId);
      
      // Broadcast to all players except the excluded one (excludePlayerId = sessionId in this system)
      server.broadcastToRoomExcept(roomId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gameState,
        'turn_events': turnEvents,
        if (winners != null) 'winners': winners, // Include winners list for game end notification
        if (ownerId != null) 'owner_id': ownerId,
        'timestamp': DateTime.now().toIso8601String(),
      }, excludePlayerId);
      
      _logger.info('✅ broadcastGameStateExcept: Broadcasted state update to all except player $excludePlayerId', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ broadcastGameStateExcept: Error broadcasting state update: $e', isOn: LOGGING_SWITCH);
    }
  }
  
  /// Apply validated updates to GameStateStore and broadcast
  /// This is called by StateQueueValidator after validation
  void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
    // Log turn_events if present in validated updates
    if (validatedUpdates.containsKey('turn_events')) {
      final turnEventsInUpdates = validatedUpdates['turn_events'] as List<dynamic>? ?? [];
      _logger.info('🔍 TURN_EVENTS DEBUG - _applyValidatedUpdates received turn_events in validatedUpdates: ${turnEventsInUpdates.length} events', isOn: LOGGING_SWITCH);
      _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${turnEventsInUpdates.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}', isOn: LOGGING_SWITCH);
    } else {
      _logger.info('🔍 TURN_EVENTS DEBUG - _applyValidatedUpdates received NO turn_events in validatedUpdates. Keys: ${validatedUpdates.keys.toList()}', isOn: LOGGING_SWITCH);
    }
    
    // Merge into state root
    _store.mergeRoot(roomId, validatedUpdates);
    // Read the full state after merge
    final state = _store.getState(roomId);
    final gameState = state['game_state'] as Map<String, dynamic>? ?? {};
    
    // Extract turn_events from root state (they're stored at root level, not in game_state)
    final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
    _logger.info('🔍 TURN_EVENTS DEBUG - _applyValidatedUpdates extracted turn_events from root state: ${turnEvents.length} events', isOn: LOGGING_SWITCH);
    _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${turnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}', isOn: LOGGING_SWITCH);
    
    // CRITICAL: If gamePhase is in updates, copy it to game_state['phase'] for client broadcast
    // Frontend expects gamePhase in game_state['phase'], not at root level
    if (validatedUpdates.containsKey('gamePhase')) {
      final phase = validatedUpdates['gamePhase']?.toString();
      if (phase != null) {
        // Normalize phase names to match frontend expectations
        // Map Dart cleco mode phase names to multiplayer backend phase names
        String normalizedPhase = phase;
        if (phase == 'special_play_window') {
          normalizedPhase = 'special_play_window';
        } else if (phase == 'same_rank_window') {
          normalizedPhase = 'same_rank_window';
        } else if (phase == 'player_turn') {
          normalizedPhase = 'playing';
        } else if (phase == 'ending_round') {
          normalizedPhase = 'ending_round';
        } else if (phase == 'ending_turn') {
          normalizedPhase = 'ending_turn';
        } else if (phase == 'game_ended') {
          normalizedPhase = 'game_ended'; // Pass through game_ended as-is
        }
        gameState['phase'] = normalizedPhase;
        _logger.info('GameStateCallback: Copied gamePhase ($phase) to game_state[phase] ($normalizedPhase) for broadcast', isOn: LOGGING_SWITCH);
      }
    }
    // Ensure phase key and playerCount
    gameState['phase'] = gameState['phase'] ?? 'playing';
    gameState['playerCount'] = (gameState['players'] as List<dynamic>? ?? []).length;
    
    // Extract winners from validatedUpdates (if present) - needed for game end notification
    final winners = validatedUpdates['winners'] as List<dynamic>?;
    if (winners != null) {
      _logger.info('GameStateCallback: Including winners list in broadcast: ${winners.length} winner(s)', isOn: LOGGING_SWITCH);
    }
    
    // Owner info for gating
    final ownerId = server.getRoomOwner(roomId);
    _logger.info('🔍 TURN_EVENTS DEBUG - Broadcasting game_state_updated with ${turnEvents.length} turn_events', isOn: LOGGING_SWITCH);
    _logger.info('🔍 TURN_EVENTS DEBUG - Turn events in broadcast: ${turnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}', isOn: LOGGING_SWITCH);
    
    server.broadcastToRoom(roomId, {
      'event': 'game_state_updated',
      'game_id': roomId,
      'game_state': gameState,
      'turn_events': turnEvents, // Include turn_events for animations
      if (winners != null) 'winners': winners, // Include winners list for game end notification
      if (ownerId != null) 'owner_id': ownerId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  void onDiscardPileChanged() {
    final gameState = _store.getGameState(roomId);
    final discardPile = gameState['discardPile'];
    server.broadcastToRoom(roomId, {
      'event': 'discard_pile_updated',
      'room_id': roomId,
      'discard_pile': discardPile,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  void onActionError(String message, {Map<String, dynamic>? data}) {
    server.broadcastToRoom(roomId, {
      'event': 'action_error',
      'room_id': roomId,
      'message': message,
      'data': data ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Map<String, dynamic>? getCardById(Map<String, dynamic> gameState, String cardId) {
    return _store.getCardById(roomId, cardId);
  }

  @override
  Map<String, dynamic> getCurrentGameState() {
    return _store.getGameState(roomId);
  }

  @override
  Map<String, dynamic> get currentGamesMap {
    // Return state in Flutter format: {gameId: {'gameData': {'game_state': ...}}}
    // This matches the format expected by handlePlayCard in cleco_game_round.dart
    final state = _store.getState(roomId);
    final gameState = state['game_state'] as Map<String, dynamic>? ?? {};
    
    return {
      roomId: {
        'gameData': {
          'game_id': roomId,
          'game_state': gameState,
          'owner_id': server.getRoomOwner(roomId),
        },
      },
    };
  }

  void saveCardPositionsAsPrevious() {
    // No-op for backend - card position tracking is handled on the frontend
  }

  @override
  List<Map<String, dynamic>> getCurrentTurnEvents() {
    final state = _store.getState(roomId);
    final currentTurnEvents = state['turn_events'] as List<dynamic>? ?? [];
    
    // Return a copy of the current events
    return List<Map<String, dynamic>>.from(
      currentTurnEvents.map((e) => e as Map<String, dynamic>)
    );
  }

  @override
  Map<String, dynamic>? getMainStateCurrentPlayer() {
    final state = _store.getState(roomId);
    return state['currentPlayer'] as Map<String, dynamic>?;
  }

  @override
  Map<String, dynamic> getTimerConfig() {
    // Get turnTimeLimit from room config
    final roomInfo = server.getRoomInfo(roomId);
    final turnTimeLimit = roomInfo?.turnTimeLimit ?? 30;
    
    // Get showInstructions from game state (default to false if not found)
    final gameState = _store.getGameState(roomId);
    final showInstructions = gameState['showInstructions'] as bool? ?? false;
    
    return {
      'turnTimeLimit': turnTimeLimit,
      'showInstructions': showInstructions,
    };
  }

  @override
  void triggerLeaveRoom(String playerId) {
    // Only trigger for multiplayer matches (room_*), not practice (practice_room_*)
    if (!roomId.startsWith('room_')) {
      _logger.info('GameStateCallback: Skipping auto-leave for non-multiplayer room $roomId (player $playerId)', isOn: LOGGING_SWITCH);
      return;
    }
    
    _logger.info('GameStateCallback: Triggering auto-leave for player $playerId in room $roomId (2 missed actions)', isOn: LOGGING_SWITCH);
    
    try {
      // Get userId from session (playerId = sessionId in this system)
      final userId = server.getUserIdForSession(playerId) ?? playerId;
      
      // Trigger the leave_room hook through the server
      // This will call the _onLeaveRoom handler in ClecoGameModule
      server.triggerHook('leave_room', data: {
        'room_id': roomId,
        'session_id': playerId, // playerId = sessionId in this system
        'user_id': userId,
        'left_at': DateTime.now().toIso8601String(),
      });
      
      _logger.info('GameStateCallback: Successfully triggered leave_room hook for player $playerId', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('GameStateCallback: Error triggering leave room for player $playerId: $e', isOn: LOGGING_SWITCH);
    }
  }
}


