#!/usr/bin/env dart
/// Dart Game Service for Recall Game
/// 
/// This service runs as a persistent subprocess and handles all game logic
/// while communicating with Python via stdin/stdout JSON messages.

import 'dart:io';
import 'dart:convert';
import '../../../../../../flutter_base_05/lib/modules/recall_game/game_logic/game_state.dart';
import '../../../../../../flutter_base_05/lib/modules/recall_game/game_logic/game_round.dart';
import '../../../../../../flutter_base_05/lib/modules/recall_game/game_logic/models/player.dart';

const bool LOGGING_SWITCH = true;

class DartGameService {
  final Map<String, GameState> activeGames = {};
  final Map<String, GameRound> gameRounds = {};
  final Map<String, GameStateManager> gameStateManagers = {};
  
  DartGameService() {
    if (LOGGING_SWITCH) {
      print('Dart Game Service started');
    }
  }

  void start() {
    // Listen for JSON messages from Python via stdin
    stdin.transform(utf8.decoder).transform(LineSplitter()).listen(
      (String line) {
        try {
          final Map<String, dynamic> message = json.decode(line);
          handleMessage(message);
        } catch (e) {
          if (LOGGING_SWITCH) {
            print('Invalid JSON message: $e');
          }
          sendError('Invalid JSON message: $e');
        }
      },
      onError: (error) {
        if (LOGGING_SWITCH) {
          print('Error reading stdin: $error');
        }
        sendError('Error reading stdin: $error');
      },
    );
  }

  void handleMessage(Map<String, dynamic> message) {
    try {
      final String action = message['action'] ?? '';
      final String gameId = message['game_id'] ?? '';
      final Map<String, dynamic> data = message['data'] ?? {};

      switch (action) {
        case 'create_game':
          handleCreateGame(gameId, data);
          break;
        case 'join_game':
          handleJoinGame(gameId, data);
          break;
        case 'player_action':
          handlePlayerAction(gameId, data);
          break;
        case 'get_game_state':
          handleGetGameState(gameId);
          break;
        case 'get_player_state':
          handleGetPlayerState(gameId, data);
          break;
        case 'cleanup_game':
          handleCleanupGame(gameId);
          break;
        case 'health_check':
          handleHealthCheck();
          break;
        default:
          sendError('Unknown action: $action');
      }
    } catch (e) {
      sendError('Error handling message: $e');
    }
  }

  void handleCreateGame(String gameId, Map<String, dynamic> data) {
    try {
      // Create game state manager
      final gameStateManager = GameStateManager();
      gameStateManagers[gameId] = gameStateManager;
      
      // Create game state
      final gameState = GameState(
        gameId: gameId,
        maxPlayers: data['max_players'] ?? 4,
        minPlayers: data['min_players'] ?? 2,
        permission: data['permission'] ?? 'public',
        appManager: null, // Will be set later if needed
      );
      
      activeGames[gameId] = gameState;
      
      // Create game round
      final gameRound = GameRound(gameState);
      gameRounds[gameId] = gameRound;
      
      sendSuccess({
        'action': 'create_game',
        'game_id': gameId,
        'status': 'created',
        'game_state': gameState.toDict(),
      });
    } catch (e) {
      sendError('Error creating game: $e');
    }
  }

  void handleJoinGame(String gameId, Map<String, dynamic> data) {
    try {
      final gameState = activeGames[gameId];
      if (gameState == null) {
        sendError('Game not found: $gameId');
        return;
      }

      final String playerId = data['player_id'] ?? '';
      final String playerName = data['player_name'] ?? '';
      final String playerType = data['player_type'] ?? 'human';

      if (playerType == 'human') {
        final player = HumanPlayer(playerId: playerId, name: playerName);
        gameState.addPlayer(player);
      } else {
        final player = ComputerPlayer(
          playerId: playerId, 
          name: playerName,
          difficulty: data['difficulty'] ?? 'medium',
        );
        gameState.addPlayer(player);
      }

      sendSuccess({
        'action': 'join_game',
        'game_id': gameId,
        'player_id': playerId,
        'status': 'joined',
        'game_state': gameState.toDict(),
      });
    } catch (e) {
      sendError('Error joining game: $e');
    }
  }

  void handlePlayerAction(String gameId, Map<String, dynamic> data) {
    try {
      final gameRound = gameRounds[gameId];
      if (gameRound == null) {
        sendError('Game round not found: $gameId');
        return;
      }

      final String sessionId = data['session_id'] ?? '';
      final String action = data['action'] ?? '';
      
      // Route the action through the game round
      final result = gameRound.onPlayerAction(sessionId, data);
      
      sendSuccess({
        'action': 'player_action',
        'game_id': gameId,
        'session_id': sessionId,
        'action_type': action,
        'result': result,
        'game_state': activeGames[gameId]?.toDict(),
      });
    } catch (e) {
      sendError('Error handling player action: $e');
    }
  }

  void handleGetGameState(String gameId) {
    try {
      final gameState = activeGames[gameId];
      if (gameState == null) {
        sendError('Game not found: $gameId');
        return;
      }

      sendSuccess({
        'action': 'get_game_state',
        'game_id': gameId,
        'game_state': gameState.toDict(),
      });
    } catch (e) {
      sendError('Error getting game state: $e');
    }
  }

  void handleGetPlayerState(String gameId, Map<String, dynamic> data) {
    try {
      final gameState = activeGames[gameId];
      if (gameState == null) {
        sendError('Game not found: $gameId');
        return;
      }

      final String playerId = data['player_id'] ?? '';
      final player = gameState.players[playerId];
      if (player == null) {
        sendError('Player not found: $playerId');
        return;
      }

      sendSuccess({
        'action': 'get_player_state',
        'game_id': gameId,
        'player_id': playerId,
        'player_state': player.toDict(),
      });
    } catch (e) {
      sendError('Error getting player state: $e');
    }
  }

  void handleCleanupGame(String gameId) {
    try {
      activeGames.remove(gameId);
      gameRounds.remove(gameId);
      gameStateManagers.remove(gameId);
      
      sendSuccess({
        'action': 'cleanup_game',
        'game_id': gameId,
        'status': 'cleaned_up',
      });
    } catch (e) {
      sendError('Error cleaning up game: $e');
    }
  }

  void handleHealthCheck() {
    sendSuccess({
      'action': 'health_check',
      'status': 'healthy',
      'active_games': activeGames.length,
      'service': 'dart_game_service',
    });
  }

  void sendSuccess(Map<String, dynamic> data) {
    final response = {
      'success': true,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (LOGGING_SWITCH) {
      print(json.encode(response));
    }
  }

  void sendError(String message) {
    final response = {
      'success': false,
      'error': message,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (LOGGING_SWITCH) {
      print(json.encode(response));
    }
  }
}

void main() {
  final service = DartGameService();
  service.start();
}
