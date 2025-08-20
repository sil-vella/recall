import 'dart:async';
import '../../../core/managers/state_manager.dart';
import '../../../tools/logging/logger.dart';
import '../utils/recall_game_helpers.dart';
import '../utils/recall_event_listener_validator.dart';

class RecallMessageManager {
  static final Logger _log = Logger();
  static final RecallMessageManager _instance = RecallMessageManager._internal();
  factory RecallMessageManager() => _instance;
  RecallMessageManager._internal();

  final StateManager _stateManager = StateManager();

  final StreamController<List<Map<String, dynamic>>> _roomMessagesController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> _sessionMessagesController = StreamController<List<Map<String, dynamic>>>.broadcast();

  // In-memory boards (roomId -> list), session board (global for this client)
  final Map<String, List<Map<String, dynamic>>> _roomBoards = {};
  final List<Map<String, dynamic>> _sessionBoard = [];

  Stream<List<Map<String, dynamic>>> roomMessages(String roomId) {
    return _roomMessagesController.stream.where((_) => true);
  }

  Stream<List<Map<String, dynamic>>> get sessionMessages => _sessionMessagesController.stream;

  Future<bool> initialize() async {
    try {
      _log.info('📨 Initializing RecallMessageManager...');
      
      // Register state domains
      _stateManager.registerModuleState("recall_messages", {
        'session': <Map<String, dynamic>>[],
        'rooms': <String, List<Map<String, dynamic>>>{},
        'lastUpdated': DateTime.now().toIso8601String(),
      });

      // Hook to WS events (standard)
      _wireWebsocketEvents();

      // Recall-specific Socket.IO listeners are centralized in RecallGameCoordinator.
      // We subscribe only via WSEventManager callbacks here.
      _log.info('✅ RecallMessageManager initialized successfully');
      return true;
      
    } catch (e) {
      _log.error('❌ RecallMessageManager initialization failed: $e');
      return false;
    }
  }

  void _wireWebsocketEvents() {
    // Use validated event listener for each message-related event type
    final eventTypes = [
      'connection_status', 'room_event', 'message', 'error',
      'recall_message', 'room_closed',
    ];
    
    for (final eventType in eventTypes) {
      RecallGameEventListenerExtension.onEvent(eventType, (data) {
        switch (eventType) {
          case 'connection_status':
            final status = data['status']?.toString() ?? 'unknown';
            _addSessionMessage(level: 'info', title: 'Connection', message: 'Status: $status', data: data);
            break;
            
          case 'room_event':
            final action = data['action']?.toString() ?? '';
            final roomId = data['room_id']?.toString() ?? '';
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
            break;

          case 'message':
            final roomId = data['room_id']?.toString() ?? '';
            final msg = data['message']?.toString() ?? '';
            if (roomId.isNotEmpty) {
              _addRoomMessage(roomId, level: 'info', title: 'Message', message: msg, data: data);
            } else {
              _addSessionMessage(level: 'info', title: 'Message', message: msg, data: data);
            }
            break;
            
          case 'error':
            _addSessionMessage(level: 'error', title: 'Error', message: data['error']?.toString() ?? 'Error', data: data);
            break;
            
          case 'recall_message':
            final scope = data['scope']?.toString();
            if (scope == 'room') {
              final roomId = data['target_id']?.toString() ?? '';
              if (roomId.isNotEmpty) _addRoomMessage(roomId, level: data['level'], title: data['title'], message: data['message'], data: data);
            } else {
              _addSessionMessage(level: data['level'], title: data['title'], message: data['message'], data: data);
            }
            break;
            
          case 'room_closed':
            final roomId = data['room_id']?.toString() ?? '';
            if (roomId.isNotEmpty) {
              _addRoomMessage(roomId, level: 'warning', title: 'Room closed', message: data['reason']?.toString() ?? 'Closed', data: data);
            }
            break;
        }
      });
    }
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
    // Push to StateManager using validated state updater
    final roomsCopy = <String, List<Map<String, dynamic>>>{};
    _roomBoards.forEach((k, v) => roomsCopy[k] = List<Map<String, dynamic>>.from(v));
    
    RecallGameHelpers.updateUIState({
      'messages': {
        'session': List<Map<String, dynamic>>.from(_sessionBoard),
        'rooms': roomsCopy,
      },
    });
  }

  List<Map<String, dynamic>> getSessionBoard() => List<Map<String, dynamic>>.from(_sessionBoard);
  List<Map<String, dynamic>> getRoomBoard(String roomId) => List<Map<String, dynamic>>.from(_roomBoards[roomId] ?? const []);

  void dispose() {
    _roomMessagesController.close();
    _sessionMessagesController.close();
  }
}