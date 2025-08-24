import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import 'widgets/connection_status_widget.dart';
import 'widgets/create_room_widget.dart';
import 'widgets/current_room_widget.dart';
import 'widgets/available_games_widget.dart';
import 'features/lobby_features.dart';
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
  final WebSocketManager _websocketManager = WebSocketManager.instance;
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
      
      // Now proceed with room creation - bypass RoomService and call helper directly
      final result = await RecallGameHelpers.createRoom(
        roomName: roomSettings['roomName'],
        permission: roomSettings['permission'] ?? 'public',
        maxPlayers: roomSettings['maxPlayers'],
        minPlayers: roomSettings['minPlayers'],
        gameType: roomSettings['gameType'] ?? 'classic',
        turnTimeLimit: roomSettings['turnTimeLimit'] ?? 30,
        autoStart: roomSettings['autoStart'] ?? true,
        password: roomSettings['password'],
      );
      if (result['success'] == true) {
        // Room creation initiated successfully - WebSocket events will handle state updates
        if (mounted) _showSnackBar('Room created successfully!');
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
      
      // Now proceed with room joining using helper
      final result = await RecallGameHelpers.joinRoom(
        roomId: roomId,
      );
      
      if (result['success'] == true) {
        if (mounted) _showSnackBar('Successfully joined room!');
      } else {
        final errorMessage = result['error'] ?? 'Failed to join room';
        if (mounted) _showSnackBar(errorMessage, isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Failed to join room: $e', isError: true);
    }
  }

  Future<void> _fetchAvailableGames() async {
    try {
      // Set loading state
      RecallGameHelpers.updateUIState({
        'isLoading': true,
      });

      // Use the helper method to fetch available games
      final result = await RecallGameHelpers.fetchAvailableGames();
      
      if (result['success'] == true) {
        // Extract games from response
        final games = result['games'] ?? [];
        final message = result['message'] ?? 'Games fetched successfully';
        
        // Update state with real game data
        RecallGameHelpers.updateUIState({
          'availableGames': games,
          'isLoading': false,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        
        if (mounted) _showSnackBar(message);
      } else {
        // Handle error from helper method
        final errorMessage = result['error'] ?? 'Failed to fetch games';
        throw Exception(errorMessage);
      }
      
    } catch (e) {
      RecallGameHelpers.updateUIState({
        'isLoading': false,
      });
      if (mounted) _showSnackBar('Failed to fetch available games: $e', isError: true);
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
          
          // Current Room Section
          CurrentRoomWidget(
            onJoinRoom: _joinRoom,
          ),
          const SizedBox(height: 20),
          
          // Create Room Section
          CreateRoomWidget(
            onCreateRoom: _createRoom,
          ),
          const SizedBox(height: 20),
          
          // Available Games Section
          AvailableGamesWidget(
            onFetchGames: _fetchAvailableGames,
          ),
          const SizedBox(height: 20),
        
        ],
      ),
    );
  }
} 