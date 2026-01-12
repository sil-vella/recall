import '../utils/platform/shared_imports.dart';
import 'coordinator/game_event_coordinator.dart';
import 'services/game_registry.dart';
import 'services/game_state_store.dart';

const bool LOGGING_SWITCH = false; // Enabled for rank-based matching testing

/// Entry point for registering Dutch game module components with the server.
class DutchGameModule {
  final WebSocketServer server;
  final RoomManager roomManager;
  final HooksManager hooksManager;
  late final GameEventCoordinator coordinator;
  final Logger _logger = Logger();

  DutchGameModule(this.server, this.roomManager, this.hooksManager) {
    coordinator = GameEventCoordinator(roomManager, server);
    _registerHooks();
    _logger.info('DutchGameModule initialized with hooks', isOn: LOGGING_SWITCH);
  }

  /// Register hooks for game lifecycle
  void _registerHooks() {
    // room_created: create game instance with minimal state
    hooksManager.registerHookCallback('room_created', _onRoomCreated, priority: 100);
    
    // room_joined: add player to game and send snapshot
    hooksManager.registerHookCallback('room_joined', _onRoomJoined, priority: 100);
    
    // leave_room: remove player from game
    hooksManager.registerHookCallback('leave_room', _onLeaveRoom, priority: 100);
    
    // room_closed: cleanup game instance
    hooksManager.registerHookCallback('room_closed', _onRoomClosed, priority: 100);
    
    _logger.info('🎣 DutchGame: Registered hooks for game lifecycle', isOn: LOGGING_SWITCH);
  }

  /// Hook callback: room_created
  /// Create a minimal game state when a room is created (creator auto-joined)
  void _onRoomCreated(Map<String, dynamic> data) {
    try {
      final roomId = data['room_id'] as String?;
      final ownerId = data['owner_id'] as String?;
      final sessionId = data['session_id'] as String?; // Get sessionId for player ID
      final maxSize = data['max_size'] as int? ?? 4;
      final minPlayers = data['min_players'] as int? ?? 2;
      final gameType = data['game_type'] as String? ?? 'multiplayer';

      if (roomId == null || ownerId == null || sessionId == null) {
        _logger.warning('🎣 room_created: missing roomId, ownerId, or sessionId', isOn: LOGGING_SWITCH);
        return;
      }

      _logger.info('🎣 room_created: Creating game for room $roomId with player ID $sessionId', isOn: LOGGING_SWITCH);

      // Check if this is a practice room (practice rooms start with "practice_room_")
      final isPracticeMode = roomId.startsWith('practice_room_');
      
      String? roomDifficulty;
      
      if (isPracticeMode) {
        // For practice rooms: get difficulty from hook data (passed from Flutter lobby selection)
        final practiceDifficulty = data['difficulty'] as String?;
        if (practiceDifficulty != null) {
          roomDifficulty = practiceDifficulty.toLowerCase();
          _logger.info('🎣 room_created: Practice mode - using difficulty from hook data: $roomDifficulty', isOn: LOGGING_SWITCH);
        } else {
          _logger.warning('🎣 room_created: Practice mode but no difficulty in hook data, defaulting to medium', isOn: LOGGING_SWITCH);
          roomDifficulty = 'medium'; // Default for practice if not provided
        }
        
        // Set room difficulty
        final room = roomManager.getRoomInfo(roomId);
        if (room != null) {
          room.difficulty = roomDifficulty;
          _logger.info('🎣 room_created: Set practice room difficulty to $roomDifficulty for room $roomId', isOn: LOGGING_SWITCH);
        }
      } else {
        // For multiplayer rooms: get creator's rank from session data and set room difficulty
        _logger.info('🎣 room_created: Multiplayer mode - getting rank for session $sessionId', isOn: LOGGING_SWITCH);
        final creatorRank = server.getUserRankForSession(sessionId);
        _logger.info('🎣 room_created: Creator rank for session $sessionId: $creatorRank', isOn: LOGGING_SWITCH);
        if (creatorRank != null) {
          _logger.info('🎣 room_created: Creator rank is not null, getting room info', isOn: LOGGING_SWITCH);
          final room = roomManager.getRoomInfo(roomId);
          _logger.info('🎣 room_created: Room info retrieved: ${room != null ? "found" : "null"}', isOn: LOGGING_SWITCH);
          if (room != null) {
            room.difficulty = creatorRank.toLowerCase();
            roomDifficulty = creatorRank.toLowerCase();
            _logger.info('🎣 room_created: Set room difficulty to $roomDifficulty for room $roomId', isOn: LOGGING_SWITCH);
          } else {
            _logger.warning('🎣 room_created: Room $roomId not found in roomManager', isOn: LOGGING_SWITCH);
          }
        } else {
          _logger.warning('🎣 room_created: Creator rank is null for session $sessionId', isOn: LOGGING_SWITCH);
        }
      }
      _logger.info('🎣 room_created: Final roomDifficulty value: $roomDifficulty', isOn: LOGGING_SWITCH);

      // Create GameRound instance via registry (includes ServerGameStateCallback)
      GameRegistry.instance.getOrCreate(roomId, server);

      // Initialize minimal game state in store
      // Use sessionId as player ID (not ownerId/userId)
      final store = GameStateStore.instance;
      store.mergeRoot(roomId, {
        'game_id': roomId,
        'roomDifficulty': roomDifficulty, // Store room difficulty in state
        'game_state': {
          'gameId': roomId,
          'gameName': 'Game_$roomId',
          'gameType': gameType,
          'maxPlayers': maxSize,
          'minPlayers': minPlayers,
          'isGameActive': false,
          // Match Python: use 'phase' so Flutter reads it correctly
          'phase': 'waiting_for_players',
          // Ensure counts available for UI slices
          'playerCount': 1,
          'players': <Map<String, dynamic>>[
            // Creator added as first player (auto-joined)
            // Player ID is now sessionId, not ownerId
            {
              'id': sessionId, // Use sessionId as player ID
              'name': 'Player_${sessionId.substring(0, sessionId.length > 8 ? 8 : sessionId.length)}',
              'isHuman': true,
              'status': 'waiting',
              'hand': <Map<String, dynamic>>[],
              'visible_cards': <Map<String, dynamic>>[],
              'points': 0,
              'known_cards': <String, dynamic>{},
              'collection_rank_cards': <String>[],
              'isActive': true,  // Required for winner calculation and same rank play filtering
              'userId': ownerId,  // Store userId (MongoDB ObjectId) for coin deduction
            }
          ],
          'drawPile': <String>[],
          'discardPile': <Map<String, dynamic>>[],
          'originalDeck': <Map<String, dynamic>>[],
        },
      });

      // Send initial game_state_updated to creator
      final initialState = store.getState(roomId);
      server.sendToSession(
        sessionId, // Use sessionId directly instead of lookup
        {
          'event': 'game_state_updated',
          'game_id': roomId,
          'game_state': initialState['game_state'],
          // Seed ownership for Flutter to gate Start button
          'owner_id': ownerId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _logger.info('✅ Game created for room $roomId with creator session $sessionId', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ Error in _onRoomCreated: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Hook callback: room_joined
  /// Add player to existing game and send snapshot
  void _onRoomJoined(Map<String, dynamic> data) {
    try {
      final roomId = data['room_id'] as String?;
      final userId = data['user_id'] as String?; // Kept for backward compatibility
      final sessionId = data['session_id'] as String?; // This is now the player ID

      if (roomId == null || sessionId == null) {
        _logger.warning('🎣 room_joined: missing roomId or sessionId', isOn: LOGGING_SWITCH);
        return;
      }

      _logger.info('🎣 room_joined: Adding player with session ID $sessionId to room $roomId', isOn: LOGGING_SWITCH);

      final store = GameStateStore.instance;
      final gameState = store.getGameState(roomId);
      final players = gameState['players'] as List<dynamic>? ?? [];

      // Check if player already exists (by sessionId, not userId)
      final existingPlayer = players.any((p) => p['id'] == sessionId);
      if (existingPlayer) {
        _logger.info('Player with session $sessionId already in game $roomId', isOn: LOGGING_SWITCH);
        // Still send snapshot
        _sendGameSnapshot(sessionId, roomId);
        return;
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
          _logger.info('🎣 room_joined: Set room difficulty to $joinerRank for room $roomId (first human player)', isOn: LOGGING_SWITCH);
        }
      } else if (room != null && room.difficulty != null) {
        roomDifficulty = room.difficulty;
        _logger.info('🎣 room_joined: Room $roomId already has difficulty set to ${room.difficulty}', isOn: LOGGING_SWITCH);
      } else if (isPracticeMode && room != null && room.difficulty == null) {
        // Practice room but difficulty not set - should have been set in room_created, default to medium
        room.difficulty = 'medium';
        roomDifficulty = 'medium';
        _logger.warning('🎣 room_joined: Practice room $roomId has no difficulty, defaulting to medium', isOn: LOGGING_SWITCH);
      }
      
      // Update game state with room difficulty
      if (roomDifficulty != null) {
        final stateRoot = store.getState(roomId);
        stateRoot['roomDifficulty'] = roomDifficulty;
        store.setGameState(roomId, stateRoot['game_state'] as Map<String, dynamic>);
      }

      // Add new player - use sessionId as player ID
      players.add({
        'id': sessionId, // Use sessionId as player ID
        'name': 'Player_${sessionId.substring(0, sessionId.length > 8 ? 8 : sessionId.length)}',
        'isHuman': true,
        'status': 'waiting',
        'hand': <Map<String, dynamic>>[],
        'visible_cards': <Map<String, dynamic>>[],
        'points': 0,
        'known_cards': <String, dynamic>{},
        'collection_rank_cards': <String>[],
        'isActive': true,  // Required for winner calculation and same rank play filtering
        if (userId != null && userId.isNotEmpty) 'userId': userId,  // Store userId for coin deduction
      });

      gameState['players'] = players;
      // Maintain playerCount for UI
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
          'name': 'Player_${sessionId.substring(0, sessionId.length > 8 ? 8 : sessionId.length)}',
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

      _logger.info('✅ Player with session $sessionId added to game $roomId', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ Error in _onRoomJoined: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Hook callback: leave_room
  /// Remove player from game
  void _onLeaveRoom(Map<String, dynamic> data) {
    try {
      final roomId = data['room_id'] as String?;
      final sessionId = data['session_id'] as String?; // Use sessionId as player ID

      if (roomId == null || sessionId == null) {
        _logger.warning('🎣 leave_room: missing roomId or sessionId', isOn: LOGGING_SWITCH);
        return;
      }

      _logger.info('🎣 leave_room: Removing player with session $sessionId from room $roomId', isOn: LOGGING_SWITCH);

      final store = GameStateStore.instance;
      final gameState = store.getGameState(roomId);
      final players = (gameState['players'] as List<dynamic>? ?? []);

      // Remove player by sessionId (player ID)
      final initialPlayerCount = players.length;
      players.removeWhere((p) => p['id'] == sessionId);
      final newPlayerCount = players.length;
      
      if (initialPlayerCount == newPlayerCount) {
        _logger.warning('🎣 leave_room: Player $sessionId not found in game state players list', isOn: LOGGING_SWITCH);
        _logger.warning('🎣 leave_room: Current players: ${players.map((p) => p['id']?.toString() ?? 'unknown').join(', ')}', isOn: LOGGING_SWITCH);
      }
      
      gameState['players'] = players;
      gameState['playerCount'] = newPlayerCount; // Update player count
      
      // Ensure phase is set (preserve existing phase if present)
      if (!gameState.containsKey('phase')) {
        gameState['phase'] = 'playing'; // Default phase
      }
      
      store.setGameState(roomId, gameState);

      _logger.info('✅ Player with session $sessionId removed from game $roomId (players: $initialPlayerCount -> $newPlayerCount)', isOn: LOGGING_SWITCH);

      // CRITICAL: Broadcast the updated game state to all remaining players
      // This ensures other players see that the player has left
      // Note: If this was triggered by auto-leave, _moveToNextPlayer() was already called
      // in the timer expiry handler, so the game has already progressed to the next player
      final ownerId = server.getRoomOwner(roomId);
      server.broadcastToRoom(roomId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gameState,
        'turn_events': [], // No turn events for leave
        if (ownerId != null) 'owner_id': ownerId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _logger.info('✅ Broadcasted game_state_updated to all players in room $roomId after player $sessionId left', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ Error in _onLeaveRoom: $e', isOn: LOGGING_SWITCH);
    }
  }

  /// Hook callback: room_closed
  /// Cleanup game instance and state
  void _onRoomClosed(Map<String, dynamic> data) {
    try {
      final roomId = data['room_id'] as String?;
      final reason = data['reason'] as String? ?? 'unknown';

      if (roomId == null) {
        _logger.warning('🎣 room_closed: missing roomId', isOn: LOGGING_SWITCH);
        return;
      }

      _logger.info('🎣 room_closed: Cleaning up game for room $roomId (reason: $reason)', isOn: LOGGING_SWITCH);

      // Dispose GameRound instance
      GameRegistry.instance.dispose(roomId);

      // Clear game state
      GameStateStore.instance.clear(roomId);

      _logger.info('✅ Game cleanup complete for room $roomId', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ Error in _onRoomClosed: $e', isOn: LOGGING_SWITCH);
    }
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

      server.sendToSession(sessionId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gs,
        if (ownerId != null) 'owner_id': ownerId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _logger.info('📤 Sent game snapshot to session $sessionId for room $roomId', isOn: LOGGING_SWITCH);
    } catch (e) {
      _logger.error('❌ Error sending snapshot: $e', isOn: LOGGING_SWITCH);
    }
  }
}


