/// Game Event Coordinator for Recall Game
///
/// This module handles all WebSocket event coordination for the Recall game,
/// including event registration, routing, and handling.

import 'package:recall/tools/logging/logger.dart';

const bool loggingSwitch = false;

class GameEventCoordinator {
  /// Coordinates all WebSocket events for the Recall game
  
  final dynamic gameStateManager;
  final dynamic websocketManager;
  List<String> registeredEvents = [];
  
  GameEventCoordinator(this.gameStateManager, this.websocketManager);

  bool registerGameEventListeners() {
    /// Register WebSocket event listeners for Recall game events
    try {
      // Get the WebSocket event listeners from the WebSocket manager
      final eventListeners = websocketManager?.eventListeners;
      if (eventListeners == null) {
        return false;
      }
      
      // Define all game events
      final gameEvents = [
        'start_match',
        'draw_card', 
        'play_card',
        'discard_card',
        'take_from_discard',
        'call_recall',
        'same_rank_play',
        'jack_swap',
        'queen_peek',
        'completed_initial_peek',
      ];
      
      // Register each event listener
      for (final eventName in gameEvents) {
        // Create a wrapper function that captures the event name
        final eventHandler = (String sessionId, Map<String, dynamic> data) {
          return handleGameEvent(sessionId, eventName, data);
        };
        
        // eventListeners.registerCustomListener(eventName, eventHandler);
        registeredEvents.add(eventName);
      }
      return true;
      
    } catch (e) {
      return false;
    }
  }

  bool handleGameEvent(String sessionId, String eventName, Map<String, dynamic> data) {
    /// Handle incoming game events and route to appropriate handlers
    try {
      Logger().info('Handling game event event_name: $eventName data: $data', isOn: loggingSwitch);
      // Route to appropriate game state manager method
      if (eventName == 'start_match') {
        return gameStateManager?.onStartMatch(sessionId, data) ?? false;
      }
      if (eventName == 'completed_initial_peek') {
        return gameStateManager?.onCompletedInitialPeek(sessionId, data) ?? false;
      } else if (eventName == 'draw_card') {
        // Add action type to data payload for draw_card events
        final dataWithAction = {...data, 'action': 'draw_from_deck'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'play_card') {
        // Add action type to data payload for play_card events
        final dataWithAction = {...data, 'action': 'play_card'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'discard_card') {
        // Add action type to data payload for discard_card events
        final dataWithAction = {...data, 'action': 'discard_card'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'take_from_discard') {
        // Add action type to data payload for take_from_discard events
        final dataWithAction = {...data, 'action': 'take_from_discard'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'call_recall') {
        // Add action type to data payload for call_recall events
        final dataWithAction = {...data, 'action': 'call_recall'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'same_rank_play') {
        // Add action type to data payload for same_rank_play events
        final dataWithAction = {...data, 'action': 'same_rank_play'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'jack_swap') {
        // Add action type to data payload for jack_swap events
        final dataWithAction = {...data, 'action': 'jack_swap'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else if (eventName == 'queen_peek') {
        // Add action type to data payload for queen_peek events
        final dataWithAction = {...data, 'action': 'queen_peek'};
        return _handlePlayerActionThroughRound(sessionId, dataWithAction);
      } else {
        return false;
      }
      
    } catch (e) {
      return false;
    }
  }

  bool _handlePlayerActionThroughRound(String sessionId, Map<String, dynamic> data) {
    /// Handle player actions through the game round
    try {
      final gameId = data['game_id'] ?? data['room_id'];
      Logger().info('Handling player action through round game_id: $gameId data: $data', isOn: loggingSwitch);
      if (gameId == null) {
        return false;
      }
      
      // Get the game from the game state manager
      final game = gameStateManager?.getGame(gameId);
      if (game == null) {
        return false;
      }
      
      // Get the game round handler
      final gameRound = game.getRound();
      if (gameRound == null) {
        return false;
      }
      
      // Handle the player action through the game round and store the result
      final actionResult = gameRound.onPlayerAction(sessionId, data);
      Logger().info('Action result: $actionResult', isOn: loggingSwitch);
      // Return the action result
      return actionResult;
      
    } catch (e) {
      return false;
    }
  }

  // ========= COMMUNICATION METHODS =========
  
  void _sendError(String sessionId, String message) {
    /// Send error message to session
    if (websocketManager != null) {
      // websocketManager.sendToSession(sessionId, 'recall_error', {'message': message});
    }
  }

  void _broadcastEvent(String roomId, Map<String, dynamic> payload) {
    /// Broadcast event to room
    try {
      final eventType = payload['event_type'];
      if (eventType != null && websocketManager != null) {
        final eventPayload = Map<String, dynamic>.from(payload);
        eventPayload.remove('event_type');
        // websocketManager.socketio.emit(eventType, eventPayload, room: roomId);
      }
    } catch (e) {
      // Handle error
    }
  }

  bool _sendToPlayer(String gameId, String playerId, String event, Map<String, dynamic> data) {
    /// Send event to specific player
    try {
      final game = gameStateManager?.getGame(gameId);
      if (game == null) {
        return false;
      }
      final sessionId = game.getPlayerSession(playerId);
      if (sessionId == null) {
        return false;
      }
      // websocketManager.sendToSession(sessionId, event, data);
      return true;
    } catch (e) {
      return false;
    }
  }

  bool _sendToAllPlayers(String gameId, String event, Map<String, dynamic> data) {
    /// Send event to all players in game using direct room broadcast
    try {
      Logger().info('Sending event to all players game_id: $gameId event: $event data: $data', isOn: loggingSwitch);
      // Use direct room broadcast instead of looping through players
      // websocketManager.broadcastToRoom(gameId, event, data);
      return true;
    } catch (e) {
      Logger().error('Error sending to all players: $e', isOn: loggingSwitch);
      return false;
    }
  }

  void _sendGameStateUpdate(String gameId) {
    /// Send complete game state update to all players
    final game = gameStateManager?.getGame(gameId);
    if (game != null) {
      final payload = {
        'event_type': 'game_state_updated',
        'game_id': gameId,
        'game_state': gameStateManager?._toFlutterGameData(game),
      };
      _sendToAllPlayers(gameId, 'game_state_updated', payload);
    }
  }

  void _sendGameStatePartialUpdate(String gameId, List<String> changedProperties) {
    /// Send partial game state update with only changed properties to all players
    try {
      Logger().info('Sending partial game state update for game_id: $gameId changed_properties: $changedProperties', isOn: loggingSwitch);
      final game = gameStateManager?.getGame(gameId);
      if (game == null) {
        return;
      }
      
      // Get full game state in Flutter format
      final fullGameState = gameStateManager?._toFlutterGameData(game);
      
      // DEBUG: Log the full game state phase
      Logger().info('🔍 _sendGameStatePartialUpdate DEBUG:', isOn: loggingSwitch);
      Logger().info('🔍   Game ID: $gameId', isOn: loggingSwitch);
      Logger().info('🔍   Changed properties: $changedProperties', isOn: loggingSwitch);
      Logger().info('🔍   Full game state phase: ${fullGameState?['phase'] ?? 'NOT_FOUND'}', isOn: loggingSwitch);
      
      // Extract only the changed properties
      final partialState = <String, dynamic>{};
      final propertyMapping = {
        'phase': 'phase',
        'current_player_id': 'currentPlayer',
        'recall_called_by': 'recallCalledBy',
        'game_ended': 'gameEnded',
        'winner': 'winner',
        'discard_pile': 'discardPile',
        'draw_pile': 'drawPile',
        'last_action_time': 'lastActivityTime',
        'players': 'players', // Special case - includes all players
      };
      
      for (final prop in changedProperties) {
        final flutterKey = propertyMapping[prop];
        if (flutterKey != null && fullGameState != null && fullGameState.containsKey(flutterKey)) {
          partialState[flutterKey] = fullGameState[flutterKey];
          Logger().info('🔍   Extracted $prop -> $flutterKey: ${partialState[flutterKey]}', isOn: loggingSwitch);
        }
      }
      
      // Always include core identifiers
      partialState['gameId'] = gameId;
      partialState['timestamp'] = DateTime.now().toIso8601String();
      
      // DEBUG: Log the final partial state being sent
      Logger().info('🔍 Final partial state being sent:', isOn: loggingSwitch);
      Logger().info('🔍   partial_state: $partialState', isOn: loggingSwitch);
      
      final payload = {
        'event_type': 'game_state_partial_update',
        'game_id': gameId,
        'changed_properties': changedProperties,
        'partial_game_state': partialState,
      };
      Logger().info('Sending partial game state update payload: $payload', isOn: loggingSwitch);
      _sendToAllPlayers(gameId, 'game_state_partial_update', payload);
      
    } catch (e) {
      // Handle error
    }
  }

  void _sendPlayerStateUpdate(String gameId, String playerId) {
    /// Send player state update including hand to the specific player
    try {
      Logger().info('Sending player state update for game_id: $gameId player_id: $playerId', isOn: loggingSwitch);
      final game = gameStateManager?.getGame(gameId);
      if (game == null) {
        Logger().info('Game not found for player state update: $gameId', isOn: loggingSwitch);
        return;
      }
      
      if (!game.players.containsKey(playerId)) {
        Logger().info('Player not found in game for state update: $playerId', isOn: loggingSwitch);
        return;
      }
      
      final player = game.players[playerId];
      
      // Get player session ID
      final sessionId = game.playerSessions[playerId];
      if (sessionId == null) {
        // Computer players don't have session IDs, but their status should still be updated in game state
        if (playerId.startsWith('computer_')) {
          Logger().info('Computer player $playerId - no session ID needed', isOn: loggingSwitch);
          return;
        } else {
          Logger().info('No session ID found for player $playerId', isOn: loggingSwitch);
          return;
        }
      }
      
      // Convert player to Flutter format using GameStateManager
      final playerData = gameStateManager?._toFlutterPlayerData(
        player, 
        isCurrent: (game.currentPlayerId == playerId),
      );
      
      // Create player state update payload
      final payload = {
        'event_type': 'player_state_updated',
        'game_id': gameId,
        'player_id': playerId,
        'player_data': playerData,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Send to the specific player
      Logger().info('Sending player_state_updated to session $sessionId for player $playerId with status ${player?.status.name}', isOn: loggingSwitch);
      // websocketManager.sendToSession(sessionId, 'player_state_updated', payload);
      
    } catch (e) {
      Logger().error('Error in _sendPlayerStateUpdate: $e', isOn: loggingSwitch);
    }
  }

  void _sendPlayerStateUpdateToAll(String gameId) {
    /// Send player state update to all players in the game
    try {
      final game = gameStateManager?.getGame(gameId);
      if (game == null) {
        return;
      }
      
      // Send player state update to each player
      for (final entry in game.playerSessions.entries) {
        final playerId = entry.key;
        final sessionId = entry.value;
        if (game.players.containsKey(playerId)) {
          final player = game.players[playerId]!;
          
          // Convert player to Flutter format using GameStateManager
          final playerData = gameStateManager?._toFlutterPlayerData(
            player, 
            isCurrent: (game.currentPlayerId == playerId),
          );
          
          // Create player state update payload
          final payload = {
            'event_type': 'player_state_updated',
            'game_id': gameId,
            'player_id': playerId,
            'player_data': playerData,
            'timestamp': DateTime.now().toIso8601String(),
          };
          
          // Send to the specific player
          // websocketManager.sendToSession(sessionId, 'player_state_updated', payload);
        }
      }
      
    } catch (e) {
      // Handle error
    }
  }

  void _sendRoundCompletionEvent(String gameId, Map<String, dynamic> roundResult) {
    /// Send round completion event to all players using direct room broadcast
    try {
      final payload = {
        'event_type': 'round_completed',
        'game_id': gameId,
        'round_number': roundResult['round_number'],
        'round_duration': roundResult['round_duration'],
        'winner': roundResult['winner'],
        'final_action': roundResult['final_action'],
        'game_phase': roundResult['game_phase'],
        'timestamp': DateTime.now().toIso8601String(),
      };
      // Use direct room broadcast instead of looping through players
      // websocketManager.broadcastToRoom(gameId, 'round_completed', payload);
    } catch (e) {
      // Handle error
    }
  }

  void _sendRecallPlayerJoinedEvents(String roomId, String userId, String sessionId, dynamic game) {
    /// Send recall-specific events when a player joins a room
    try {
      // Convert game to Flutter format using GameStateManager (which has the proper conversion method)
      final gameState = gameStateManager?._toFlutterGameData(game);
      
      // 1. Send new_player_joined event to the room
      // Get the owner_id for this room from the WebSocket manager
      final ownerId = websocketManager?.getRoomCreator(roomId);
      
      final roomPayload = {
        'event_type': 'recall_new_player_joined',
        'room_id': roomId,
        'owner_id': ownerId, // Include owner_id for ownership determination
        'joined_player': {
          'user_id': userId,
          'session_id': sessionId,
          'name': 'Player_${userId.substring(0, userId.length > 8 ? 8 : userId.length)}',
          'joined_at': DateTime.now().toIso8601String(),
        },
        'game_state': gameState,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Send as direct event to the room
      // websocketManager.socketio.emit('recall_new_player_joined', roomPayload, room: roomId);
      
      final userGames = <Map<String, dynamic>>[];
      for (final entry in gameStateManager?.activeGames.entries ?? <String, dynamic>{}.entries) {
        final gameId = entry.key;
        final userGame = entry.value;
        // Check if user is in this game
        if (userGame.players.containsKey(userId)) {
          // Use GameStateManager for data conversion
          final userGameState = gameStateManager?._toFlutterGameData(userGame);
          
          // Get the owner_id for this room from the WebSocket manager
          final ownerId = websocketManager?.getRoomCreator(gameId);
          
          userGames.add({
            'game_id': gameId,
            'room_id': gameId, // Game ID is the same as room ID
            'owner_id': ownerId, // Include owner_id for ownership determination
            'game_state': userGameState,
            'joined_at': DateTime.now().toIso8601String(),
          });
        }
      }
      
      final userPayload = {
        'event_type': 'recall_joined_games',
        'user_id': userId,
        'session_id': sessionId,
        'games': userGames,
        'total_games': userGames.length,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Send as direct event to the specific user's session
      // websocketManager.sendToSession(sessionId, 'recall_joined_games', userPayload);
      
    } catch (e) {
      // Handle error
    }
  }

  List<String> getRegisteredEvents() {
    /// Get list of registered event names
    return List<String>.from(registeredEvents);
  }

  bool isEventRegistered(String eventName) {
    /// Check if a specific event is registered
    return registeredEvents.contains(eventName);
  }

  Map<String, dynamic> healthCheck() {
    /// Perform health check on event coordinator
    try {
      return {
        'status': 'healthy',
        'component': 'game_event_coordinator',
        'details': {
          'registered_events': registeredEvents.length,
          'event_list': registeredEvents,
          'game_state_manager_available': gameStateManager != null,
          'websocket_manager_available': websocketManager != null,
        },
      };
    } catch (e) {
      return {
        'status': 'unhealthy',
        'component': 'game_event_coordinator',
        'details': 'Health check failed: $e',
      };
    }
  }
}
