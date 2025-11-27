import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../managers/game_coordinator.dart';
import '../../utils/recall_game_helpers.dart';
import 'widgets/create_game_widget.dart';
import 'widgets/join_game_widget.dart';
import 'widgets/current_games_widget.dart';
import 'widgets/available_games_widget.dart';
import 'widgets/practice_match_widget.dart';
import 'features/lobby_features.dart';


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
      
      // Now proceed with room joining using GameCoordinator
      final gameCoordinator = GameCoordinator();
      final success = await gameCoordinator.joinGame(
        gameId: roomId,
        playerName: 'Player', // TODO: Get actual player name from state
      );
      
      if (success) {
        if (mounted) _showSnackBar('Successfully joined room!');
      } else {
        if (mounted) _showSnackBar('Failed to join room', isError: true);
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

  Future<void> _startPracticeMatch(Map<String, dynamic> practiceSettings) async {
    try {
      // Get current user ID
      final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
      final currentUserId = loginState['userId']?.toString() ?? 'practice_user_${DateTime.now().millisecondsSinceEpoch}';
      
      // Generate practice game ID
      final practiceGameId = 'recall_game_${DateTime.now().millisecondsSinceEpoch}';
      
      // Get current games map
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final games = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      // Create practice game data structure
      final practiceGameData = {
        'gameData': {
          'game_id': practiceGameId,
          'game_type': 'practice',
          'game_state': {
            'phase': 'setup',
            'status': 'inactive',
            'difficulty': practiceSettings['difficulty'] ?? 'medium',
            'showInstructions': practiceSettings['showInstructions'] ?? true,
            'players': [
              {
                'id': currentUserId,
                'name': 'You',
                'status': 'waiting',
                'hand': [],
                'collection_rank': null,
                'collection_rank_cards': [],
                'known_cards': {},
              }
            ],
          },
          'owner_id': currentUserId,
        },
        'gamePhase': 'setup',
        'gameStatus': 'inactive',
        'isRoomOwner': true,
        'isInGame': true,
        'joinedAt': DateTime.now().toIso8601String(),
      };
      
      // Add practice game to games map
      games[practiceGameId] = practiceGameData;
      
      // Update recall game state with practice game data
      RecallGameHelpers.updateUIState({
        'currentGameId': practiceGameId,
        'games': games,
      });
      
      // Navigate to game play screen
      NavigationManager().navigateTo('/recall/game-play');
      
      // Show success message
      if (mounted) {
        _showSnackBar('Practice match started!');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to start practice match: $e', isError: true);
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
          
          // Create and Join Room Section (Side by Side)
          Row(
            children: [
              // Create Room Widget (50% width)
              Expanded(
                child: CreateRoomWidget(
                  onCreateRoom: _createRoom,
                ),
              ),
              const SizedBox(width: 16),
              // Join Room Widget (50% width)
              Expanded(
                child: JoinRoomWidget(
                  onJoinRoom: () {
                    // JoinRoomWidget handles its own room joining logic
                    // This callback is called after successful join request
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Practice Match Section
          PracticeMatchWidget(
            onStartPractice: _startPracticeMatch,
          ),
          const SizedBox(height: 20),
          
          // Current Room Section (moved under Create/Join buttons)
          CurrentRoomWidget(
            onJoinRoom: _joinRoom,
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