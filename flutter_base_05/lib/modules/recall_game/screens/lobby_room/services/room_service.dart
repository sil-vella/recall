import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../../core/managers/websockets/ws_event_manager.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../utils/recall_game_helpers.dart';

class RoomService {
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final WSEventManager _wsEventManager = WSEventManager.instance;
  final Logger _logger = Logger();

  /// Validates room settings before creation
  bool isValidRoomSettings(Map<String, dynamic> settings) {
    final requiredFields = ['roomName', 'maxPlayers', 'minPlayers'];
    
    for (final field in requiredFields) {
      if (!settings.containsKey(field) || settings[field] == null) {
        _logger.error('❌ Missing required field: $field');
        return false;
      }
    }

    final maxPlayers = settings['maxPlayers'] as int;
    final minPlayers = settings['minPlayers'] as int;
    
    if (maxPlayers < minPlayers) {
      _logger.error('❌ Max players cannot be less than min players');
      return false;
    }
    
    if (maxPlayers > 8 || minPlayers < 2) {
      _logger.error('❌ Invalid player count range');
      return false;
    }

    return true;
  }

  /// Creates a new room using the validated event system
  /// Returns a Future that completes when room creation is successful
  /// Emits events for UI to handle state updates
  Future<Map<String, dynamic>> createRoom(Map<String, dynamic> roomSettings) async {
    try {
      // Check if connected before creating room
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot create room: WebSocket not connected");
        throw Exception('Cannot create room: WebSocket not connected');
      }
      
      // Validate room settings
      if (!isValidRoomSettings(roomSettings)) {
        throw Exception('Invalid room settings');
      }
      
      // 🎯 Use validated event emitter for room creation
      _logger.info("🏠 Creating room using validated system...");
      
      // Create a completer to wait for the room creation to complete
      final completer = Completer<Map<String, dynamic>>();
      
      // Set up one-time listener for room creation success
      _wsEventManager.onceEvent('create_room_success', (data) {
        _logger.info("✅ Room creation completed successfully");
        
        completer.complete({
          'success': true,
          'room_data': data,
        });
      });
      
      // Set up one-time listener for room creation failure
      _wsEventManager.onceEvent('create_room_error', (data) {
        _logger.error("❌ Room creation failed: $data");
        completer.completeError(Exception(data['message'] ?? 'Room creation failed'));
      });
      
      // Emit the create room event
      final result = await RecallGameHelpers.createRoom(
        roomName: roomSettings['roomName'],
        maxPlayers: roomSettings['maxPlayers'],
        minPlayers: roomSettings['minPlayers'],
        permission: roomSettings['permission'] ?? 'public',
        gameType: roomSettings['gameType'] ?? 'classic',
        turnTimeLimit: roomSettings['turnTimeLimit'] ?? 30,
        autoStart: roomSettings['autoStart'] ?? true,
        password: roomSettings['password'],
      );
      
      _logger.info("🏠 Validated create room result: $result");
      
      // Set timeout to prevent hanging
      Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Room creation timeout'));
        }
      });
      
      return await completer.future;
      
    } catch (e) {
      _logger.error("❌ Error creating room: $e");
      rethrow;
    }
  }

  /// Joins an existing room
  /// Emits events for UI to handle state updates
  Future<Map<String, dynamic>> joinRoom(String roomId, {String? password}) async {
    try {
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot join room: WebSocket not connected");
        throw Exception('Cannot join room: WebSocket not connected');
      }

      _logger.info("🚪 Joining room: $roomId");
      
      // Create a completer to wait for the join room to complete
      final completer = Completer<Map<String, dynamic>>();
      
      // Set up one-time listener for room join success
      _wsEventManager.onceEvent('room_joined', (data) {
        _logger.info("✅ Successfully joined room");
        
        completer.complete({
          'success': true,
          'room_data': data,
        });
      });
      
      // Set up one-time listener for room join failure
      _wsEventManager.onceEvent('join_room_error', (data) {
        _logger.error("❌ Failed to join room: $data");
        completer.completeError(Exception(data['message'] ?? 'Failed to join room'));
      });
      
      // Emit the join room event
      final result = await RecallGameHelpers.joinGame(roomId, 'current_user');
      
      _logger.info("🚪 Validated join room result: $result");
      
      // Set timeout to prevent hanging
      Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Join room timeout'));
        }
      });
      
      return await completer.future;
      
    } catch (e) {
      _logger.error("❌ Error joining room: $e");
      rethrow;
    }
  }

  /// Leaves the current room
  /// Emits events for UI to handle state updates
  Future<void> leaveRoom() async {
    try {
      if (!_websocketManager.isConnected) {
        _logger.error("❌ Cannot leave room: WebSocket not connected");
        throw Exception('Cannot leave room: WebSocket not connected');
      }

      _logger.info("🚪 Leaving current room");
      
      // Create a completer to wait for the leave room to complete
      final completer = Completer<void>();
      
      // Set up one-time listener for room leave success
      _wsEventManager.onceEvent('room_left', (data) {
        _logger.info("✅ Successfully left room");
        completer.complete();
      });
      
      // Emit the leave room event
      final result = await RecallGameHelpers.leaveGame(
        gameId: 'current_room',
        reason: 'User left room',
      );
      
      _logger.info("🚪 Validated leave room result: $result");
      
      // Set timeout to prevent hanging
      Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Leave room timeout'));
        }
      });
      
      await completer.future;
      
    } catch (e) {
      _logger.error("❌ Error leaving room: $e");
      rethrow;
    }
  }

  /// Gets the event manager for UI to subscribe to room events
  WSEventManager get eventManager => _wsEventManager;

  /// Disposes of the service
  void dispose() {
    // Clean up any remaining listeners if needed
  }
}