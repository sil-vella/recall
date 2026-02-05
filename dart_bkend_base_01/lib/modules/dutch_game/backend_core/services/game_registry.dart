import '../../utils/platform/shared_imports.dart';
import '../../../dutch_game/backend_core/shared_logic/dutch_game_round.dart';
import '../shared_logic/game_state_callback.dart';
import '../utils/state_queue_validator.dart';
import 'game_state_store.dart';

const bool LOGGING_SWITCH = false; // Enabled for testing game initialization

/// Holds active DutchGameRound instances per room and wires their callbacks
/// to the WebSocket server through ServerGameStateCallback.
class GameRegistry {
  static final GameRegistry instance = GameRegistry._internal();
  final Map<String, DutchGameRound> _roomIdToRound = {};
  final Logger _logger = Logger();

  GameRegistry._internal();

  DutchGameRound getOrCreate(String roomId, WebSocketServer server) {
    return _roomIdToRound.putIfAbsent(roomId, () {
      final callback = ServerGameStateCallbackImpl(roomId, server);
      final round = DutchGameRound(callback, roomId);
      if (LOGGING_SWITCH) {
        _logger.info('GameRegistry: Created DutchGameRound for $roomId');
      }
      return round;
    });
  }

  void dispose(String roomId) {
    _roomIdToRound.remove(roomId);
    GameStateStore.instance.clear(roomId);
    if (LOGGING_SWITCH) {
      _logger.info('GameRegistry: Disposed game for $roomId');
    }
  }

  /// Clear all rounds (reset to init). Use when clearing all games (e.g. mode switch).
  void clearAll() {
    _roomIdToRound.clear();
    if (LOGGING_SWITCH) {
      _logger.info('GameRegistry: clearAll() - cleared all rounds');
    }
  }
}

/// Server implementation of GameStateCallback for backend-authoritative play.
class ServerGameStateCallbackImpl implements GameStateCallback {
  final String roomId;
  final WebSocketServer server;
  final _store = GameStateStore.instance;
  final Logger _logger = Logger();
  final StateQueueValidator _validator = StateQueueValidator.instance;

  /// Get all timer values as a map (for UI consumption)
  /// This is the single source of truth for all timer durations
  /// Static method - doesn't require roomId since values are constant
  static Map<String, int> getAllTimerValues() {
    return {
      'initial_peek': 10,
      'drawing_card': 5,
      'playing_card': 15,
      'same_rank_window': 7,
      'queen_peek': 10,
      'jack_swap': 10,
      'peeking': 7,
      'waiting': 0,
      'default': 30,
    };
  }

  ServerGameStateCallbackImpl(this.roomId, this.server) {
    // Initialize state queue validator with logger callback
    _validator.setLogCallback((String message, {bool isError = false}) {
      if (isError) {
        if (LOGGING_SWITCH) {
          _logger.error(message);
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.info(message);
        }
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
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - onGameStateChanged received turn_events: ${turnEvents.length} events');
      }
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${turnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}');
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - onGameStateChanged received NO turn_events in updates. Keys: ${updates.keys.toList()}');
      }
    }
    
    // Use StateQueueValidator to validate and queue the update
    // The validator will call our update handler with validated updates
    _validator.enqueueUpdate(updates);
  }

  @override
  void sendGameStateToPlayer(String playerId, Map<String, dynamic> updates) {
    // Validate and apply updates to state store (same as onGameStateChanged)
    // But send only to the specific player instead of broadcasting
    if (LOGGING_SWITCH) {
      _logger.info('📤 sendGameStateToPlayer: Sending state update to player $playerId');
    }
    
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
      
      // Filter gameState to remove fields that shouldn't be sent to frontend
      final filteredGameState = _filterGameStateForFrontend(gameState);
      
      // Owner info for gating
      final ownerId = server.getRoomOwner(roomId);
      
      // Extract myCardsToPeek from validated updates if present (for initial peek clearing)
      final myCardsToPeek = validatedUpdates['myCardsToPeek'] as List<dynamic>?;
      
      // Send to single player (playerId = sessionId in this system)
      server.sendToSession(playerId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': filteredGameState,
        'turn_events': turnEvents,
        if (ownerId != null) 'owner_id': ownerId,
        if (myCardsToPeek != null) 'myCardsToPeek': myCardsToPeek, // Include myCardsToPeek if present in updates
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ sendGameStateToPlayer: Sent state update to player $playerId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ sendGameStateToPlayer: Error sending state update to player $playerId: $e');
      }
    }
  }

  @override
  void broadcastGameStateExcept(String excludePlayerId, Map<String, dynamic> updates) {
    // Validate and apply updates to state store (same as onGameStateChanged)
    // But broadcast to all players except the excluded one
    if (LOGGING_SWITCH) {
      _logger.info('📤 broadcastGameStateExcept: Broadcasting state update to all except player $excludePlayerId');
    }
    
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
      
      // Filter gameState to remove fields that shouldn't be sent to frontend
      final filteredGameState = _filterGameStateForFrontend(gameState);
      
      // Extract winners from validatedUpdates (if present) - needed for game end notification
      final winners = validatedUpdates['winners'] as List<dynamic>?;
      
      // Owner info for gating
      final ownerId = server.getRoomOwner(roomId);
      
      // Broadcast to all players except the excluded one (excludePlayerId = sessionId in this system)
      server.broadcastToRoomExcept(roomId, {
        'event': 'game_state_updated',
        'game_id': roomId,
        'game_state': filteredGameState,
        'turn_events': turnEvents,
        if (winners != null) 'winners': winners, // Include winners list for game end notification
        if (ownerId != null) 'owner_id': ownerId,
        'timestamp': DateTime.now().toIso8601String(),
      }, excludePlayerId);
      
      if (LOGGING_SWITCH) {
        _logger.info('✅ broadcastGameStateExcept: Broadcasted state update to all except player $excludePlayerId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('❌ broadcastGameStateExcept: Error broadcasting state update: $e');
      }
    }
  }
  
  /// Filter gameState to remove fields that shouldn't be sent to frontend
  /// Currently removes originalDeck to reduce payload size
  Map<String, dynamic> _filterGameStateForFrontend(Map<String, dynamic> gameState) {
    final filtered = Map<String, dynamic>.from(gameState);
    filtered.remove('originalDeck');
    return filtered;
  }

  /// Apply validated updates to GameStateStore and broadcast
  /// This is called by StateQueueValidator after validation
  void _applyValidatedUpdates(Map<String, dynamic> validatedUpdates) {
    // Log turn_events if present in validated updates
    if (validatedUpdates.containsKey('turn_events')) {
      final turnEventsInUpdates = validatedUpdates['turn_events'] as List<dynamic>? ?? [];
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - _applyValidatedUpdates received turn_events in validatedUpdates: ${turnEventsInUpdates.length} events');
      }
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${turnEventsInUpdates.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}');
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.info('🔍 TURN_EVENTS DEBUG - _applyValidatedUpdates received NO turn_events in validatedUpdates. Keys: ${validatedUpdates.keys.toList()}');
      }
    }
    
    // Merge into state root
    _store.mergeRoot(roomId, validatedUpdates);
    // Read the full state after merge
    final state = _store.getState(roomId);
    final gameState = state['game_state'] as Map<String, dynamic>? ?? {};
    
    // Extract turn_events from root state (they're stored at root level, not in game_state)
    final turnEvents = state['turn_events'] as List<dynamic>? ?? [];
    if (LOGGING_SWITCH) {
      _logger.info('🔍 TURN_EVENTS DEBUG - _applyValidatedUpdates extracted turn_events from root state: ${turnEvents.length} events');
    }
    if (LOGGING_SWITCH) {
      _logger.info('🔍 TURN_EVENTS DEBUG - Turn events details: ${turnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}');
    }
    
    // CRITICAL: If gamePhase is in updates, copy it to game_state['phase'] for client broadcast
    // Frontend expects gamePhase in game_state['phase'], not at root level
    if (validatedUpdates.containsKey('gamePhase')) {
      final phase = validatedUpdates['gamePhase']?.toString();
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
        if (LOGGING_SWITCH) {
          _logger.info('GameStateCallback: Copied gamePhase ($phase) to game_state[phase] ($normalizedPhase) for broadcast');
        }
      }
    }
    // Ensure phase key and playerCount
    gameState['phase'] = gameState['phase'] ?? 'playing';
    gameState['playerCount'] = (gameState['players'] as List<dynamic>? ?? []).length;
    
    // Filter gameState to remove fields that shouldn't be sent to frontend
    final filteredGameState = _filterGameStateForFrontend(gameState);
    
    // Extract winners from validatedUpdates (if present) - needed for game end notification
    final winners = validatedUpdates['winners'] as List<dynamic>?;
    if (winners != null) {
      if (LOGGING_SWITCH) {
        _logger.info('GameStateCallback: Including winners list in broadcast: ${winners.length} winner(s)');
      }
    }
    
    // Owner info for gating
    final ownerId = server.getRoomOwner(roomId);
    if (LOGGING_SWITCH) {
      _logger.info('🔍 TURN_EVENTS DEBUG - Broadcasting game_state_updated with ${turnEvents.length} turn_events');
    }
    if (LOGGING_SWITCH) {
      _logger.info('🔍 TURN_EVENTS DEBUG - Turn events in broadcast: ${turnEvents.map((e) => e is Map ? '${e['cardId']}:${e['actionType']}' : e.toString()).join(', ')}');
    }
    
    server.broadcastToRoom(roomId, {
      'event': 'game_state_updated',
      'game_id': roomId,
      'game_state': filteredGameState,
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
    
    if (LOGGING_SWITCH) {
      _logger.info('GameRegistry: getTimerConfig() for room $roomId - phase: $phase, status: $status');
    }
    
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
    
    if (LOGGING_SWITCH) {
      _logger.info('GameRegistry: getTimerConfig() returning turnTimeLimit: $turnTimeLimit for room $roomId');
    }
    
    return {
      'turnTimeLimit': turnTimeLimit,
      'showInstructions': showInstructions,
    };
  }

  @override
  void triggerLeaveRoom(String playerId) {
    // Only trigger for multiplayer matches (room_*), not practice (practice_room_*)
    if (!roomId.startsWith('room_')) {
      if (LOGGING_SWITCH) {
        _logger.info('GameStateCallback: Skipping auto-leave for non-multiplayer room $roomId (player $playerId)');
      }
      return;
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('GameStateCallback: Triggering auto-leave for player $playerId in room $roomId (2 missed actions)');
    }
    
    try {
      // Get userId from session (playerId = sessionId in this system)
      final userId = server.getUserIdForSession(playerId) ?? playerId;
      
      // Trigger the leave_room hook through the server
      // This will call the _onLeaveRoom handler in DutchGameModule
      server.triggerHook('leave_room', data: {
        'room_id': roomId,
        'session_id': playerId, // playerId = sessionId in this system
        'user_id': userId,
        'left_at': DateTime.now().toIso8601String(),
      });
      
      if (LOGGING_SWITCH) {
        _logger.info('GameStateCallback: Successfully triggered leave_room hook for player $playerId');
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('GameStateCallback: Error triggering leave room for player $playerId: $e');
      }
    }
  }

  @override
  void onGameEnded(List<Map<String, dynamic>> winners, List<Map<String, dynamic>> allPlayers, {int? matchPot}) {
    // Only update stats for multiplayer matches (room_*), not practice (practice_room_*)
    if (!roomId.startsWith('room_')) {
      if (LOGGING_SWITCH) {
        _logger.info('GameStateCallback: Skipping stats update for non-multiplayer room $roomId (practice mode)');
      }
      return;
    }

      final pot = matchPot ?? 0;
      if (LOGGING_SWITCH) {
        _logger.info('GameStateCallback: Game ended for room $roomId - updating statistics for ${allPlayers.length} player(s), match_pot: $pot');
      }

    try {
      // Build list of winner player IDs for quick lookup
      final winnerPlayerIds = winners.map((w) => w['playerId']?.toString() ?? '').toSet();
      
      // Build game_results array for API call
      final gameResults = <Map<String, dynamic>>[];
      
      for (final player in allPlayers) {
        final playerId = player['id']?.toString() ?? '';
        if (playerId.isEmpty) {
          if (LOGGING_SWITCH) {
            _logger.warning('GameStateCallback: Skipping player with empty ID');
          }
          continue;
        }
        
        // Get user_id from session (for human players) or from player object (for comp players)
        var userId = server.getUserIdForSession(playerId);
        if (userId == null) {
          // Fallback: Check if player object has userId (for comp players from database)
          userId = player['userId']?.toString();
          if (userId == null || userId.isEmpty) {
            if (LOGGING_SWITCH) {
              _logger.warning('GameStateCallback: No user_id found for player $playerId (tried session and player object), skipping stats update');
            }
            continue;
          }
          if (LOGGING_SWITCH) {
            _logger.info('GameStateCallback: Using userId from player object for comp player $playerId: $userId');
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
        
        gameResults.add({
          'user_id': userId,
          'is_winner': isWinner,
          'pot': playerPot, // Pot amount for this player (full pot if single winner, split if multiple winners)
          'win_type': winType,
        });
        
        if (LOGGING_SWITCH) {
          _logger.info('GameStateCallback: Added game result for user $userId - winner: $isWinner, pot: $playerPot');
        }
      }
      
      if (gameResults.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.warning('GameStateCallback: No valid game results to send, skipping API call');
        }
        return;
      }
      
      // Call Python API to update statistics
      if (LOGGING_SWITCH) {
        _logger.info('GameStateCallback: Calling Python API to update game statistics');
      }
      server.pythonClient.updateGameStats(gameResults).then((result) {
        if (result['success'] == true) {
          if (LOGGING_SWITCH) {
            _logger.info('GameStateCallback: Successfully updated game statistics');
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.error('GameStateCallback: Failed to update game statistics: ${result['error']}');
          }
        }
      }).catchError((error) {
        if (LOGGING_SWITCH) {
          _logger.error('GameStateCallback: Error updating game statistics: $error');
        }
        // Don't throw - stats update failure shouldn't break the game
      });
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('GameStateCallback: Error in onGameEnded: $e');
      }
      // Don't throw - stats update failure shouldn't break the game
    }
  }
}


