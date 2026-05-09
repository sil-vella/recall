// =============================================================================
// Dutch game module — hook callbacks implementation
// =============================================================================
//
// This file is the ONLY place that registers Dutch game hook *callbacks*.
// It is loaded via the re-export in ../dutch_main.dart (see that file for
// how this module and the server act together).
//
// Hook flow (summary):
// --------------------
//   1. WebSocketServer (websocket_server.dart) owns HooksManager and calls
//      registerHook('room_created'), registerHook('room_joined'), etc. to
//      declare hook names. No callbacks at that point.
//   2. WebSocketServer instantiates DutchGameModule(server, roomManager, hooksManager).
//      This constructor calls _registerHooks() below, which registers the four
//      callbacks with HooksManager.
//   3. MessageHandler (message_handler.dart) triggers hooks when room events
//      occur: triggerHook('room_created', data) after create_room,
//      triggerHook('room_joined', data) when a user joins (or when creator
//      auto-joins), triggerHook('leave_room', data) on leave,
//      and RoomManager triggers triggerHook('room_closed', data) when a room
//      is closed.
//   4. HooksManager invokes the callbacks registered here (_onRoomCreated,
//      _onRoomJoined, _onLeaveRoom, _onRoomClosed). This module then updates
//      GameStateStore, GameRegistry, and sends game_state_updated to sessions
//      as needed.
//
// Important: room_created receives add_creator_to_room in data. When false
// (e.g. tournament admin flow), this module creates game state with 0 players
// and does not send game_state_updated to the creator. When true, the creator
// is added as the first player and receives the initial state.
//
// =============================================================================

import '../utils/platform/shared_imports.dart';
import 'coordinator/game_event_coordinator.dart';
import 'services/game_registry.dart';
import 'services/game_state_store.dart';

const bool LOGGING_SWITCH = false; // leave/grace + snapshot hooks (disconnect rejoin; set false after test)

/// If [gameState.currentPlayer] is missing from [players] (e.g. leave mid-turn), pick a new
/// current seat so broadcasts stay consistent for remaining clients and CPU timers.
void _reassignCurrentPlayerIfInvalidForLeave(
  Map<String, dynamic> gameState,
  List<dynamic> players,
) {
  if (players.isEmpty) return;

  String? curId;
  final cp = gameState['currentPlayer'];
  if (cp is Map<String, dynamic>) {
    curId = cp['id']?.toString();
  }

  final rosterHasCurrent = curId != null &&
      curId.isNotEmpty &&
      players.any((p) {
        if (p is! Map<String, dynamic>) return false;
        return p['id']?.toString() == curId;
      });
  if (rosterHasCurrent) return;

  Map<String, dynamic>? chosen;
  for (final p in players) {
    if (p is Map<String, dynamic> && (p['isActive'] as bool? ?? true)) {
      chosen = p;
      break;
    }
  }
  if (chosen == null) {
    for (final p in players) {
      if (p is Map<String, dynamic>) {
        chosen = p;
        break;
      }
    }
  }
  if (chosen == null) return;

  for (final p in players) {
    if (p is! Map<String, dynamic>) continue;
    if (identical(p, chosen)) continue;
    p['status'] = 'waiting';
  }
  chosen['status'] = 'drawing_card';
  gameState['currentPlayer'] = chosen;
}

/// Dutch game backend module. Registers the four room-lifecycle hook callbacks
/// and holds the coordinator for game events. Instantiated once by WebSocketServer.
class DutchGameModule {
  final WebSocketServer server;
  final RoomManager roomManager;
  final HooksManager hooksManager;
  late final GameEventCoordinator coordinator;
  final Logger _logger = Logger();

  DutchGameModule(this.server, this.roomManager, this.hooksManager) {
    coordinator = GameEventCoordinator(roomManager, server);
    _registerHooks();
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameModule initialized with hooks');
    }
  }

  /// Registers this module's callbacks with HooksManager. This is the only
  /// place in the codebase that registers these four hooks; do not register
  /// them elsewhere.
  void _registerHooks() {
    hooksManager.registerHookCallback('room_created', _onRoomCreated, priority: 100);
    hooksManager.registerHookCallback('room_joined', _onRoomJoined, priority: 100);
    hooksManager.registerHookCallback('leave_room', _onLeaveRoom, priority: 100);
    hooksManager.registerHookCallback('room_closed', _onRoomClosed, priority: 100);
    if (LOGGING_SWITCH) {
      _logger.info('🎣 DutchGame: Registered hooks for game lifecycle');
    }
  }

  /// Hook callback for 'room_created'. Triggered by MessageHandler after create_room
  /// (and after random-join room creation). Creates minimal game state; when
  /// add_creator_to_room is false (e.g. tournament admin flow), creator is not added as a player.
  Future<void> _onRoomCreated(Map<String, dynamic> data) async {
    try {
      final roomId = data['room_id'] as String?;
      final ownerId = data['owner_id'] as String?;
      final sessionId = data['session_id'] as String?; // Get sessionId for player ID
      final addCreatorToRoom = data['add_creator_to_room'] as bool? ?? true;
      final maxSize = data['max_size'] as int? ?? 4;
      final minPlayers = data['min_players'] as int? ?? 2;
      final gameType = data['game_type'] as String? ?? 'multiplayer';
      final gameLevel = data['game_level'] as int?;
      final isTournament = data['is_tournament'] as bool? ?? false;
      final tournamentData = data['tournament_data'] as Map<String, dynamic>?;
      final isCoinRequired =
          data['is_coin_required'] as bool? ?? data['isCoinRequired'] as bool? ?? true;
      final permission = data['permission'] as String?;
      final createdAt = data['created_at'] as String?;
      final currentSize = data['current_size'] as int?;
      final specialEventIdHook = data['special_event_id']?.toString();
      final specialEndModalHook = data['special_event_end_match_modal'];

      if (roomId == null || ownerId == null || sessionId == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎣 room_created: missing roomId, ownerId, or sessionId');
        }
        return;
      }

      if (LOGGING_SWITCH) {
        _logger.info('🎣 room_created: room=$roomId add_creator_to_room=$addCreatorToRoom sessionId=$sessionId');
      }

      // Check if this is a practice room (practice rooms start with "practice_room_")
      final isPracticeMode = roomId.startsWith('practice_room_');
      
      String? roomDifficulty;
      
      if (isPracticeMode) {
        // For practice rooms: get difficulty from hook data (passed from Flutter lobby selection)
        final practiceDifficulty = data['difficulty'] as String?;
        if (practiceDifficulty != null) {
          roomDifficulty = practiceDifficulty.toLowerCase();
          if (LOGGING_SWITCH) {
            _logger.info('🎣 room_created: Practice mode - using difficulty from hook data: $roomDifficulty');
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.warning('🎣 room_created: Practice mode but no difficulty in hook data, defaulting to medium');
          }
          roomDifficulty = 'medium'; // Default for practice if not provided
        }
        
        // Set room difficulty
        final room = roomManager.getRoomInfo(roomId);
        if (room != null) {
          room.difficulty = roomDifficulty;
          if (LOGGING_SWITCH) {
            _logger.info('🎣 room_created: Set practice room difficulty to $roomDifficulty for room $roomId');
          }
        }
      } else {
        // For multiplayer rooms: get creator's rank from session data and set room difficulty
        if (LOGGING_SWITCH) {
          _logger.info('🎣 room_created: Multiplayer mode - getting rank for session $sessionId');
        }
        final creatorRank = server.getUserRankForSession(sessionId);
        if (LOGGING_SWITCH) {
          _logger.info('🎣 room_created: Creator rank for session $sessionId: $creatorRank');
        }
        if (creatorRank != null) {
          if (LOGGING_SWITCH) {
            _logger.info('🎣 room_created: Creator rank is not null, getting room info');
          }
          final room = roomManager.getRoomInfo(roomId);
          if (LOGGING_SWITCH) {
            _logger.info('🎣 room_created: Room info retrieved: ${room != null ? "found" : "null"}');
          }
          if (room != null) {
            room.difficulty = creatorRank.toLowerCase();
            roomDifficulty = creatorRank.toLowerCase();
            if (LOGGING_SWITCH) {
              _logger.info('🎣 room_created: Set room difficulty to $roomDifficulty for room $roomId');
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.warning('🎣 room_created: Room $roomId not found in roomManager');
            }
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.warning('🎣 room_created: Creator rank is null for session $sessionId');
          }
        }
      }
      if (LOGGING_SWITCH) {
        _logger.info('🎣 room_created: Final roomDifficulty value: $roomDifficulty');
      }

      // Create GameRound instance via registry (includes ServerGameStateCallback)
      GameRegistry.instance.getOrCreate(roomId, server);

      // When addCreatorToRoom is true, add creator as first player and send them game state; otherwise start with 0 players (e.g. tournament admin flow).
      List<Map<String, dynamic>> initialPlayers = [];
      if (addCreatorToRoom) {
        String playerName = 'Player_${sessionId.substring(0, sessionId.length > 8 ? 8 : sessionId.length)}';
        String? profilePicture;
        String? usernameFromProfile;
        String? equippedCardBackId;
        if (ownerId.isNotEmpty) {
          try {
            final profileResult = await server.pythonClient.getUserProfile(ownerId);
            if (profileResult['success'] == true) {
              final fullName = profileResult['full_name'] as String?;
              usernameFromProfile = profileResult['username'] as String?;
              profilePicture = profileResult['profile_picture'] as String?;
              if (fullName != null && fullName.isNotEmpty) {
                playerName = fullName;
              } else if (usernameFromProfile != null && usernameFromProfile.isNotEmpty) {
                playerName = usernameFromProfile;
              }
              if (LOGGING_SWITCH) {
                _logger.info('✅ Fetched creator profile: name=$playerName, username=$usernameFromProfile');
              }
            } else if (LOGGING_SWITCH) {
              _logger.warning('⚠️ Failed to fetch creator profile: ${profileResult['error']}');
            }
          } catch (e) {
            if (LOGGING_SWITCH) _logger.warning('⚠️ Error fetching creator profile: $e');
          }
          try {
            final statsResult = await server.pythonClient.getUserStatsForJoin(ownerId);
            if (statsResult['success'] == true) {
              final inventory = statsResult['inventory'] as Map<String, dynamic>? ?? {};
              final cosmetics = inventory['cosmetics'] as Map<String, dynamic>? ?? {};
              final equipped = cosmetics['equipped'] as Map<String, dynamic>? ?? {};
              final cardBack = equipped['card_back_id']?.toString() ?? '';
              if (cardBack.isNotEmpty) equippedCardBackId = cardBack;
            }
          } catch (_) {}
        }
        final seatId = canonicalMultiplayerHumanPlayerId(sessionId, ownerId);
        initialPlayers = [
          {
            'id': seatId,
            'name': playerName,
            'isHuman': true,
            'status': 'waiting',
            'hand': <Map<String, dynamic>>[],
            'visible_cards': <Map<String, dynamic>>[],
            'points': 0,
            'known_cards': <String, dynamic>{},
            'collection_rank_cards': <String>[],
            'isActive': true,
            'userId': ownerId,
            if (usernameFromProfile != null && usernameFromProfile.isNotEmpty) 'username': usernameFromProfile,
            if (profilePicture != null && profilePicture.isNotEmpty) 'profile_picture': profilePicture,
            if (equippedCardBackId != null && equippedCardBackId.isNotEmpty) 'card_back_id': equippedCardBackId,
          }
        ];
      } else if (LOGGING_SWITCH) {
        _logger.info('🎣 room_created: add_creator_to_room=false, starting with 0 players for room $roomId');
      }

      final store = GameStateStore.instance;
      // Build inner game_state with full room args so clients and coordinator have complete context
      final gameStateInner = <String, dynamic>{
        'gameId': roomId,
        'gameName': 'Game_$roomId',
        'gameType': gameType,
        'maxPlayers': maxSize,
        'minPlayers': minPlayers,
        'isGameActive': false,
        'phase': 'waiting_for_players',
        'playerCount': initialPlayers.length,
        'players': initialPlayers,
        'drawPile': <Map<String, dynamic>>[],
        'discardPile': <Map<String, dynamic>>[],
        'originalDeck': <Map<String, dynamic>>[],
      };
      if (gameLevel != null) gameStateInner['gameLevel'] = gameLevel;
      if (isTournament) gameStateInner['is_tournament'] = true;
      if (tournamentData != null && tournamentData.isNotEmpty) gameStateInner['tournament_data'] = tournamentData;
      gameStateInner['isCoinRequired'] = isCoinRequired;
      if (permission != null && permission.isNotEmpty) gameStateInner['permission'] = permission;
      if (createdAt != null && createdAt.isNotEmpty) gameStateInner['created_at'] = createdAt;
      if (currentSize != null) gameStateInner['current_size'] = currentSize;
      gameStateInner['owner_id'] = ownerId;

      final seTrim = specialEventIdHook?.trim();
      if (seTrim != null && seTrim.isNotEmpty) {
        gameStateInner['special_event_id'] = seTrim;
      }
      if (specialEndModalHook is Map && specialEndModalHook.isNotEmpty) {
        gameStateInner['special_event_end_match_modal'] =
            Map<String, dynamic>.from(specialEndModalHook.map((k, v) => MapEntry(k.toString(), v)));
      }

      store.mergeRoot(roomId, {
        'game_id': roomId,
        'roomDifficulty': roomDifficulty,
        'game_state': gameStateInner,
      });

      if (addCreatorToRoom) {
        final initialState = store.getState(roomId);
        final payload = <String, dynamic>{
          'event': 'game_state_updated',
          'game_id': roomId,
          'game_state': initialState['game_state'],
          'owner_id': ownerId,
          'game_type': gameType,
          'timestamp': DateTime.now().toIso8601String(),
        };
        if (gameLevel != null) payload['game_level'] = gameLevel;
        server.sendToSession(sessionId, payload);
        if (LOGGING_SWITCH) {
          _logger.info('✅ Game created for room $roomId with creator session $sessionId (1 player)');
        }
      } else if (LOGGING_SWITCH) {
        _logger.info('✅ Game created for room $roomId with 0 players (creator not in room)');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error in _onRoomCreated: $e');
      }
    }
  }

  /// Hook callback for 'room_joined'. Triggered by MessageHandler when a client
  /// sends join_room (or when creator auto-joins after create_room if add_creator_to_room).
  /// Adds the joining session as a player in game state and sends game_state_updated.
  Future<void> _onRoomJoined(Map<String, dynamic> data) async {
    try {
      final roomId = data['room_id'] as String?;
      final userId = data['user_id'] as String?; // Kept for backward compatibility
      final sessionId = data['session_id'] as String?; // This is now the player ID

      if (roomId == null || sessionId == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎣 room_joined: missing roomId or sessionId');
        }
        return;
      }

      if (LOGGING_SWITCH) {
        _logger.info('🎣 room_joined: processing session=$sessionId room=$roomId');
      }

      final store = GameStateStore.instance;
      final canonicalSeat =
          canonicalMultiplayerHumanPlayerId(sessionId, userId ?? '');

      // Fast-path if roster already authoritative (handles sync re-entry).
      {
        final gs0 = store.getGameState(roomId);
        final pl0 = gs0['players'] as List<dynamic>? ?? [];
        if (pl0.any((p) => p['id'] == canonicalSeat)) {
          if (LOGGING_SWITCH) {
            _logger.info('Player seat $canonicalSeat already in game $roomId (sync check)');
          }
          _sendGameSnapshot(sessionId, roomId);
          return;
        }
        if (userId != null && userId.isNotEmpty &&
            pl0.any((p) => p['userId']?.toString() == userId)) {
          if (LOGGING_SWITCH) {
            _logger.info('User $userId already in game $roomId (sync check)');
          }
          _sendGameSnapshot(sessionId, roomId);
          return;
        }
      }

      // Set room difficulty if not already set
      // For practice rooms: difficulty is already set in room_created hook
      // For multiplayer rooms: first human player sets it from their rank
      final room = roomManager.getRoomInfo(roomId);
      String? roomDifficulty;
      final isPracticeMode = roomId.startsWith('practice_room_');
      
      if (room != null && room.difficulty == null && !isPracticeMode) {
        // Only try to get rank for multiplayer rooms (practice rooms already have difficulty set)
        final joinerRank = server.getUserRankForSession(sessionId);
        if (joinerRank != null) {
          room.difficulty = joinerRank.toLowerCase();
          roomDifficulty = joinerRank.toLowerCase();
          if (LOGGING_SWITCH) {
            _logger.info('🎣 room_joined: Set room difficulty to $joinerRank for room $roomId (first human player)');
          }
        }
      } else if (room != null && room.difficulty != null) {
        roomDifficulty = room.difficulty;
        if (LOGGING_SWITCH) {
          _logger.info('🎣 room_joined: Room $roomId already has difficulty set to ${room.difficulty}');
        }
      } else if (isPracticeMode && room != null && room.difficulty == null) {
        // Practice room but difficulty not set - should have been set in room_created, default to medium
        room.difficulty = 'medium';
        roomDifficulty = 'medium';
        if (LOGGING_SWITCH) {
          _logger.warning('🎣 room_joined: Practice room $roomId has no difficulty, defaulting to medium');
        }
      }

      // Fetch user profile data (full name, profile picture) if userId is available
      String playerName = 'Player_${sessionId.substring(0, sessionId.length > 8 ? 8 : sessionId.length)}';
      String? profilePicture;
      String? usernameFromProfile;
      String? equippedCardBackId;
      
      if (userId != null && userId.isNotEmpty) {
        try {
          final profileResult = await server.pythonClient.getUserProfile(userId);
          if (profileResult['success'] == true) {
            final fullName = profileResult['full_name'] as String?;
            usernameFromProfile = profileResult['username'] as String?;
            profilePicture = profileResult['profile_picture'] as String?;
            
            // Use full name if available, otherwise fallback to username, otherwise keep default
            if (fullName != null && fullName.isNotEmpty) {
              playerName = fullName;
            } else if (usernameFromProfile != null && usernameFromProfile.isNotEmpty) {
              playerName = usernameFromProfile;
            }
            
            final accountType = profileResult['account_type'] as String? ?? 'unknown';
            if (LOGGING_SWITCH) {
              _logger.info('✅ Fetched user profile: name=$playerName, username=$usernameFromProfile, account_type=$accountType, hasPicture=${profilePicture != null && profilePicture.isNotEmpty}');
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.warning('⚠️ Failed to fetch user profile: ${profileResult['error']}');
            }
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ Error fetching user profile: $e');
          }
          // Continue with default name
        }
        try {
          final statsResult = await server.pythonClient.getUserStatsForJoin(userId);
          if (statsResult['success'] == true) {
            final inventory = statsResult['inventory'] as Map<String, dynamic>? ?? {};
            final cosmetics = inventory['cosmetics'] as Map<String, dynamic>? ?? {};
            final equipped = cosmetics['equipped'] as Map<String, dynamic>? ?? {};
            final cardBack = equipped['card_back_id']?.toString() ?? '';
            if (cardBack.isNotEmpty) equippedCardBackId = cardBack;
          }
        } catch (_) {}
      }

      // Authoritative roster read AFTER awaits — `room_created` may merge while we fetch profile,
      // and early `players` references would otherwise be orphaned or stale.
      final gameState =
          Map<String, dynamic>.from(store.getGameState(roomId));
      final playersExisting = gameState['players'] as List<dynamic>? ?? [];
      final players = <Map<String, dynamic>>[];
      for (final p in playersExisting) {
        if (p is Map<String, dynamic>) {
          players.add(Map<String, dynamic>.from(p));
        }
      }

      if (players.any((p) => p['id'] == canonicalSeat)) {
        if (LOGGING_SWITCH) {
          _logger.info(
            '🎣 room_joined: seat $canonicalSeat already present after await (room_created won race); skip duplicate add',
          );
        }
        _sendGameSnapshot(sessionId, roomId);
        return;
      }
      if (userId != null &&
          userId.isNotEmpty &&
          players.any((p) => p['userId']?.toString() == userId)) {
        if (LOGGING_SWITCH) {
          _logger.info(
            '🎣 room_joined: user $userId already in roster after await; skip duplicate add',
          );
        }
        _sendGameSnapshot(sessionId, roomId);
        return;
      }

      if (roomDifficulty != null) {
        final stateRoot = store.getState(roomId);
        stateRoot['roomDifficulty'] = roomDifficulty;
      }

      // Add new player — stable seat id survives WS reconnect (`hum_<userId>`).
      players.add({
        'id': canonicalSeat,
        'name': playerName,
        'isHuman': true,
        'status': 'waiting',
        'hand': <Map<String, dynamic>>[],
        'visible_cards': <Map<String, dynamic>>[],
        'points': 0,
        'known_cards': <String, dynamic>{},
        'collection_rank_cards': <String>[],
        'isActive': true,  // Required for winner calculation and same rank play filtering
        if (userId != null && userId.isNotEmpty) 'userId': userId,  // Store userId for coin deduction
        if (usernameFromProfile != null && usernameFromProfile.isNotEmpty) 'username': usernameFromProfile,  // Store username for display
        if (profilePicture != null && profilePicture.isNotEmpty) 'profile_picture': profilePicture,
        if (equippedCardBackId != null && equippedCardBackId.isNotEmpty) 'card_back_id': equippedCardBackId,
      });

      gameState['players'] = players;
      gameState['playerCount'] = players.length;
      store.setGameState(roomId, gameState);

      // Send snapshot to the joiner
      _sendGameSnapshot(sessionId, roomId);

      // Broadcast player_joined to room (include owner_id like Python)
      final ownerId = roomManager.getRoomInfo(roomId)?.ownerId;
      server.broadcastToRoom(roomId, {
        'event': 'dutch_new_player_joined',
        'room_id': roomId,
        if (ownerId != null) 'owner_id': ownerId,
        'joined_player': {
          'user_id': userId, // Kept for backward compatibility
          'session_id': sessionId, // This is the player ID
          'name': playerName,
          if (profilePicture != null && profilePicture.isNotEmpty) 'profile_picture': profilePicture,
          'joined_at': DateTime.now().toIso8601String(),
        },
        'game_state': () {
          final gs = Map<String, dynamic>.from(store.getState(roomId)['game_state'] as Map<String, dynamic>);
          // Ensure 'phase' key exists on join snapshot too
          gs.putIfAbsent('phase', () => 'waiting_for_players');
          // Ensure playerCount present
          gs['playerCount'] = (gs['players'] as List<dynamic>? ?? []).length;
          return gs;
        }(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      if (LOGGING_SWITCH) {
        _logger.info('✅ Player with session $sessionId added to game $roomId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error in _onRoomJoined: $e');
      }
    }
  }

  /// Hook callback: leave_room
  /// Remove player from game
  /// Hook callback for 'leave_room'. Triggered by MessageHandler when a client
  /// sends leave_room. Removes the session from game state and notifies room.
  void _onLeaveRoom(Map<String, dynamic> data) {
    try {
      final roomId = data['room_id'] as String?;
      final sessionId = data['session_id'] as String?;
      final gamePlayerId =
          data['game_player_id'] as String? ?? sessionId;

      if (roomId == null || gamePlayerId == null || gamePlayerId.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎣 leave_room: missing roomId or game_player_id');
        }
        return;
      }

      if (LOGGING_SWITCH) {
        _logger.info(
            '🎣 leave_room: Removing player $gamePlayerId from room $roomId (session=$sessionId)');
      }

      final store = GameStateStore.instance;
      final gameState = store.getGameState(roomId);
      final players = (gameState['players'] as List<dynamic>? ?? []);

      // Remove player by canonical seat id (or legacy session-as-id)
      final initialPlayerCount = players.length;
      players.removeWhere((p) => p['id'] == gamePlayerId);
      final newPlayerCount = players.length;
      
      if (initialPlayerCount == newPlayerCount) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎣 leave_room: Player $gamePlayerId not found in game state players list');
          _logger.warning('🎣 leave_room: Current players: ${players.map((p) => p['id']?.toString() ?? 'unknown').join(', ')}');
        }
      }
      
      gameState['players'] = players;
      gameState['playerCount'] = newPlayerCount; // Update player count

      _reassignCurrentPlayerIfInvalidForLeave(gameState, players);
      
      // Ensure phase is set (preserve existing phase if present)
      if (!gameState.containsKey('phase')) {
        gameState['phase'] = 'playing'; // Default phase
      }
      
      store.setGameState(roomId, gameState);

      if (LOGGING_SWITCH) {
        _logger.info(
            '✅ Player $gamePlayerId removed from game $roomId (players: $initialPlayerCount -> $newPlayerCount)');
      }

      // One player left mid-match: declare winner and use normal game_ended broadcast (same as regular end).
      final phaseAfterLeave = gameState['phase'] as String? ?? '';
      if (newPlayerCount == 1 &&
          phaseAfterLeave != 'waiting_for_players' &&
          phaseAfterLeave != 'game_ended') {
        final round = GameRegistry.instance.getExisting(roomId);
        if (round != null) {
          round.endGameWithSoleRemainingPlayer();
          if (LOGGING_SWITCH) {
            _logger.info('🎣 leave_room: Sole player remains — match ended via game_ended path');
          }
          return;
        }
      }

      // CRITICAL: Broadcast the updated game state to all remaining players
      // This ensures other players see that the player has left.
      // Inactivity kicks: DutchGameRound advances the turn synchronously before
      // [triggerLeaveRoom]; [_reassignCurrentPlayerIfInvalidForLeave] covers any other leave path.
      final ownerId = server.getRoomOwner(roomId);
      server.broadcastToRoom(roomId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gameState,
        'turn_events': [], // No turn events for leave
        if (ownerId != null) 'owner_id': ownerId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info(
            '✅ Broadcasted game_state_updated to all players in room $roomId after player $gamePlayerId left');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error in _onLeaveRoom: $e');
      }
    }
  }

  /// Hook callback: room_closed
  /// Cleanup game instance and state
  /// Hook callback for 'room_closed'. Triggered by RoomManager when a room is
  /// closed (e.g. empty or TTL). Cleans up GameStateStore and GameRegistry for that room.
  void _onRoomClosed(Map<String, dynamic> data) {
    try {
      final roomId = data['room_id'] as String?;
      final reason = data['reason'] as String? ?? 'unknown';

      if (roomId == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎣 room_closed: missing roomId');
        }
        return;
      }

      if (LOGGING_SWITCH) {
        _logger.info('🎣 room_closed: Cleaning up game for room $roomId (reason: $reason)');
      }

      // Dispose GameRound instance
      GameRegistry.instance.dispose(roomId);

      // Clear game state
      GameStateStore.instance.clear(roomId);

      if (LOGGING_SWITCH) {
        _logger.info('✅ Game cleanup complete for room $roomId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error in _onRoomClosed: $e');
      }
    }
  }

  /// Send full Dutch snapshot to one websocket session (resume_room / recovery).
  void sendGameSnapshotToSession(String sessionId, String roomId) =>
      _sendGameSnapshot(sessionId, roomId);

  /// Pause/resume primary action timers during disconnect grace (`DutchGameRound`).
  void pauseActionTimersForDisconnectGrace(String roomId, String stablePlayerId) {
    GameRegistry.instance
        .getExisting(roomId)
        ?.pauseActionTimersForPlayer(stablePlayerId);
  }

  void resumeActionTimersAfterReconnect(String roomId, String stablePlayerId) {
    GameRegistry.instance
        .getExisting(roomId)
        ?.resumeActionTimersForPlayer(stablePlayerId);
  }

  void clearDisconnectGracePause(String roomId, String stablePlayerId) {
    GameRegistry.instance
        .getExisting(roomId)
        ?.clearActionTimerPauseWithoutResume(stablePlayerId);
  }

  /// Helper: Send current game state snapshot to a session
  void _sendGameSnapshot(String sessionId, String roomId) {
    try {
      final store = GameStateStore.instance;
      final state = store.getState(roomId);
      // Compute owner and ensure counts
      final ownerId = roomManager.getRoomInfo(roomId)?.ownerId;
      final gs = Map<String, dynamic>.from(state['game_state'] as Map<String, dynamic>? ?? {});
      gs['playerCount'] = (gs['players'] as List<dynamic>? ?? []).length;

      final gameType = gs['gameType']?.toString() ?? roomManager.getRoomInfo(roomId)?.gameType;
      final gameLevel = gs['gameLevel'] as int? ?? roomManager.getRoomInfo(roomId)?.gameLevel;
      server.sendToSession(sessionId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gs,
        if (ownerId != null) 'owner_id': ownerId,
        if (gameType != null && gameType.isNotEmpty) 'game_type': gameType,
        if (gameLevel != null) 'game_level': gameLevel,
        'timestamp': DateTime.now().toIso8601String(),
      });

      if (LOGGING_SWITCH) {
        _logger.info('📤 Sent game snapshot to session $sessionId for room $roomId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error sending snapshot: $e');
      }
    }
  }
}


