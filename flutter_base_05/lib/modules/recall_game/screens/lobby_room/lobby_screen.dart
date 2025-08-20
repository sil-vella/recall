import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import 'widgets/connection_status_widget.dart';
import 'widgets/create_room_widget.dart';
import 'widgets/join_room_widget.dart';
import 'widgets/current_room_widget.dart';
import 'widgets/room_list_widget.dart';
import 'widgets/room_message_board_widget.dart';
import 'widgets/pending_games_widget.dart';
import 'services/room_service.dart';

import '../../widgets/feature_slot.dart';
import 'features/lobby_features.dart';
import 'widgets/message_board_widget.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../utils/recall_game_helpers.dart';


class LobbyScreen extends BaseScreen {
  const LobbyScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Game Lobby';

  @override
  _LobbyScreenState createState() => _LobbyScreenState();
}

class _LobbyScreenState extends BaseScreenState<LobbyScreen> {
  final RoomService _roomService = RoomService();
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final TextEditingController _roomIdController = TextEditingController();
  
  final LobbyFeatureRegistrar _featureRegistrar = LobbyFeatureRegistrar();

  @override
  void initState() {
    super.initState();
    
    _initializeWebSocket().then((_) {
      _setupEventCallbacks();
      _initializeRoomState();
      _featureRegistrar.registerDefaults(context);
    });
  }

  Future<void> _initializeWebSocket() async {
    try {
      // Initialize WebSocket manager if not already initialized
      if (!_websocketManager.isInitialized) {
        final initialized = await _websocketManager.initialize();
        if (!initialized) {
          _showSnackBar('Failed to initialize WebSocket', isError: true);
          return;
        }
      }
      
      // Connect to WebSocket if not already connected
      if (!_websocketManager.isConnected) {
        final connected = await _websocketManager.connect();
        if (!connected) {
          _showSnackBar('Failed to connect to WebSocket', isError: true);
          return;
        }
        _showSnackBar('WebSocket connected successfully!');
      } else {
        _showSnackBar('WebSocket already connected!');
      }
    } catch (e) {
      _showSnackBar('WebSocket initialization error: $e', isError: true);
    }
  }
  
  @override
  void dispose() {
    // Clean up event callbacks - now handled by WSEventManager
    _featureRegistrar.unregisterAll();
    
    super.dispose();
  }

  Future<void> _createRoom(Map<String, dynamic> roomSettings) async {
    try {
      // First ensure WebSocket is connected
      if (!_websocketManager.isConnected) {
        _showSnackBar('Connecting to WebSocket...', isError: false);
        final connected = await _websocketManager.connect();
        if (!connected) {
          _showSnackBar('Failed to connect to WebSocket. Cannot create room.', isError: true);
          return;
        }
        _showSnackBar('WebSocket connected! Creating room...', isError: false);
      }
      
      // Now proceed with room creation
      final result = await _roomService.createRoom(roomSettings);
      if (result['success'] == true) {
        final roomData = result['room_data'] as Map<String, dynamic>?;
        if (roomData != null) {
          // Update state to refresh MyRoomsWidget
          final currentState = StateManager().getModuleState<Map<String, dynamic>>("recall_game") ?? {};
          final currentMyCreatedRooms = (currentState['myCreatedRooms'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          
          // Add to myCreatedRooms if not already there
          if (!currentMyCreatedRooms.any((room) => room['room_id'] == roomData['room_id'])) {
            RecallGameHelpers.updateUIState({
              'myCreatedRooms': [...currentMyCreatedRooms, roomData],
            });
          }
          
          if (mounted) _showSnackBar('Room created successfully!');
        } else {
          if (mounted) _showSnackBar('Room created but no data received', isError: true);
        }
      } else {
        if (mounted) _showSnackBar('Failed to create room', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Failed to create room: $e', isError: true);
    }
  }

  Future<void> _joinRoom(String roomId) async {
    try {
      // First ensure WebSocket is connected
      if (!_websocketManager.isConnected) {
        _showSnackBar('Connecting to WebSocket...', isError: false);
        final connected = await _websocketManager.connect();
        if (!connected) {
          _showSnackBar('Failed to connect to WebSocket. Cannot join room.', isError: true);
          return;
        }
        _showSnackBar('WebSocket connected! Joining room...', isError: false);
      }
      
      // Now proceed with room joining
      final result = await _roomService.joinRoom(roomId);
      if (result['success'] == true) {
        if (mounted) {
          _showSnackBar('Joined room: $roomId');
        }
      } else {
        if (mounted) _showSnackBar('Failed to join room', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Failed to join room: $e', isError: true);
    }
  }

  Future<void> _leaveRoom(String roomId) async {
    try {
      await _roomService.leaveRoom();
      if (mounted) {
        _showSnackBar('Left room: $roomId');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to leave room: $e', isError: true);
      }
    }
  }

  void _initializeRoomState() {
    // State is now managed by StateManager, no need to initialize local variables
    // Room state is managed by StateManager
  }

  void _setupEventCallbacks() {
    // Event callbacks are now handled by WSEventManager
    // No need to set up specific callbacks here
    // The WSEventManager handles all WebSocket events automatically
  }

  void _showSnackBar(String message, {bool isError = false}) {
    // Check if the widget is still mounted before accessing context
    if (!mounted) return;
    
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
    // Screen doesn't read state directly - widgets handle their own subscriptions
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

          // Pending Games (fetched on demand)
          PendingGamesWidget(
            title: 'Available Games',
            onJoinRoom: _joinRoom,
            emptyMessage: 'No games available to join',
          ),

          const SizedBox(height: 20),

          // Session Message Board
          MessageBoardWidget(),

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
          const RoomMessageBoardWidget(),
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
  }
} 