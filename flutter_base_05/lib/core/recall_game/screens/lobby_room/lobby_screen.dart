import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../managers/websockets/websocket_manager.dart';
import '../../../managers/state_manager.dart';
import '../../../managers/websockets/websocket_events.dart';
import '../../../00_base/screen_base.dart';
import 'widgets/connection_status_widget.dart';
import 'widgets/create_room_widget.dart';
import 'widgets/join_room_widget.dart';
import 'widgets/current_room_widget.dart';
import 'widgets/room_list_widget.dart';
import 'services/room_service.dart';

class LobbyScreen extends BaseScreen {
  const LobbyScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Game Lobby';

  @override
  _LobbyScreenState createState() => _LobbyScreenState();
}

class _LobbyScreenState extends BaseScreenState<LobbyScreen> {
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final RoomService _roomService = RoomService();
  final TextEditingController _roomIdController = TextEditingController();
  
  // State variables - only transient UI state
  bool _isLoading = false;
  
  // Managers
  final StateManager _stateManager = StateManager();

  @override
  void initState() {
    super.initState();
    _initializeWebSocket().then((_) {
      _loadPublicRooms();
      _setupEventCallbacks();
      _initializeRoomState();
    });
  }

  Future<void> _initializeWebSocket() async {
    await _roomService.initializeWebSocket();
  }

  @override
  void dispose() {
    
    // Clean up event callbacks
    _roomService.cleanupEventCallbacks();
    
    super.dispose();
  }

  Future<void> _loadPublicRooms() async {
    try {
      await _roomService.loadPublicRooms();
    } catch (e) {
      _showSnackBar('Failed to load public rooms: $e', isError: true);
    }
  }

  Future<void> _createRoom(Map<String, dynamic> roomSettings) async {
    try {
      await _roomService.createRoom(roomSettings);
      _showSnackBar('Room created successfully!');
    } catch (e) {
      _showSnackBar('Failed to create room: $e', isError: true);
    }
  }

  Future<void> _joinRoom(String roomId) async {
    try {
      await _roomService.joinRoom(roomId);
      _showSnackBar('Joined room: $roomId');
    } catch (e) {
      _showSnackBar('Failed to join room: $e', isError: true);
    }
  }

  Future<void> _leaveRoom(String roomId) async {
    try {
      await _roomService.leaveRoom(roomId);
      // Don't show success message here - let the event callbacks handle it
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to leave room: $e', isError: true);
      }
    }
  }

  // Form clearing is now handled in the modal

  void _initializeRoomState() {
    // State is now managed by StateManager, no need to initialize local variables
    // Room state is managed by StateManager
  }

  void _setupEventCallbacks() {
    _roomService.setupEventCallbacks(
      (action, roomId) {
        if (mounted) {
          if (action == 'joined') {
            _showSnackBar('Successfully joined room: $roomId');
          } else if (action == 'left') {
            _showSnackBar('Left room: $roomId');
          } else if (action == 'created') {
            _showSnackBar('Room created: $roomId');
          }
        }
      },
      (error) {
        if (mounted) {
          _showSnackBar('Error: $error', isError: true);
        }
      },
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return StreamBuilder<ConnectionStatusEvent>(
      stream: _websocketManager.connectionStatus,
      builder: (context, connectionSnapshot) {
        final isConnected = connectionSnapshot.data?.status == ConnectionStatus.connected || _websocketManager.isConnected;
        
        return Consumer<StateManager>(
          builder: (context, stateManager, child) {
            // Get recall game state from StateManager
            final recallState = stateManager.getModuleState<Map<String, dynamic>>("recall_game") ?? {};
            final isLoading = recallState['isLoading'] ?? false;
            final currentRoom = recallState['currentRoom'];
            final currentRoomId = recallState['currentRoomId'];
            final publicRooms = (recallState['rooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
            final myRooms = (recallState['myRooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
            
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Connection Status
                  ConnectionStatusWidget(websocketManager: _websocketManager),
                  
                  const SizedBox(height: 20),
                  
                  // Create Room Section
                  CreateRoomWidget(
                    isLoading: isLoading,
                    isConnected: isConnected,
                    onCreateRoom: _createRoom,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Join Room Section
                  JoinRoomWidget(
                    isLoading: isLoading,
                    isConnected: isConnected,
                    onJoinRoom: () => _joinRoom(_roomIdController.text.trim()),
                    roomIdController: _roomIdController,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Current Room Info
                  if (currentRoom != null)
                    CurrentRoomWidget(
                      currentRoomInfo: currentRoom,
                      currentRoomId: currentRoomId,
                      isConnected: isConnected,
                      onLeaveRoom: () => _leaveRoom(currentRoomId!),
                    ),
                  
                  const SizedBox(height: 20),
                  
                  // Public Rooms List
                  RoomListWidget(
                    title: 'Public Rooms',
                    rooms: publicRooms,
                    isLoading: isLoading,
                    isConnected: isConnected,
                    onJoinRoom: _joinRoom,
                    currentRoomId: currentRoomId,
                    onLeaveRoom: currentRoomId != null ? (roomId) => _leaveRoom(roomId) : null,
                    emptyMessage: 'No public rooms available',
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // My Rooms List
                  RoomListWidget(
                    title: 'My Rooms',
                    rooms: myRooms,
                    isLoading: false,
                    isConnected: isConnected,
                    onJoinRoom: _joinRoom,
                    currentRoomId: currentRoomId,
                    onLeaveRoom: currentRoomId != null ? (roomId) => _leaveRoom(roomId) : null,
                    emptyMessage: 'You haven\'t created any rooms yet',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
} 