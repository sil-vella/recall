import 'package:flutter/material.dart';
import 'dart:async';
import '../../../00_base/screen_base.dart';
import '../../../managers/websockets/websocket_manager.dart';
import '../../../managers/websockets/ws_event_manager.dart';
import '../../../managers/state_manager.dart';
import '../../../managers/websockets/websocket_events.dart';
import 'package:provider/provider.dart';
import '../../providers/recall_game_provider.dart';
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
  BaseScreenState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends BaseScreenState<LobbyScreen> {
  
  // Controllers
  final TextEditingController _roomIdController = TextEditingController();
  
  // State variables - only transient UI state
  bool _isLoading = false;
  
  // Managers
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final StateManager _stateManager = StateManager();
  final RoomService _roomService = RoomService();

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
    // This is now handled by the provider
    final provider = Provider.of<RecallGameProvider>(context, listen: false);
    await provider.loadPublicRooms();
  }

  Future<void> _createRoom(Map<String, dynamic> roomSettings) async {
    final provider = Provider.of<RecallGameProvider>(context, listen: false);
    await provider.createRoom(roomSettings);
  }

  Future<void> _joinRoom(String roomId) async {
    final provider = Provider.of<RecallGameProvider>(context, listen: false);
    await provider.joinRoom(roomId);
  }

  Future<void> _leaveRoom(String roomId) async {
    final provider = Provider.of<RecallGameProvider>(context, listen: false);
    await provider.leaveRoom(roomId);
  }

  // Form clearing is now handled in the modal

  void _initializeRoomState() {
    // State is now managed by StateManager, no need to initialize local variables
    // Room state is managed by StateManager
  }

  void _setupEventCallbacks() {
    _roomService.setupEventCallbacks(
      (action, roomId) {
        if (action == 'joined') {
          _showSnackBar('Successfully joined room: $roomId');
        } else if (action == 'left') {
          _showSnackBar('Left room: $roomId');
        } else if (action == 'created') {
          _showSnackBar('Room created: $roomId');
        }
      },
      (error) {
        _showSnackBar('Error: $error', isError: true);
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
        
        return Consumer<RecallGameProvider>(
          builder: (context, provider, child) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Connection Status
                  ConnectionStatusWidget(websocketManager: _websocketManager),

                  const SizedBox(height: 24),

                  // Create Room Section
                  CreateRoomWidget(
                    isLoading: provider.isLoading,
                    isConnected: isConnected,
                    onCreateRoom: _createRoom,
                  ),

                  const SizedBox(height: 24),

                  // Join Room Section
                  JoinRoomWidget(
                    isLoading: provider.isLoading,
                    isConnected: isConnected,
                    onJoinRoom: () => _joinRoom(_roomIdController.text.trim()),
                    roomIdController: _roomIdController,
                  ),

                  const SizedBox(height: 24),

                  // Current Room Info
                  CurrentRoomWidget(
                    currentRoomInfo: provider.currentRoom,
                    currentRoomId: provider.currentRoomId,
                    isConnected: isConnected,
                    onLeaveRoom: () => _leaveRoom(provider.currentRoomId!),
                  ),

                  const SizedBox(height: 24),

                  // Public Rooms Section
                  RoomListWidget(
                    title: 'Public Rooms',
                    rooms: provider.publicRooms,
                    isLoading: provider.isLoading,
                    isConnected: isConnected,
                    onJoinRoom: _joinRoom,
                    currentRoomId: provider.currentRoomId,
                    onLeaveRoom: provider.currentRoomId != null ? (roomId) => _leaveRoom(roomId) : null,
                    emptyMessage: 'No public rooms available',
                  ),

                  const SizedBox(height: 24),

                  // My Rooms Section
                  RoomListWidget(
                    title: 'My Rooms',
                    rooms: provider.myRooms,
                    isLoading: false,
                    isConnected: isConnected,
                    onJoinRoom: _joinRoom,
                    currentRoomId: provider.currentRoomId,
                    onLeaveRoom: provider.currentRoomId != null ? (roomId) => _leaveRoom(roomId) : null,
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