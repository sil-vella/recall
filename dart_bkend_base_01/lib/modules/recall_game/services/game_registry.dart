import '../shared_logic/recall_game_round.dart';
import '../shared_logic/game_state_callback.dart';
import '../utils/state_queue_validator.dart';
import 'game_state_store.dart';
import '../../../server/websocket_server.dart';
import '../../../utils/server_logger.dart';

const bool LOGGING_SWITCH = false;

/// Holds active RecallGameRound instances per room and wires their callbacks
/// to the WebSocket server through ServerGameStateCallback.
class GameRegistry {
  static final GameRegistry instance = GameRegistry._internal();
  final Map<String, RecallGameRound> _roomIdToRound = {};
  final Logger _logger = Logger();

  GameRegistry._internal();

  RecallGameRound getOrCreate(String roomId, WebSocketServer server) {
    return _roomIdToRound.putIfAbsent(roomId, () {
      final callback = _ServerGameStateCallbackImpl(roomId, server);
      final round = RecallGameRound(callback, roomId);
      _logger.info('GameRegistry: Created RecallGameRound for $roomId', isOn: LOGGING_SWITCH);
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
class _ServerGameStateCallbackImpl implements GameStateCallback {
  final String roomId;
  final WebSocketServer server;
  final _store = GameStateStore.instance;
  final Logger _logger = Logger();
  final StateQueueValidator _validator = StateQueueValidator.instance;

  _ServerGameStateCallbackImpl(this.roomId, this.server) {
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
  void onPlayerStatusChanged(String status, {String? playerId, bool updateMainState = true, bool triggerInstructions = false, Map<String, dynamic>? gamesMap}) {
    final state = _store.getGameState(roomId);
    final players = (state['players'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
    for (final p in players) {
      if (playerId == null || p['id'] == playerId) {
        p['status'] = status;
      }
    }
    if (updateMainState) {
      // mirror Flutter recall behavior
      state['playerStatus'] = status;
    }
    _store.setGameState(roomId, state);
    
    // Also broadcast full game_state_updated to ensure currentPlayer is included
    // This is needed when starting a new turn and currentPlayer changes
    final ownerId = server.getRoomOwner(roomId);
    server.broadcastToRoom(roomId, {
      'event': 'game_state_updated',
      'game_id': roomId,
      'game_state': state, // Include full state with currentPlayer
      if (ownerId != null) 'owner_id': ownerId,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // Also send player_status_updated for backward compatibility
    server.broadcastToRoom(roomId, {
      'event': 'player_status_updated',
      'room_id': roomId,
      'player_id': playerId,
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  void onGameStateChanged(Map<String, dynamic> updates) {
    // Use StateQueueValidator to validate and queue the update
    // The validator will call our update handler with validated updates
    _validator.enqueueUpdate(updates);
  }
  
  /// Apply validated updates to GameStateStore and broadcast
  /// This is called by StateQueueValidator after validation
  void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
    // Merge into state root
    _store.mergeRoot(roomId, validatedUpdates);
    // Read the full game_state after merge for snapshot
    final state = _store.getState(roomId);
    final gameState = state['game_state'] as Map<String, dynamic>? ?? {};
    // CRITICAL: If gamePhase is in updates, copy it to game_state['phase'] for client broadcast
    // Frontend expects gamePhase in game_state['phase'], not at root level
    if (validatedUpdates.containsKey('gamePhase')) {
      final phase = validatedUpdates['gamePhase']?.toString();
      if (phase != null) {
        // Normalize phase names to match frontend expectations
        // Map Dart recall mode phase names to multiplayer backend phase names
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
        _logger.info('GameStateCallback: Copied gamePhase ($phase) to game_state[phase] ($normalizedPhase) for broadcast', isOn: LOGGING_SWITCH);
      }
    }
    // Ensure phase key and playerCount
    gameState['phase'] = gameState['phase'] ?? 'playing';
    gameState['playerCount'] = (gameState['players'] as List<dynamic>? ?? []).length;
    // Owner info for gating
    final ownerId = server.getRoomOwner(roomId);
    server.broadcastToRoom(roomId, {
      'event': 'game_state_updated',
      'game_id': roomId,
      'game_state': gameState,
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
    // This matches the format expected by handlePlayCard in recall_game_round.dart
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
}


