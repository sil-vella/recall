#!/usr/bin/env dart
/// Simple Dart Game Service for Recall Game
/// 
/// This service acts as a bridge between Python and Dart game logic.
/// It communicates with the Python backend to handle game operations.

import 'dart:io';
import 'dart:convert';

const bool LOGGING_SWITCH = true;

class SimpleDartGameService {
  SimpleDartGameService() {
    print('Simple Dart Game Service initialized');
  }

  Map<String, dynamic> handleMessage(Map<String, dynamic> message) {
    final String action = message['action'] ?? '';
    final String gameId = message['game_id'] ?? '';
    final Map<String, dynamic> data = message['data'] ?? {};

    if (LOGGING_SWITCH) {
      print('Handling action: $action for game: $gameId');
    }

    switch (action) {
      case 'health_check':
        return {'status': 'healthy', 'message': 'Dart service is running'};
      
      case 'create_game':
        return _handleCreateGame(gameId, data);
      
      case 'join_game':
      case 'add_player':
        return _handleAddPlayer(gameId, data);
      
      case 'start_game':
        return _handleStartGame(gameId, data);
      
      case 'player_action':
        return _handlePlayerAction(gameId, data);
      
      case 'get_game_state':
        return _handleGetGameState(gameId, data);
      
      default:
        return {'status': 'error', 'message': 'Unknown action: $action'};
    }
  }

  Map<String, dynamic> _handleCreateGame(String gameId, Map<String, dynamic> data) {
    if (LOGGING_SWITCH) {
      print('Creating game: $gameId');
    }
    return {
      'status': 'success', 
      'message': 'Game created',
      'game_id': gameId,
      'max_players': data['max_players'] ?? 4,
      'min_players': data['min_players'] ?? 2,
      'permission': data['permission'] ?? 'public'
    };
  }

  Map<String, dynamic> _handleAddPlayer(String gameId, Map<String, dynamic> data) {
    final playerId = data['player_id'] ?? '';
    final playerName = data['player_name'] ?? 'Player';
    final playerType = data['player_type'] ?? 'human';
    
    if (LOGGING_SWITCH) {
      print('Adding player: $playerName ($playerId) to game: $gameId');
    }
    return {
      'status': 'success',
      'message': 'Player added',
      'player_id': playerId,
      'player_name': playerName,
      'player_type': playerType
    };
  }

  Map<String, dynamic> _handleStartGame(String gameId, Map<String, dynamic> data) {
    if (LOGGING_SWITCH) {
      print('Starting game: $gameId');
    }
    return {
      'status': 'success',
      'message': 'Game started',
      'game_id': gameId
    };
  }

  Map<String, dynamic> _handlePlayerAction(String gameId, Map<String, dynamic> data) {
    final action = data['action'] ?? '';
    final playerId = data['player_id'] ?? '';
    
    if (LOGGING_SWITCH) {
      print('Player action: $action by player: $playerId in game: $gameId');
    }
    
    switch (action) {
      case 'draw_from_deck':
        return {
          'status': 'success',
          'message': 'Card drawn',
          'action': action,
          'player_id': playerId
        };
      case 'play_card':
        return {
          'status': 'success',
          'message': 'Card played',
          'action': action,
          'player_id': playerId,
          'card_index': data['card_index'] ?? 0
        };
      case 'call_recall':
        return {
          'status': 'success',
          'message': 'Recall called',
          'action': action,
          'player_id': playerId
        };
      default:
        return {
          'status': 'error',
          'message': 'Unknown player action: $action'
        };
    }
  }

  Map<String, dynamic> _handleGetGameState(String gameId, Map<String, dynamic> data) {
    if (LOGGING_SWITCH) {
      print('Getting game state for: $gameId');
    }
    return {
      'status': 'success',
      'message': 'Game state retrieved',
      'game_state': {
        'game_id': gameId,
        'status': 'active',
        'phase': 'player_turn',
        'current_player': 0,
        'players': [],
        'deck_count': 52,
        'discard_pile': []
      }
    };
  }
}

void main() {
  if (LOGGING_SWITCH) {
    print('Simple Dart Game Service Started');
  }
  
  final service = SimpleDartGameService();

  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
    try {
      final Map<String, dynamic> message = jsonDecode(line);
      final response = service.handleMessage(message);
      stdout.writeln(jsonEncode(response));
    } catch (e) {
      if (LOGGING_SWITCH) {
        print('Error processing message: $e');
      }
      stdout.writeln(jsonEncode({
        'status': 'error',
        'message': 'Failed to process message: $e',
      }));
    }
  });
}