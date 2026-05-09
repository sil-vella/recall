import '../utils/platform/shared_imports.dart';
import 'coordinator/game_event_coordinator.dart';
import 'services/game_registry.dart';
import 'services/game_state_store.dart';
import 'utils/player_seat_id.dart';

const bool LOGGING_SWITCH = false; // leave/grace + snapshot mirrors server (disconnect rejoin; set false after test)

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
    if (LOGGING_SWITCH) {
      _logger.info('DutchGameModule initialized with hooks');
    }
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
    
    if (LOGGING_SWITCH) {
      _logger.info('🎣 DutchGame: Registered hooks for game lifecycle');
    }
  }

  /// Hook callback: room_created
  /// Create a minimal game state when a room is created (creator auto-joined)
  Future<void> _onRoomCreated(Map<String, dynamic> data) async {
    try {
      final roomId = data['room_id'] as String?;
      final ownerId = data['owner_id'] as String?;
      final sessionId = data['session_id'] as String?; // Get sessionId for player ID
      final maxSize = data['max_size'] as int? ?? 4;
      final minPlayers = data['min_players'] as int? ?? 2;
      final gameType = data['game_type'] as String? ?? 'multiplayer';
      final isCoinRequired =
          data['is_coin_required'] as bool? ?? data['isCoinRequired'] as bool? ?? true;

      if (roomId == null || ownerId == null || sessionId == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎣 room_created: missing roomId, ownerId, or sessionId');
        }
        return;
      }

      if (LOGGING_SWITCH) {
        _logger.info('🎣 room_created: Creating game for room $roomId with player ID $sessionId');
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

      // Fetch user profile data (full name, profile picture) for creator
      String playerName = 'Player_${sessionId.substring(0, sessionId.length > 8 ? 8 : sessionId.length)}';
      String? profilePicture;
      String? usernameFromProfile;
      
      if (ownerId != null && ownerId.isNotEmpty) {
        try {
          final profileResult = await server.pythonClient.getUserProfile(ownerId);
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
            
            if (LOGGING_SWITCH) {
              _logger.info('✅ Fetched creator profile: name=$playerName, username=$usernameFromProfile, hasPicture=${profilePicture != null && profilePicture.isNotEmpty}');
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.warning('⚠️ Failed to fetch creator profile: ${profileResult['error']}');
            }
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ Error fetching creator profile: $e');
          }
          // Continue with default name
        }
      }

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
            // Creator added as first player (auto-joined); stable `hum_<userId>` seat id.
            {
              'id': canonicalMultiplayerHumanPlayerId(sessionId, ownerId ?? ''),
              'name': playerName,
              'isHuman': true,
              'status': 'waiting',
              'hand': <Map<String, dynamic>>[],
              'visible_cards': <Map<String, dynamic>>[],
              'points': 0,
              'known_cards': <String, dynamic>{},
              'collection_rank_cards': <String>[],
              'isActive': true,  // Required for winner calculation and same rank play filtering
              'userId': ownerId,  // Store userId (MongoDB ObjectId) for coin deduction
              if (usernameFromProfile != null && usernameFromProfile.isNotEmpty) 'username': usernameFromProfile,  // Store username for display
              if (profilePicture != null && profilePicture.isNotEmpty) 'profile_picture': profilePicture,
            }
          ],
          'drawPile': <Map<String, dynamic>>[],
          'discardPile': <Map<String, dynamic>>[],
          'originalDeck': <Map<String, dynamic>>[],
          'isCoinRequired': isCoinRequired,
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
          'state_version': store.bumpOutboundStateVersion(roomId),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (LOGGING_SWITCH) {
        _logger.info('✅ Game created for room $roomId with creator session $sessionId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error in _onRoomCreated: $e');
      }
    }
  }

  /// Hook callback: room_joined
  /// Add player to existing game and send snapshot
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
        if (userId != null &&
            userId.isNotEmpty &&
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
            
            if (LOGGING_SWITCH) {
              _logger.info('✅ Fetched user profile: name=$playerName, username=$usernameFromProfile, hasPicture=${profilePicture != null && profilePicture.isNotEmpty}');
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
      }

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
            '🎣 room_joined: seat $canonicalSeat already present after await — skip duplicate add',
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
            '🎣 room_joined: user $userId already in roster after await — skip duplicate add',
          );
        }
        _sendGameSnapshot(sessionId, roomId);
        return;
      }

      if (roomDifficulty != null) {
        final stateRoot = store.getState(roomId);
        stateRoot['roomDifficulty'] = roomDifficulty;
      }

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

      final initialPlayerCount = players.length;
      players.removeWhere((p) => p['id'] == gamePlayerId);
      final newPlayerCount = players.length;
      
      if (initialPlayerCount == newPlayerCount) {
        if (LOGGING_SWITCH) {
          _logger.warning(
              '🎣 leave_room: Player $gamePlayerId not found in game state players list');
        }
        if (LOGGING_SWITCH) {
          _logger.warning('🎣 leave_room: Current players: ${players.map((p) => p['id']?.toString() ?? 'unknown').join(', ')}');
        }
      }
      
      gameState['players'] = players;
      gameState['playerCount'] = newPlayerCount; // Update player count
      
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
        'state_version': store.bumpOutboundStateVersion(roomId),
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info(
            '✅ Broadcasted game_state_updated after player $gamePlayerId left room $roomId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ Error in _onLeaveRoom: $e');
      }
    }
  }

  /// Hook callback: room_closed
  /// Cleanup game instance and state
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

  void sendGameSnapshotToSession(String sessionId, String roomId) =>
      _sendGameSnapshot(sessionId, roomId);

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

      server.sendToSession(sessionId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': gs,
        if (ownerId != null) 'owner_id': ownerId,
        'state_version': store.bumpOutboundStateVersion(roomId),
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


