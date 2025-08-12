import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../managers/state_manager.dart';
import '../../managers/websockets/ws_event_manager.dart';
import '../../managers/websockets/websocket_manager.dart';
import '../../../tools/logging/logger.dart';

class RecallMessageManager {
  static final Logger _log = Logger();
  static final RecallMessageManager _instance = RecallMessageManager._internal();
  factory RecallMessageManager() => _instance;
  RecallMessageManager._internal();

  final StateManager _stateManager = StateManager();
  final WSEventManager _wsEvents = WSEventManager.instance;

  final StreamController<List<Map<String, dynamic>>> _roomMessagesController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _sessionMessagesController = StreamController<List<Map<String, dynamic>>>.broadcast();

  // In-memory boards (roomId -> list), session board (global for this client)
  final Map<String, List<Map<String, dynamic>>> _roomBoards = {};
  final List<Map<String, dynamic>> _sessionBoard = [];

  Stream<List<Map<String, dynamic>>> roomMessages(String roomId) {
    return _roomMessagesController.stream.where((_) => true);
  }

  Stream<List<Map<String, dynamic>>> get sessionMessages => _sessionMessagesController.stream;

  void initialize() {
    // Register state domains
    _stateManager.registerModuleState("recall_messages", {
      'session': <Map<String, dynamic>>[],
      'rooms': <String, List<Map<String, dynamic>>>{},
      'lastUpdated': DateTime.now().toIso8601String(),
    });

    // Hook to WS events (standard)
    _wireWebsocketEvents();

    // Hook custom socket events directly
    final socket = WebSocketManager.instance.socket;
    socket?.on('recall_message', (data) {
      final scope = data['scope']?.toString();
      if (scope == 'room') {
        final roomId = data['target_id']?.toString() ?? '';
        if (roomId.isNotEmpty) _addRoomMessage(roomId, level: data['level'], title: data['title'], message: data['message'], data: Map<String, dynamic>.from(data));
      } else {
        _addSessionMessage(level: data['level'], title: data['title'], message: data['message'], data: Map<String, dynamic>.from(data));
      }
    });
    socket?.on('room_closed', (data) {
      final roomId = data['room_id']?.toString() ?? '';
      if (roomId.isNotEmpty) {
        _addRoomMessage(roomId, level: 'warning', title: 'Room closed', message: data['reason']?.toString() ?? 'Closed', data: Map<String, dynamic>.from(data));
      }
    });
    _log.info('✅ RecallMessageManager initialized');
  }

  void _wireWebsocketEvents() {
    // Connection lifecycle
    _wsEvents.onEvent('connection', (data) {
      final status = data['status']?.toString() ?? 'unknown';
      _addSessionMessage(level: 'info', title: 'Connection', message: 'Status: $status', data: data);
    });

    // Room events
    _wsEvents.onEvent('room', (data) {
      final action = data['action']?.toString() ?? '';
      final roomId = data['roomId']?.toString() ?? '';
      if (roomId.isEmpty) return;
      switch (action) {
        case 'created':
          _addRoomMessage(roomId, level: 'success', title: 'Room created', message: roomId, data: data);
          break;
        case 'joined':
          _addRoomMessage(roomId, level: 'success', title: 'Joined room', message: roomId, data: data);
          break;
        case 'left':
          _addRoomMessage(roomId, level: 'info', title: 'Left room', message: roomId, data: data);
          break;
        default:
          _addRoomMessage(roomId, level: 'info', title: 'Room event', message: action, data: data);
      }
    });

    // Message channel (generic)
    _wsEvents.onEvent('message', (data) {
      final roomId = data['roomId']?.toString() ?? '';
      final msg = data['message']?.toString() ?? '';
      if (roomId.isNotEmpty) {
        _addRoomMessage(roomId, level: 'info', title: 'Message', message: msg, data: data);
      } else {
        _addSessionMessage(level: 'info', title: 'Message', message: msg, data: data);
      }
    });

    // Errors
    _wsEvents.onEvent('error', (data) {
      _addSessionMessage(level: 'error', title: 'Error', message: data['error']?.toString() ?? 'Error', data: data);
    });

    // Custom: recall_message and room_closed notifications
    _wsEvents.onEvent('recall_message', (data) {
      final scope = data['scope']?.toString();
      if (scope == 'room') {
        final roomId = data['target_id']?.toString() ?? '';
        if (roomId.isNotEmpty) _addRoomMessage(roomId, level: data['level'], title: data['title'], message: data['message'], data: data);
      } else {
        _addSessionMessage(level: data['level'], title: data['title'], message: data['message'], data: data);
      }
    });

    _wsEvents.onEvent('room_closed', (data) {
      final roomId = data['room_id']?.toString() ?? '';
      if (roomId.isNotEmpty) {
        _addRoomMessage(roomId, level: 'warning', title: 'Room closed', message: data['reason']?.toString() ?? 'Closed', data: data);
      }
    });
  }

  void _addRoomMessage(String roomId, {required String? level, required String? title, required String? message, Map<String, dynamic>? data}) {
    final entry = _entry(level, title, message, data);
    final list = _roomBoards.putIfAbsent(roomId, () => <Map<String, dynamic>>[]);
    list.add(entry);
    if (list.length > 200) list.removeAt(0);
    _emitState();
  }

  void _addSessionMessage({required String? level, required String? title, required String? message, Map<String, dynamic>? data}) {
    final entry = _entry(level, title, message, data);
    _sessionBoard.add(entry);
    if (_sessionBoard.length > 200) _sessionBoard.removeAt(0);
    _emitState();
  }

  Map<String, dynamic> _entry(String? level, String? title, String? message, Map<String, dynamic>? data) {
    return {
      'level': (level ?? 'info'),
      'title': title ?? '',
      'message': message ?? '',
      'data': data ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  void _emitState() {
    // Push to StateManager for UI consumption
    final roomsCopy = <String, List<Map<String, dynamic>>>{};
    _roomBoards.forEach((k, v) => roomsCopy[k] = List<Map<String, dynamic>>.from(v));
    _stateManager.updateModuleState('recall_messages', {
      'session': List<Map<String, dynamic>>.from(_sessionBoard),
      'rooms': roomsCopy,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  List<Map<String, dynamic>> getSessionBoard() => List<Map<String, dynamic>>.from(_sessionBoard);
  List<Map<String, dynamic>> getRoomBoard(String roomId) => List<Map<String, dynamic>>.from(_roomBoards[roomId] ?? const []);

  void dispose() {
    _roomMessagesController.close();
    _sessionMessagesController.close();
  }
}


