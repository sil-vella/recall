import '../practice_game_round.dart';
import '../game_state_callback.dart';
import 'game_state_store.dart';
import '../../../server/websocket_server.dart';
import '../../../utils/server_logger.dart';

const bool LOGGING_SWITCH = true;

/// Holds active PracticeGameRound instances per room and wires their callbacks
/// to the WebSocket server through ServerGameStateCallback.
class GameRegistry {
  static final GameRegistry instance = GameRegistry._internal();
  final Map<String, PracticeGameRound> _roomIdToRound = {};
  final ServerLogger _logger = ServerLogger();

  GameRegistry._internal();

  PracticeGameRound getOrCreate(String roomId, WebSocketServer server) {
    return _roomIdToRound.putIfAbsent(roomId, () {
      final callback = _ServerGameStateCallbackImpl(roomId, server);
      final round = PracticeGameRound(callback, roomId);
      _logger.info('GameRegistry: Created PracticeGameRound for $roomId', isOn: LOGGING_SWITCH);
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
  final ServerLogger _logger = ServerLogger();

  _ServerGameStateCallbackImpl(this.roomId, this.server);

  @override
  void onPlayerStatusChanged(String status, {String? playerId, bool updateMainState = true, bool triggerInstructions = false}) {
    final state = _store.getGameState(roomId);
    final players = (state['players'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
    for (final p in players) {
      if (playerId == null || p['id'] == playerId) {
        p['status'] = status;
      }
    }
    if (updateMainState) {
      // mirror Flutter practice behavior
      state['playerStatus'] = status;
    }
    _store.setGameState(roomId, state);
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
    // Merge into root to preserve structure compatible with Flutter
    _store.mergeRoot(roomId, updates);
    server.broadcastToRoom(roomId, {
      'event': 'game_state_updated',
      'room_id': roomId,
      'updates': updates,
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
  Map<String, dynamic> get currentGamesMap => _store.getState(roomId);
}


