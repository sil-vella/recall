import 'package:flutter/material.dart';
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
import '../../widgets/feature_slot.dart';
import 'features/lobby_features.dart';
import 'widgets/message_board_widget.dart';
// Provider removed – use StateManager only


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
  
  // Legacy managers (for backward compatibility)
  final StateManager _stateManager = StateManager();
  final LobbyFeatureRegistrar _featureRegistrar = LobbyFeatureRegistrar();
  
  // Unified state management is now handled by BaseScreen

  @override
  void initState() {
    super.initState();
    
    // Using StateManager as SSOT – no Provider
    
    _initializeWebSocket().then((_) {
      _setupEventCallbacks();
      _initializeRoomState();
      _featureRegistrar.registerDefaults(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Load public rooms after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadPublicRooms();
      }
    });
  }

  Future<void> _initializeWebSocket() async {
    await _roomService.initializeWebSocket();
  }

  @override
  void dispose() {
    
    // Clean up event callbacks
    _roomService.cleanupEventCallbacks();
    _featureRegistrar.unregisterAll();
    
    super.dispose();
  }

  Future<void> _loadPublicRooms() async {
    try {
      if (!mounted) return;
      // Use RoomService+StateManager to fetch and store rooms
      await _roomService.loadPublicRooms().then((rooms) {
        final current = _stateManager.getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        _stateManager.updateModuleState('recall_game', {
          ...current,
          'rooms': rooms,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      });
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to load public rooms: $e', isError: true);
      }
    }
  }

  Future<void> _createRoom(Map<String, dynamic> roomSettings) async {
    try {
      final created = await _roomService.createRoom(roomSettings);
      if (created.isNotEmpty) {
        _showSnackBar('Room created successfully!');
      } else {
        _showSnackBar('Failed to create room', isError: true);
      }
    } catch (e) {
      _showSnackBar('Failed to create room: $e', isError: true);
    }
  }

  Future<void> _joinRoom(String roomId) async {
    try {
      await _roomService.joinRoom(roomId);
      if (mounted) {
        _showSnackBar('Joined room: $roomId');
      }
    } catch (e) {
      _showSnackBar('Failed to join room: $e', isError: true);
    }
  }

  Future<void> _leaveRoom(String roomId) async {
    try {
      await _roomService.leaveRoom(roomId);
      if (mounted) {
        _showSnackBar('Left room: $roomId');
      }
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
    // State is now provided by BaseScreen
    return StreamBuilder<ConnectionStatusEvent>(
      stream: _websocketManager.connectionStatus,
      builder: (context, connectionSnapshot) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection Status
              const ConnectionStatusWidget(),
              const SizedBox(height: 20),
              
              // Create Room Section
              CreateRoomWidget(
                onCreateRoom: _createRoom,
              ),
              
              const SizedBox(height: 20),

              // Session Message Board
              MessageBoardWidget(stateManager: _stateManager),

              const SizedBox(height: 20),
              
              // Join Room Section
              JoinRoomWidget(
                onJoinRoom: () => _joinRoom(_roomIdController.text.trim()),
                roomIdController: _roomIdController,
              ),
              
              const SizedBox(height: 20),
              // Second slot in lobby for extra tools/actions (icon-only contract)
              const FeatureSlot(
                scopeKey: LobbyFeatureSlots.scopeKey,
                slotId: LobbyFeatureSlots.slotSecondary,
                title: 'Tools',
                contract: 'icon_action',
                iconSize: 22,
              ),

              const SizedBox(height: 20),
              
              // Current Room Info
              CurrentRoomWidget(
                onLeaveRoom: _leaveRoom,
              ),
              
              const SizedBox(height: 20),

              // Room Message Board (if in room)
              Builder(builder: (context) {
                final wsState = _stateManager.getModuleState<Map<String, dynamic>>('websocket') ?? {};
                final currentRoomId = (wsState['currentRoomId'] ?? '') as String;
                if (currentRoomId.isEmpty) return const SizedBox.shrink();
                return MessageBoardWidget(stateManager: _stateManager, roomId: currentRoomId);
              }),
              
              // Public Rooms List
              RoomListWidget(
                title: 'Public Rooms',
                onJoinRoom: _joinRoom,
                onLeaveRoom: _leaveRoom,
                emptyMessage: 'No public rooms available',
                roomType: 'public',
              ),
              
              const SizedBox(height: 20),
              
              // My Rooms List
              RoomListWidget(
                title: 'My Rooms',
                onJoinRoom: _joinRoom,
                onLeaveRoom: _leaveRoom,
                emptyMessage: 'You haven\'t created any rooms yet',
                roomType: 'my',
              ),
            ],
          ),
        );
      },
    );
  }
} 