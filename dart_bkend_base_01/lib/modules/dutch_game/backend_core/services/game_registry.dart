import 'dart:convert';
import 'dart:async';

import '../../utils/platform/shared_imports.dart';
import '../../../dutch_game/backend_core/shared_logic/dutch_game_round.dart';
import '../shared_logic/game_state_callback.dart';
import 'game_state_store.dart';

String _deriveWireCurrentPlayerStatus(Map<String, dynamic> gameState) {
  final cp = gameState['currentPlayer'];
  if (cp is Map<String, dynamic>) {
    final st = cp['status']?.toString().trim();
    if (st != null && st.isNotEmpty) {
      return st;
    }
    final id = cp['id']?.toString();
    if (id != null && id.isNotEmpty) {
      final players = gameState['players'] as List<dynamic>? ?? [];
      for (final p in players) {
        if (p is Map<String, dynamic> && p['id']?.toString() == id) {
          final pst = p['status']?.toString().trim();
          if (pst != null && pst.isNotEmpty) {
            return pst;
          }
          break;
        }
      }
    }
  }
  final phase = gameState['phase']?.toString().trim();
  if (phase != null && phase.isNotEmpty) {
    return phase;
  }
  return 'unknown';
}

/// Holds active DutchGameRound instances per room and wires their callbacks
/// to the WebSocket server through ServerGameStateCallback.
class GameRegistry {
  static final GameRegistry instance = GameRegistry._internal();
  final Map<String, DutchGameRound> _roomIdToRound = {};

  GameRegistry._internal();

  DutchGameRound getOrCreate(String roomId, WebSocketServer server) {
    return _roomIdToRound.putIfAbsent(roomId, () {
      final callback = ServerGameStateCallbackImpl(roomId, server);
      final round = DutchGameRound(callback, roomId);
      
      return round;
    });
  }

  /// Existing round for [roomId], or null if none (e.g. never created or disposed).
  DutchGameRound? getExisting(String roomId) => _roomIdToRound[roomId];

  void dispose(String roomId) {
    final round = _roomIdToRound.remove(roomId);
    round?.dispose();
    GameStateStore.instance.clear(roomId);
    
  }

  /// Clear all rounds (reset to init). Use when clearing all games (e.g. mode switch).
  void clearAll() {
    _roomIdToRound.clear();
    
  }
}

/// Server implementation of GameStateCallback for backend-authoritative play.
class ServerGameStateCallbackImpl implements GameStateCallback {
  final String roomId;
  final WebSocketServer server;
  final _store = GameStateStore.instance;

  static final Map<String, int> _stateVersionByRoom = <String, int>{};
  static final Map<String, String> _lastBroadcastSignatureByRoom = <String, String>{};
  final Map<String, dynamic> _pendingOnChangeUpdates = <String, dynamic>{};
  bool _onChangeFlushScheduled = false;

  int _nextStateVersion() {
    final next = (_stateVersionByRoom[roomId] ?? 0) + 1;
    _stateVersionByRoom[roomId] = next;
    return next;
  }

  String _buildBroadcastSignature({
    required Map<String, dynamic> filteredGameState,
    required List<dynamic> turnEvents,
    required String? ownerId,
    required List<dynamic>? myCardsToPeekFromState,
    required List<dynamic>? cardsToPeekFromState,
    required List<dynamic>? winners,
  }) {
    return jsonEncode(<String, dynamic>{
      'game_state': filteredGameState,
      'turn_events': turnEvents,
      'owner_id': ownerId,
      'myCardsToPeek': myCardsToPeekFromState,
      'cards_to_peek': cardsToPeekFromState,
      'winners': winners,
      'is_random_join': server.getRoomInfo(roomId)?.isRandomJoin == true,
    });
  }

  /// Get all timer values as a map (for UI consumption)
  /// This is the single source of truth for all timer durations
  /// Static method - doesn't require roomId since values are constant
  static Map<String, int> getAllTimerValues() {
    return {
      'initial_peek': 10,
      'drawing_card': 5,
      'playing_card': 13,
      'same_rank_window': 5,
      'queen_peek': 7,
      'jack_swap': 7,
      'peeking': 5,
      'waiting': 0,
      'default': 15,
    };
  }

  ServerGameStateCallbackImpl(this.roomId, this.server) {
    // No-op: state updates are applied directly without queue validation.
  }

  @override
  void onGameStateChanged(Map<String, dynamic> updates) {
    _queueMergedOnGameStateChanged(updates);
  }

  void _queueMergedOnGameStateChanged(Map<String, dynamic> updates) {
    _pendingOnChangeUpdates.addAll(updates);
    if (_onChangeFlushScheduled) return;
    _onChangeFlushScheduled = true;

    scheduleMicrotask(() {
      _onChangeFlushScheduled = false;
      if (_pendingOnChangeUpdates.isEmpty) {
        return;
      }
      final mergedUpdates = Map<String, dynamic>.from(_pendingOnChangeUpdates);
      _pendingOnChangeUpdates.clear();
      _applyValidatedUpdates(mergedUpdates);
    });
  }

  @override
  void sendGameStateToPlayer(String playerId, Map<String, dynamic> updates) {
    
    emitGameStateScoped(
      sharedUpdates: updates,
      onlyPlayerId: playerId,
    );
  }

  @override
  void broadcastGameStateExcept(String excludePlayerId, Map<String, dynamic> updates) {
    
    emitGameStateScoped(
      sharedUpdates: updates,
      excludePlayerId: excludePlayerId,
    );
  }

  @override
  void emitGameAnimation(Map<String, dynamic> payload) {
    try {
      final message = <String, dynamic>{
        'event': 'game_animation',
        'game_id': roomId,
        'timestamp': DateTime.now().toIso8601String(),
        ...payload,
      };
      server.broadcastToRoom(roomId, message);
      
    } catch (e) {
      
    }
  }

  /// Filter gameState to remove fields that shouldn't be sent to frontend
  /// Currently removes originalDeck to reduce payload size
  Map<String, dynamic> _filterGameStateForFrontend(Map<String, dynamic> gameState) {
    final filtered = Map<String, dynamic>.from(gameState);
    filtered.remove('originalDeck');
    return filtered;
  }

  /// [Room.isRandomJoin] — included on every `game_state_updated` so the Flutter client can persist
  /// `gameData.is_random_join` (WS payload did not carry it; `isRandomJoinInProgress` clears too early).
  bool _roomIsRandomJoin() => server.getRoomInfo(roomId)?.isRandomJoin == true;

  Map<String, dynamic> _gameStateUpdatedPayloadBase({
    required Map<String, dynamic> filteredGameState,
    required List<dynamic> turnEvents,
    required int stateVersion,
    String? ownerId,
    List<dynamic>? myCardsToPeekFromState,
    List<dynamic>? cardsToPeekFromState,
    List<dynamic>? winners,
  }) {
    return <String, dynamic>{
      'event': 'game_state_updated',
      'game_id': roomId,
      'game_state': filteredGameState,
      'turn_events': turnEvents,
      'state_version': stateVersion,
      if (filteredGameState['currentPlayer'] != null) 'current_player': filteredGameState['currentPlayer'],
      'current_player_status': _deriveWireCurrentPlayerStatus(filteredGameState),
      if (winners != null) 'winners': winners,
      if (ownerId != null) 'owner_id': ownerId,
      if (myCardsToPeekFromState != null) 'myCardsToPeek': myCardsToPeekFromState,
      if (cardsToPeekFromState != null) 'cards_to_peek': cardsToPeekFromState,
      if (_roomIsRandomJoin()) 'is_random_join': true,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  void _emitPayloadToRoomSessions(
    Map<String, dynamic> basePayload, {
    String? excludePlayerId,
    String? onlyPlayerId,
    String? privatePlayerId,
    Map<String, dynamic>? privateOverlay,
  }) {
    final sessions = server.getSessionsInRoom(roomId);
    String? wsForSeat(String playerSeatId) =>
        server.websocketSessionForGamePlayer(roomId, playerSeatId);

    final String? onlyWs =
        onlyPlayerId == null ? null : wsForSeat(onlyPlayerId);
    final String? excludeWs =
        excludePlayerId == null ? null : wsForSeat(excludePlayerId);
    final String? privateWs =
        privatePlayerId == null ? null : wsForSeat(privatePlayerId);

    for (final sessionId in sessions) {
      if (onlyPlayerId != null) {
        if (onlyWs != null && sessionId != onlyWs) {
          continue;
        }
        if (onlyWs == null) {
          continue;
        }
      }
      if (excludePlayerId != null && excludeWs != null && sessionId == excludeWs) {
        continue;
      }
      if (privatePlayerId != null &&
          privateOverlay != null &&
          privateWs != null &&
          sessionId == privateWs) {
        server.sendToSession(sessionId, <String, dynamic>{
          ...basePayload,
          ...privateOverlay,
        });
      } else {
        server.sendToSession(sessionId, basePayload);
      }
    }
  }

  /// Single-pass emission: shared payload for room + optional private overlay for one session.
  void emitGameStateScoped({
    required Map<String, dynamic> sharedUpdates,
    String? excludePlayerId,
    String? onlyPlayerId,
    String? privatePlayerId,
    Map<String, dynamic>? privateOverlay,
  }) {
    try {
      _store.mergeRoot(roomId, sharedUpdates);
      final state = _store.getState(roomId);
      final gameState = state['game_state'] as Map<String, dynamic>? ?? {};

      if (sharedUpdates.containsKey('gamePhase')) {
        final phase = sharedUpdates['gamePhase']?.toString();
        if (phase != null) {
          gameState['phase'] = phase == 'player_turn' ? 'playing' : phase;
        }
      }
      gameState['phase'] = gameState['phase'] ?? 'playing';
      gameState['playerCount'] =
          (gameState['players'] as List<dynamic>? ?? []).length;

      final filteredGameState = _filterGameStateForFrontend(gameState);
      final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
      final ownerId = server.getRoomOwner(roomId);
      final basePayload = _gameStateUpdatedPayloadBase(
        filteredGameState: filteredGameState,
        turnEvents: turnEvents,
        stateVersion: _nextStateVersion(),
        ownerId: ownerId,
        myCardsToPeekFromState: state['myCardsToPeek'] as List<dynamic>?,
        cardsToPeekFromState: state['cards_to_peek'] as List<dynamic>?,
        winners: sharedUpdates['winners'] as List<dynamic>?,
      );
      _emitPayloadToRoomSessions(
        basePayload,
        excludePlayerId: excludePlayerId,
        onlyPlayerId: onlyPlayerId,
        privatePlayerId: privatePlayerId,
        privateOverlay: privateOverlay,
      );
    } catch (e) {
      
    }
  }

  /// Broadcast current store state (e.g. after Python [update_game_stats] returns enriched `tournament_data`).
  void _broadcastFullGameStateFromStore() {
    final state = _store.getState(roomId);
    final gameState = Map<String, dynamic>.from(state['game_state'] as Map<String, dynamic>? ?? {});
    gameState['phase'] = gameState['phase'] ?? 'playing';
    gameState['playerCount'] = (gameState['players'] as List<dynamic>? ?? []).length;
    final filteredGameState = _filterGameStateForFrontend(gameState);
    final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
    final myCardsToPeekFromState = state['myCardsToPeek'] as List<dynamic>?;
    final cardsToPeekFromState = state['cards_to_peek'] as List<dynamic>?;
    final ownerId = server.getRoomOwner(roomId);
    final payload = _gameStateUpdatedPayloadBase(
      filteredGameState: filteredGameState,
      turnEvents: turnEvents,
      stateVersion: _nextStateVersion(),
      ownerId: ownerId,
      myCardsToPeekFromState: myCardsToPeekFromState,
      cardsToPeekFromState: cardsToPeekFromState,
      winners: null,
    );
    _emitPayloadToRoomSessions(payload);
  }

  /// Apply updates to GameStateStore and broadcast.
  void _applyValidatedUpdates(Map<String, dynamic> updates) {
    final updateKeys = updates.keys.toSet();
    final isGamesOnlyUpdate =
        updateKeys.isNotEmpty && updateKeys.every((k) => k == 'games');

    // Log turn_events if present in validated updates
    if (updates.containsKey('turn_events')) {
      final turnEventsInUpdates = updates['turn_events'] as List<dynamic>? ?? [];
      
      
    } else {
      
    }
    
    // Merge into state root
    _store.mergeRoot(roomId, updates);
    // Read the full state after merge
    final state = _store.getState(roomId);
    final gameState = state['game_state'] as Map<String, dynamic>? ?? {};
    
    // Extract turn_events from root state (they're stored at root level, not in game_state)
    final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
    
    
    
    // CRITICAL: If gamePhase is in updates, copy it to game_state['phase'] for client broadcast
    // Frontend expects gamePhase in game_state['phase'], not at root level
    if (updates.containsKey('gamePhase')) {
      final phase = updates['gamePhase']?.toString();
      if (phase != null) {
        // Normalize phase names to match frontend expectations
        // Map Dart dutch mode phase names to multiplayer backend phase names
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
    
    // Filter gameState to remove fields that shouldn't be sent to frontend
    final filteredGameState = _filterGameStateForFrontend(gameState);
    
    // Extract winners from validatedUpdates (if present) - needed for game end notification
    final winners = updates['winners'] as List<dynamic>?;
    if (winners != null) {
      
    }

    final myCardsToPeekFromState = state['myCardsToPeek'] as List<dynamic>?;
    final cardsToPeekFromState = state['cards_to_peek'] as List<dynamic>?;

    // Owner info for gating
    final ownerId = server.getRoomOwner(roomId);
    
    
    
    // Games-only updates usually follow a richer merge; start_match writes `game_state` to the
    // store first then emits only `games` — skipping here left clients on waiting_for_players
    // until a later event (e.g. first draw). Always broadcast when the live phase is initial_peek.
    if (isGamesOnlyUpdate) {
      final phaseForBroadcast = gameState['phase']?.toString() ?? '';
      if (phaseForBroadcast != 'initial_peek') {
        
        return;
      }
      
    }

    final broadcastSignature = _buildBroadcastSignature(
      filteredGameState: filteredGameState,
      turnEvents: turnEvents,
      ownerId: ownerId,
      myCardsToPeekFromState: myCardsToPeekFromState,
      cardsToPeekFromState: cardsToPeekFromState,
      winners: winners,
    );
    final lastSignature = _lastBroadcastSignatureByRoom[roomId];
    if (lastSignature == broadcastSignature) {
      
      return;
    }
    _lastBroadcastSignatureByRoom[roomId] = broadcastSignature;

    final payload = _gameStateUpdatedPayloadBase(
      filteredGameState: filteredGameState,
      turnEvents: turnEvents,
      stateVersion: _nextStateVersion(),
      ownerId: ownerId,
      myCardsToPeekFromState: myCardsToPeekFromState,
      cardsToPeekFromState: cardsToPeekFromState,
      winners: winners,
    );
    
    _emitPayloadToRoomSessions(payload);
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
    // This matches the format expected by handlePlayCard in dutch_game_round.dart
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
    // Get current phase and status for phase-based timer calculation
    final gameState = _store.getGameState(roomId);
    final phase = gameState['phase'] as String?;
    final currentPlayer = gameState['currentPlayer'] as Map<String, dynamic>?;
    final status = currentPlayer?['status'] as String?;
    
    
    
    // Get all timer values from single source of truth
    final allTimerValues = ServerGameStateCallbackImpl.getAllTimerValues();
    
    // Calculate timer based on phase or status - timer values from getAllTimerValues()
    // Priority: Status is more specific than phase, so check status first for player actions
    int? turnTimeLimit; // Use null to track if timer was set
    
    // Check status first (more specific than phase for player actions)
    if (status != null && status.isNotEmpty) {
      switch (status) {
        case 'initial_peek':
          turnTimeLimit = allTimerValues['initial_peek'];
          break;
        case 'drawing_card':
          turnTimeLimit = allTimerValues['drawing_card'];
          break;
        case 'playing_card':
          turnTimeLimit = allTimerValues['playing_card'];
          break;
        case 'same_rank_window':
          turnTimeLimit = allTimerValues['same_rank_window'];
          break;
        case 'queen_peek':
          turnTimeLimit = allTimerValues['queen_peek'];
          break;
        case 'jack_swap':
          turnTimeLimit = allTimerValues['jack_swap'];
          break;
        case 'peeking':
          turnTimeLimit = allTimerValues['peeking'];
          break;
        case 'waiting':
          turnTimeLimit = allTimerValues['waiting'];
          break;
        default:
          // If status doesn't match, fall through to phase check
          break;
      }
    }
    
    // If status didn't provide a timer (or status was null), check phase
    if (turnTimeLimit == null && phase != null && phase.isNotEmpty) {
      switch (phase) {
        case 'initial_peek':
          turnTimeLimit = allTimerValues['initial_peek'];
          break;
        case 'player_turn':
        case 'playing':
          // For generic player_turn/playing phase, status should have been checked above
          // But if status wasn't available, use playing_card as default
          turnTimeLimit = allTimerValues['playing_card'];
          break;
        case 'same_rank_window':
          turnTimeLimit = allTimerValues['same_rank_window'];
          break;
        case 'queen_peek_window':
          turnTimeLimit = allTimerValues['queen_peek'];
          break;
        case 'special_play_window':
          turnTimeLimit = allTimerValues['jack_swap'];
          break;
        default:
          turnTimeLimit = allTimerValues['default'];
      }
    }
    
    // Final fallback if neither status nor phase provided a timer
    turnTimeLimit ??= allTimerValues['default'];
    
    // Get showInstructions from game state (default to false if not found)
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
      
      return;
    }
    
    
    
    try {
      // Remove session from the room (same as client leave_room) so they stop receiving
      // room broadcasts; then leave_room hook updates game state for remaining players.
      final wsSeat = server.websocketSessionForGamePlayer(roomId, playerId);
      final sessionArg = wsSeat ?? playerId;
      server.forceSessionLeaveRoom(sessionArg, reason: 'removed_inactivity');
      
    } catch (e) {
      
    }
  }

  @override
  void onGameEnded(List<Map<String, dynamic>> winners, List<Map<String, dynamic>> allPlayers, {int? matchPot}) {
    // Only update stats for multiplayer matches (room_*), not practice (practice_room_*)
    if (!roomId.startsWith('room_')) {
      
      return;
    }

      final pot = matchPot ?? 0;
      

    try {
      // Build list of winner player IDs for quick lookup
      final winnerPlayerIds = winners.map((w) => w['playerId']?.toString() ?? '').toSet();
      
      // Build game_results array for API call
      final gameResults = <Map<String, dynamic>>[];
      
      for (final player in allPlayers) {
        final playerId = player['id']?.toString() ?? '';
        if (playerId.isEmpty) {
          
          continue;
        }
        
        // Get user_id from session (for human players) or from player object (for comp players)
        var userId = player['userId']?.toString().trim();
        if (userId == null || userId.isEmpty) {
          final wsSeat = server.websocketSessionForGamePlayer(roomId, playerId);
          if (wsSeat != null && wsSeat.isNotEmpty) {
            userId = server.getUserIdForSession(wsSeat);
          }
        }
        if (userId == null || userId.isEmpty) {
          userId = server.getUserIdForSession(playerId);
        }
        if (userId == null) {
          // Fallback: Check if player object has userId (for comp players from database)
          userId = player['userId']?.toString();
          if (userId == null || userId.isEmpty) {
            
            continue;
          }
          
        }
        
        // Determine if this player is a winner
        final isWinner = winnerPlayerIds.contains(playerId);
        
        // Get win type if winner
        String? winType;
        if (isWinner) {
          final winnerInfo = winners.firstWhere(
            (w) => w['playerId']?.toString() == playerId,
            orElse: () => {},
          );
          winType = winnerInfo['winType']?.toString();
        }
        
        // Calculate pot for this player (full pot if winner, 0 if not)
        // If multiple winners, pot will be split equally among winners
        final playerPot = isWinner ? (pot > 0 && winners.isNotEmpty ? (pot / winners.length).round() : 0) : 0;

        final rawPts = player['end_game_total_points'];
        final rawCards = player['end_game_card_count'];
        final totalEndPoints = rawPts is int
            ? rawPts
            : int.tryParse('$rawPts') ?? 0;
        final endCardCount = rawCards is int
            ? rawCards
            : int.tryParse('$rawCards') ?? 0;
        
        gameResults.add({
          'user_id': userId,
          'is_winner': isWinner,
          'pot': playerPot, // Pot amount for this player (full pot if single winner, split if multiple winners)
          'win_type': winType,
          'total_end_points': totalEndPoints,
          'end_card_count': endCardCount,
        });
        
        
      }
      
      if (gameResults.isEmpty) {
        
        return;
      }

      // Read tournament context from game state (set at room creation) for Python
      final state = _store.getState(roomId);
      final gameState = state['game_state'] as Map<String, dynamic>? ?? {};
      final isTournament = gameState['is_tournament'] == true;
      final tournamentData = gameState['tournament_data'] as Map<String, dynamic>?;
      final rawCoinReq = gameState['isCoinRequired'];
      final isCoinRequired = rawCoinReq is bool ? rawCoinReq : true;

      // Call Python API to update statistics (and optional tournament stub)
      
      server.pythonClient.updateGameStats(
        gameResults,
        isTournament: isTournament,
        tournamentData: tournamentData,
        roomId: roomId,
        isCoinRequired: isCoinRequired,
      ).then((result) {
        if (result['success'] == true) {
          
          final td = result['tournament_data'];
          if (td is Map<String, dynamic> && td.isNotEmpty) {
            final gs = _store.getGameState(roomId);
            final prev = gs['tournament_data'] as Map<String, dynamic>?;
            gs['tournament_data'] = <String, dynamic>{...?prev, ...td};
            _broadcastFullGameStateFromStore();
          }
        } else {
          
        }
      }).catchError((error) {
        
        // Don't throw - stats update failure shouldn't break the game
      });
      
    } catch (e) {
      
      // Don't throw - stats update failure shouldn't break the game
    }
  }
}

