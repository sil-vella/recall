import '../../recall_game/practice_game_round.dart';
import '../services/game_registry.dart';
import '../services/game_state_store.dart';
import '../../../server/room_manager.dart';
import '../../../server/websocket_server.dart';
import '../../../utils/server_logger.dart';

const bool LOGGING_SWITCH = true;

/// Coordinates WS game events to the PracticeGameRound logic per room.
class GameEventCoordinator {
  final RoomManager roomManager;
  final WebSocketServer server;
  final _registry = GameRegistry.instance;
  final _store = GameStateStore.instance;
  final ServerLogger _logger = ServerLogger();

  GameEventCoordinator(this.roomManager, this.server);

  /// Handle a unified game event from a session
  Future<void> handle(String sessionId, String event, Map<String, dynamic> data) async {
    final roomId = roomManager.getRoomForSession(sessionId);
    if (roomId == null) {
      server.sendToSession(sessionId, {
        'event': 'error',
        'message': 'Not in a room',
      });
      return;
    }

    // Get or create the game round for this room
    final round = _registry.getOrCreate(roomId, server);

    try {
      switch (event) {
        case 'start_match':
          await _handleStartMatch(roomId, round, data);
          break;
        case 'draw_card':
          await round.handleDrawCard((data['source'] as String?) ?? 'deck');
          break;
        case 'play_card':
          final cardId = (data['card_id'] as String?) ?? (data['cardId'] as String?);
          if (cardId != null && cardId.isNotEmpty) {
            await round.handlePlayCard(cardId);
          }
          break;
        case 'same_rank_play':
          final playerId = (data['player_id'] as String?) ?? (data['playerId'] as String?);
          final cardId = (data['card_id'] as String?) ?? (data['cardId'] as String?);
          if (playerId != null && cardId != null && cardId.isNotEmpty) {
            await round.handleSameRankPlay(playerId, cardId);
          }
          break;
        case 'queen_peek':
        case 'jack_swap':
          // Placeholders: these are handled within PracticeGameRound through special card window
          // When front-end triggers structured events, wire here accordingly
          break;
        default:
          // Acknowledge unknown-but-allowed for forward-compat
          break;
      }

      // Acknowledge success
      server.sendToSession(sessionId, {
        'event': '${event}_acknowledged',
        'room_id': roomId,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      _logger.error('GameEventCoordinator: error on $event -> $e', isOn: LOGGING_SWITCH);
      server.sendToSession(sessionId, {
        'event': '${event}_error',
        'room_id': roomId,
        'message': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Initialize match: create base state, players (human/computers), deck, then initialize round
  Future<void> _handleStartMatch(String roomId, PracticeGameRound round, Map<String, dynamic> data) async {
    // Basic initial state structure compatible with PracticeGameRound
    final stateRoot = _store.getState(roomId);
    final gameState = <String, dynamic>{
      'gameId': roomId,
      'gameName': 'Recall Game $roomId',
      'players': <Map<String, dynamic>>[],
      'discardPile': <Map<String, dynamic>>[],
      'drawPile': <String>[],
      'gameType': 'multiplayer',
      'isGameActive': true,
      // Use 'phase' key to align with frontend mapping
      'phase': 'setup',
    };
    stateRoot['game_state'] = gameState;
    _store.mergeRoot(roomId, stateRoot);

    // Let PracticeGameRound run its setup pipeline (dealing, etc.) via existing methods
    // Expectation: PracticeGameRound reads/writes through callback implementation
    round.initializeRound();
  }
}


