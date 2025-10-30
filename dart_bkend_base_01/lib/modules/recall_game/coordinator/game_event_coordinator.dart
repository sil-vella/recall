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
    // Prepare initial state compatible with PracticeGameRound
    final stateRoot = _store.getState(roomId);
    final current = Map<String, dynamic>.from(stateRoot['game_state'] as Map<String, dynamic>? ?? {});

    // Start from existing players (creator and any joiners already added via hooks)
    final players = List<Map<String, dynamic>>.from(
      (current['players'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );

    // Determine target player count (mimic Python: at least minPlayers)
    // Fallbacks if room metadata missing
    final roomInfo = roomManager.getRoomInfo(roomId);
    final minPlayers = roomInfo?.minPlayers ?? (data['min_players'] as int? ?? 2);
    final maxPlayers = roomInfo?.maxSize ?? (data['max_players'] as int? ?? 4);

    // Auto-create computer players until minPlayers is reached (cap at maxPlayers)
    int needed = minPlayers - players.length;
    if (needed < 0) needed = 0;
    int cpuIndexBase = 1;
    // Find next CPU index not used
    final existingNames = players.map((p) => (p['name'] ?? '').toString()).toSet();
    while (needed > 0 && players.length < maxPlayers) {
      String name;
      do {
        name = 'CPU ${cpuIndexBase++}';
      } while (existingNames.contains(name));
      final cpuId = 'cpu_${DateTime.now().microsecondsSinceEpoch}_$cpuIndexBase';
      players.add({
        'id': cpuId,
        'name': name,
        'isHuman': false,
        'status': 'waiting',
        'hand': <Map<String, dynamic>>[],
        'visible_cards': <Map<String, dynamic>>[],
        'points': 0,
        'known_cards': <String, dynamic>{},
        'collection_rank_cards': <String>[],
      });
      needed--;
    }

    // Build updated game_state
    final gameState = <String, dynamic>{
      'gameId': roomId,
      'gameName': 'Recall Game $roomId',
      'players': players,
      'discardPile': <Map<String, dynamic>>[],
      'drawPile': <String>[],
      'gameType': 'multiplayer',
      'isGameActive': true,
      'phase': 'setup',
      'playerCount': players.length,
      'maxPlayers': maxPlayers,
      'minPlayers': minPlayers,
    };

    stateRoot['game_state'] = gameState;
    _store.mergeRoot(roomId, stateRoot);

    // Broadcast initial setup snapshot before initialization
    server.broadcastToRoom(roomId, {
      'event': 'game_state_updated',
      'game_id': roomId,
      'game_state': gameState,
      'owner_id': server.getRoomOwner(roomId),
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Run round setup (dealing, etc.) which will continue to broadcast updates via callbacks
    round.initializeRound();
  }
}


