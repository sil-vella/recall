import '../../../tools/logging/logger.dart';

/// Message processing only - no state management
/// Handles message formatting, validation, and processing logic
class MessageService {
  static final Logger _log = Logger();
  static final MessageService _instance = MessageService._internal();
  factory MessageService() => _instance;
  MessageService._internal();

  // Message processing methods
  void processGameMessage(Map<String, dynamic> message) {
    try {
      _log.info('📨 MessageService: Processing game message: ${message['type']}');
      
      if (!isValidMessage(message)) {
        _log.warning('⚠️ MessageService: Invalid game message received');
        return;
      }
      
      final messageType = message['type'] as String? ?? '';
      final data = message['data'] as Map<String, dynamic>? ?? {};
      
      switch (messageType) {
        case 'game_started':
          _processGameStartedMessage(data);
          break;
        case 'game_ended':
          _processGameEndedMessage(data);
          break;
        case 'turn_changed':
          _processTurnChangedMessage(data);
          break;
        case 'card_played':
          _processCardPlayedMessage(data);
          break;
        case 'recall_called':
          _processRecallCalledMessage(data);
          break;
        case 'player_joined':
          _processPlayerJoinedMessage(data);
          break;
        case 'player_left':
          _processPlayerLeftMessage(data);
          break;
        default:
          _log.info('📨 MessageService: Unknown game message type: $messageType');
      }
      
    } catch (e) {
      _log.error('❌ MessageService: Error processing game message: $e');
    }
  }

  void processRoomMessage(Map<String, dynamic> message) {
    try {
      _log.info('📨 MessageService: Processing room message: ${message['type']}');
      
      if (!isValidMessage(message)) {
        _log.warning('⚠️ MessageService: Invalid room message received');
        return;
      }
      
      final messageType = message['type'] as String? ?? '';
      final data = message['data'] as Map<String, dynamic>? ?? {};
      
      switch (messageType) {
        case 'room_created':
          _processRoomCreatedMessage(data);
          break;
        case 'room_joined':
          _processRoomJoinedMessage(data);
          break;
        case 'room_left':
          _processRoomLeftMessage(data);
          break;
        case 'room_closed':
          _processRoomClosedMessage(data);
          break;
        default:
          _log.info('📨 MessageService: Unknown room message type: $messageType');
      }
      
    } catch (e) {
      _log.error('❌ MessageService: Error processing room message: $e');
    }
  }

  void processSystemMessage(Map<String, dynamic> message) {
    try {
      _log.info('📨 MessageService: Processing system message: ${message['type']}');
      
      if (!isValidMessage(message)) {
        _log.warning('⚠️ MessageService: Invalid system message received');
        return;
      }
      
      final messageType = message['type'] as String? ?? '';
      final data = message['data'] as Map<String, dynamic>? ?? {};
      
      switch (messageType) {
        case 'connection_status':
          _processConnectionStatusMessage(data);
          break;
        case 'error':
          _processErrorMessage(data);
          break;
        case 'warning':
          _processWarningMessage(data);
          break;
        case 'info':
          _processInfoMessage(data);
          break;
        default:
          _log.info('📨 MessageService: Unknown system message type: $messageType');
      }
      
    } catch (e) {
      _log.error('❌ MessageService: Error processing system message: $e');
    }
  }

  // Message formatting methods
  Map<String, dynamic> formatGameMessage(String type, Map<String, dynamic> data) {
    return {
      'type': type,
      'category': 'game',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
      'id': _generateMessageId(),
    };
  }

  Map<String, dynamic> formatRoomMessage(String type, Map<String, dynamic> data) {
    return {
      'type': type,
      'category': 'room',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
      'id': _generateMessageId(),
    };
  }

  Map<String, dynamic> formatSystemMessage(String type, Map<String, dynamic> data) {
    return {
      'type': type,
      'category': 'system',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
      'id': _generateMessageId(),
    };
  }

  // Message validation methods
  bool isValidMessage(Map<String, dynamic> message) {
    if (message == null) return false;
    
    // Check required fields
    if (!message.containsKey('type')) return false;
    if (!message.containsKey('timestamp')) return false;
    
    // Check type is string
    if (message['type'] is! String) return false;
    if ((message['type'] as String).isEmpty) return false;
    
    // Check timestamp is valid
    try {
      DateTime.parse(message['timestamp'] as String);
    } catch (e) {
      return false;
    }
    
    return true;
  }

  bool isValidGameMessage(Map<String, dynamic> message) {
    if (!isValidMessage(message)) return false;
    
    final validGameTypes = [
      'game_started', 'game_ended', 'turn_changed', 'card_played',
      'recall_called', 'player_joined', 'player_left', 'game_state_updated'
    ];
    
    return validGameTypes.contains(message['type']);
  }

  bool isValidRoomMessage(Map<String, dynamic> message) {
    if (!isValidMessage(message)) return false;
    
    final validRoomTypes = [
      'room_created', 'room_joined', 'room_left', 'room_closed',
      'room_message', 'room_event'
    ];
    
    return validRoomTypes.contains(message['type']);
  }

  bool isValidSystemMessage(Map<String, dynamic> message) {
    if (!isValidMessage(message)) return false;
    
    final validSystemTypes = [
      'connection_status', 'error', 'warning', 'info', 'debug'
    ];
    
    return validSystemTypes.contains(message['type']);
  }

  // Private processing methods
  void _processGameStartedMessage(Map<String, dynamic> data) {
    final gameId = data['game_id'] as String? ?? '';
    final gameName = data['game_name'] as String? ?? '';
    _log.info('📨 MessageService: Game started - $gameName ($gameId)');
  }

  void _processGameEndedMessage(Map<String, dynamic> data) {
    final gameId = data['game_id'] as String? ?? '';
    final winner = data['winner'] as Map<String, dynamic>?;
    final winnerName = winner?['name'] as String? ?? 'Unknown';
    _log.info('📨 MessageService: Game ended - Winner: $winnerName ($gameId)');
  }

  void _processTurnChangedMessage(Map<String, dynamic> data) {
    final playerName = data['player_name'] as String? ?? 'Unknown';
    _log.info('📨 MessageService: Turn changed to: $playerName');
  }

  void _processCardPlayedMessage(Map<String, dynamic> data) {
    final cardName = data['card_name'] as String? ?? 'Unknown';
    final playerName = data['player_name'] as String? ?? 'Unknown';
    _log.info('📨 MessageService: Card played - $cardName by $playerName');
  }

  void _processRecallCalledMessage(Map<String, dynamic> data) {
    final playerName = data['player_name'] as String? ?? 'Unknown';
    _log.info('📨 MessageService: Recall called by: $playerName');
  }

  void _processPlayerJoinedMessage(Map<String, dynamic> data) {
    final playerName = data['player_name'] as String? ?? 'Unknown';
    _log.info('📨 MessageService: Player joined: $playerName');
  }

  void _processPlayerLeftMessage(Map<String, dynamic> data) {
    final playerName = data['player_name'] as String? ?? 'Unknown';
    final reason = data['reason'] as String? ?? 'Unknown';
    _log.info('📨 MessageService: Player left: $playerName (Reason: $reason)');
  }

  void _processRoomCreatedMessage(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String? ?? '';
    final roomName = data['room_name'] as String? ?? '';
    _log.info('📨 MessageService: Room created - $roomName ($roomId)');
  }

  void _processRoomJoinedMessage(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String? ?? '';
    final roomName = data['room_name'] as String? ?? '';
    _log.info('📨 MessageService: Joined room - $roomName ($roomId)');
  }

  void _processRoomLeftMessage(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String? ?? '';
    final reason = data['reason'] as String? ?? 'Unknown';
    _log.info('📨 MessageService: Left room: $roomId (Reason: $reason)');
  }

  void _processRoomClosedMessage(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String? ?? '';
    final reason = data['reason'] as String? ?? 'Unknown';
    _log.info('📨 MessageService: Room closed: $roomId (Reason: $reason)');
  }

  void _processConnectionStatusMessage(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'unknown';
    _log.info('📨 MessageService: Connection status: $status');
  }

  void _processErrorMessage(Map<String, dynamic> data) {
    final error = data['error'] as String? ?? 'Unknown error';
    final details = data['details'] as String? ?? '';
    _log.error('📨 MessageService: Error - $error${details.isNotEmpty ? ' ($details)' : ''}');
  }

  void _processWarningMessage(Map<String, dynamic> data) {
    final warning = data['warning'] as String? ?? 'Unknown warning';
    _log.warning('📨 MessageService: Warning - $warning');
  }

  void _processInfoMessage(Map<String, dynamic> data) {
    final info = data['info'] as String? ?? 'Unknown info';
    _log.info('📨 MessageService: Info - $info');
  }

  // Utility methods
  String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecondsSinceEpoch % 1000)}';
  }

  // Message priority methods
  int getMessagePriority(String messageType) {
    switch (messageType) {
      case 'error':
        return 3; // High priority
      case 'warning':
        return 2; // Medium priority
      case 'game_ended':
      case 'recall_called':
        return 2; // Medium priority
      case 'info':
      case 'connection_status':
        return 1; // Low priority
      default:
        return 0; // Default priority
    }
  }

  bool isHighPriorityMessage(String messageType) {
    return getMessagePriority(messageType) >= 2;
  }

  // Message filtering methods
  bool shouldDisplayMessage(String messageType, String category) {
    // Filter out debug messages in production
    if (messageType == 'debug') return false;
    
    // Always show errors and warnings
    if (messageType == 'error' || messageType == 'warning') return true;
    
    // Show game and room messages
    if (category == 'game' || category == 'room') return true;
    
    // Show important system messages
    if (category == 'system' && messageType == 'connection_status') return true;
    
    return false;
  }
}
