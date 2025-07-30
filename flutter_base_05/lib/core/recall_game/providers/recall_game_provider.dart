import 'package:flutter/foundation.dart';
import '../../managers/state_manager.dart';
import '../screens/lobby_room/services/room_service.dart';
import '../../../../tools/logging/logger.dart';

/// Main Provider for Recall Game state management
/// Provides type-safe access to game state and business logic
class RecallGameProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final StateManager _stateManager = StateManager();
  final RoomService _roomService = RoomService();
  
  // Private state variables
  bool _isInRoom = false;
  String? _currentRoomId;
  Map<String, dynamic>? _currentRoom;
  List<Map<String, dynamic>> _publicRooms = [];
  List<Map<String, dynamic>> _myRooms = [];
  bool _isLoading = false;
  String? _error;

  // Getters for type-safe access
  bool get isInRoom => _isInRoom;
  String? get currentRoomId => _currentRoomId;
  Map<String, dynamic>? get currentRoom => _currentRoom;
  List<Map<String, dynamic>> get publicRooms => _publicRooms;
  List<Map<String, dynamic>> get myRooms => _myRooms;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Initialize the provider and load initial state
  Future<void> initialize() async {
    _logger.info('🎮 Initializing RecallGameProvider');
    
    // Load state from StateManager
    await _loadStateFromManager();
    
    // Initialize WebSocket connection
    await _roomService.initializeWebSocket();
    
    // Load public rooms
    await loadPublicRooms();
    
    _logger.info('✅ RecallGameProvider initialized');
  }

  /// Load state from StateManager
  Future<void> _loadStateFromManager() async {
    try {
      final state = _stateManager.getModuleState<Map<String, dynamic>>("recall_game");
      if (state != null) {
        _isInRoom = state['isInRoom'] ?? false;
        _currentRoomId = state['currentRoomId'];
        _currentRoom = state['currentRoom'];
        _publicRooms = (state['rooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        _myRooms = (state['myRooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        
        _logger.info('📊 Loaded state from StateManager');
      }
    } catch (e) {
      _logger.error('❌ Error loading state from StateManager: $e');
    }
  }

  /// Update StateManager with current state
  void _updateStateManager() {
    try {
      final state = {
        'isInRoom': _isInRoom,
        'currentRoomId': _currentRoomId,
        'currentRoom': _currentRoom,
        'rooms': _publicRooms,
        'myRooms': _myRooms,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      _stateManager.updateModuleState("recall_game", state);
      _logger.info('📊 Updated StateManager');
    } catch (e) {
      _logger.error('❌ Error updating StateManager: $e');
    }
  }

  /// Load public rooms from backend
  Future<void> loadPublicRooms() async {
    try {
      _setLoading(true);
      _clearError();
      
      final rooms = await _roomService.loadPublicRooms();
      _publicRooms = rooms;
      
      _updateStateManager();
      notifyListeners();
      
      _logger.info('📊 Loaded ${rooms.length} public rooms');
    } catch (e) {
      _setError('Failed to load public rooms: $e');
      _logger.error('❌ Error loading public rooms: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Create a new room
  Future<void> createRoom(Map<String, dynamic> roomSettings) async {
    try {
      _setLoading(true);
      _clearError();
      
      final newRoom = await _roomService.createRoom(roomSettings);
      
      // Update current room state
      _isInRoom = true;
      _currentRoomId = newRoom['room_id'];
      _currentRoom = newRoom;
      
      // Add to my rooms if not already there
      if (!_myRooms.any((room) => room['room_id'] == newRoom['room_id'])) {
        _myRooms = [..._myRooms, newRoom];
      }
      
      // Add to public rooms if it's public
      if (roomSettings['permission'] == 'public') {
        if (!_publicRooms.any((room) => room['room_id'] == newRoom['room_id'])) {
          _publicRooms = [..._publicRooms, newRoom];
        }
      }
      
      _updateStateManager();
      notifyListeners();
      
      _logger.info('✅ Room created successfully: ${newRoom['room_name']}');
    } catch (e) {
      _setError('Failed to create room: $e');
      _logger.error('❌ Error creating room: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Join a room
  Future<void> joinRoom(String roomId) async {
    try {
      _setLoading(true);
      _clearError();
      
      await _roomService.joinRoom(roomId);
      
      // Find room in public rooms or my rooms
      final room = _publicRooms.firstWhere(
        (r) => r['room_id'] == roomId,
        orElse: () => _myRooms.firstWhere(
          (r) => r['room_id'] == roomId,
          orElse: () => throw Exception('Room not found'),
        ),
      );
      
      _isInRoom = true;
      _currentRoomId = roomId;
      _currentRoom = room;
      
      _updateStateManager();
      notifyListeners();
      
      _logger.info('✅ Joined room: $roomId');
    } catch (e) {
      _setError('Failed to join room: $e');
      _logger.error('❌ Error joining room: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Leave current room
  Future<void> leaveRoom(String roomId) async {
    try {
      _setLoading(true);
      _clearError();
      
      await _roomService.leaveRoom(roomId);
      
      _isInRoom = false;
      _currentRoomId = null;
      _currentRoom = null;
      
      _updateStateManager();
      notifyListeners();
      
      _logger.info('✅ Left room: $roomId');
    } catch (e) {
      _setError('Failed to leave room: $e');
      _logger.error('❌ Error leaving room: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Clear current error
  void _clearError() {
    _error = null;
  }

  /// Set error message
  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Clear error (public method)
  void clearError() {
    _clearError();
    notifyListeners();
  }

  @override
  void dispose() {
    _logger.info('🛑 RecallGameProvider disposed');
    super.dispose();
  }
} 