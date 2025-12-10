import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../managers/game_coordinator.dart';
import '../../managers/validated_event_emitter.dart';
import '../../../cleco_game/managers/cleco_event_manager.dart';
import '../../practice/practice_mode_bridge.dart';
import '../../backend_core/services/game_state_store.dart';
import '../../../cleco_game/utils/cleco_game_helpers.dart';
import 'widgets/create_game_widget.dart';
import 'widgets/join_game_widget.dart';
import 'widgets/join_random_game_widget.dart';
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
  static const bool LOGGING_SWITCH = false;
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
      // Check if user has enough coins (default 25, can be overridden in roomSettings)
      final requiredCoins = roomSettings['requiredCoins'] as int? ?? 25;
      if (!ClecoGameHelpers.checkCoinsRequirement(requiredCoins: requiredCoins)) {
        if (mounted) _showSnackBar('Insufficient coins to create a game. Required: $requiredCoins', isError: true);
        return;
      }
      
      // Clear practice user data when switching to multiplayer
      ClecoGameHelpers.updateUIState({
        'practiceUser': null,
      });
      
      // Ensure we're in WebSocket mode for multiplayer
      final eventEmitter = ClecoGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.websocket);
      
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
      final result = await ClecoGameHelpers.createRoom(
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
      // Check if user has enough coins (default 25)
      if (!ClecoGameHelpers.checkCoinsRequirement()) {
        if (mounted) _showSnackBar('Insufficient coins to join a game. Required: 25', isError: true);
        return;
      }
      
      // Clear practice user data when switching to multiplayer
      ClecoGameHelpers.updateUIState({
        'practiceUser': null,
      });
      
      // Ensure we're in WebSocket mode for multiplayer
      final eventEmitter = ClecoGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.websocket);
      
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
      ClecoGameHelpers.updateUIState({
        'isLoading': true,
      });

      // Use the helper method to fetch available games
      final result = await ClecoGameHelpers.fetchAvailableGames();
      
      if (result['success'] == true) {
        // Extract games from response
        final games = result['games'] ?? [];
        final message = result['message'] ?? 'Games fetched successfully';
        
        // Update state with real game data
        ClecoGameHelpers.updateUIState({
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
      ClecoGameHelpers.updateUIState({
        'isLoading': false,
      });
      if (mounted) _showSnackBar('Failed to fetch available games: $e', isError: true);
    }
  }

  Future<void> _startPracticeMatch(Map<String, dynamic> practiceSettings) async {
    try {
      final Logger _logger = Logger();
      _logger.info('🎮 _startPracticeMatch: Starting practice match setup', isOn: LOGGING_SWITCH);
      
      // Generate practice mode user data (self-contained, doesn't rely on login module)
      final currentUserId = 'practice_user_${DateTime.now().millisecondsSinceEpoch}';
      final practiceUserData = {
        'userId': currentUserId,
        'displayName': 'Practice Player',
        'isPracticeUser': true,
      };
      _logger.info('🎮 _startPracticeMatch: Generated practice user: $currentUserId', isOn: LOGGING_SWITCH);
      
      // Store practice user data and settings in cleco_game state (accessible to event handlers)
      // Use validated state updater to ensure proper validation
      ClecoGameHelpers.updateUIState({
        'practiceUser': practiceUserData,
        'practiceSettings': practiceSettings,
      });
      _logger.info('🎮 _startPracticeMatch: Stored practice user data and settings in state', isOn: LOGGING_SWITCH);
      _logger.info('🎮 _startPracticeMatch: showInstructions = ${practiceSettings['showInstructions']}', isOn: LOGGING_SWITCH);
      
      // Verify practice user data was stored (read back from state)
      final verifyState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final verifyPracticeUser = verifyState['practiceUser'] as Map<String, dynamic>?;
      _logger.info('🎮 _startPracticeMatch: Verified practice user in state: $verifyPracticeUser', isOn: LOGGING_SWITCH);
      
      // Switch event emitter to practice mode
      final eventEmitter = ClecoGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.practice);
      _logger.info('🎮 _startPracticeMatch: Switched to practice mode', isOn: LOGGING_SWITCH);
      
      // Initialize and start practice session
      final practiceBridge = PracticeModeBridge.instance;
      await practiceBridge.initialize();
      _logger.info('🎮 _startPracticeMatch: Practice bridge initialized', isOn: LOGGING_SWITCH);
      
      final practiceRoomId = await practiceBridge.startPracticeSession(
        userId: currentUserId,
        maxPlayers: 4,
        minPlayers: 2,
        gameType: 'practice',
      );
      _logger.info('🎮 _startPracticeMatch: Practice room created: $practiceRoomId', isOn: LOGGING_SWITCH);
      
      // Get game state from GameStateStore (after hooks have initialized it)
      final gameStateStore = GameStateStore.instance;
      final gameState = gameStateStore.getGameState(practiceRoomId);
      _logger.info('🎮 _startPracticeMatch: Got game state, phase = ${gameState['phase']}', isOn: LOGGING_SWITCH);
      
      // Create gameData structure matching multiplayer format
      final maxPlayersValue = practiceSettings['maxPlayers'] as int? ?? 4;
      final minPlayersValue = practiceSettings['minPlayers'] as int? ?? 2;
      final gameData = {
        'game_id': practiceRoomId,
        'owner_id': currentUserId,
        'game_type': 'practice',
        'game_state': gameState,
        'max_size': maxPlayersValue,
        'min_players': minPlayersValue,
      };
      
      // Extract and normalize phase (matching multiplayer format)
      // Multiplayer normalizes: 'waiting_for_players' -> 'waiting', others -> 'playing'
      final rawPhase = gameState['phase']?.toString();
      final uiPhase = rawPhase == 'waiting_for_players'
          ? 'waiting'
          : (rawPhase ?? 'playing');
      
      // Extract game status
      final gameStatus = gameState['status']?.toString() ?? 'inactive';
      
      // Get current games map
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final games = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      
      // Add/update the current game in the games map (matching multiplayer format)
      // Note: gamePhase is NOT stored in games map - it's stored in main state only
      games[practiceRoomId] = {
        'gameData': gameData,  // Single source of truth
        'gameStatus': gameStatus,
        'isRoomOwner': true,
        'isInGame': true,
        'joinedAt': DateTime.now().toIso8601String(),
      };
      
      // Update UI state to reflect practice game (matching multiplayer format)
      // Store normalized gamePhase in MAIN state (not in games map)
      // CRITICAL: Update currentGameId directly via StateManager first to ensure it's available for slice computation
      _logger.info('🎮 _startPracticeMatch: Updating UI state with currentGameId = $practiceRoomId', isOn: LOGGING_SWITCH);
      
      // Get current state and update critical fields directly (bypasses queue for immediate availability)
      final clecoStateManager = StateManager();
      final currentClecoState = clecoStateManager.getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final updatedClecoState = Map<String, dynamic>.from(currentClecoState);
      
      // Update critical fields directly
      updatedClecoState['currentGameId'] = practiceRoomId;
      updatedClecoState['currentRoomId'] = practiceRoomId;
      updatedClecoState['isInRoom'] = true;
      updatedClecoState['isRoomOwner'] = true;
      updatedClecoState['gameType'] = 'practice';
      updatedClecoState['games'] = games;
      updatedClecoState['gamePhase'] = uiPhase;
      updatedClecoState['currentSize'] = 1;
      updatedClecoState['maxSize'] = maxPlayersValue;
      updatedClecoState['isInGame'] = true;
      
      // Update StateManager directly to ensure immediate availability
      clecoStateManager.updateModuleState('cleco_game', updatedClecoState);
      _logger.info('🎮 _startPracticeMatch: Critical state fields updated directly', isOn: LOGGING_SWITCH);
      
      // Now trigger slice recomputation via the queue (this will use the updated currentGameId)
      ClecoGameHelpers.updateUIState({
        'currentGameId': practiceRoomId,  // Trigger gameInfo slice recomputation
        'games': games,  // Trigger gameInfo slice recomputation
        'gamePhase': uiPhase,  // Trigger gameInfo slice recomputation
      });
      _logger.info('🎮 _startPracticeMatch: UI state updated and slices triggered', isOn: LOGGING_SWITCH);
      
      // Small delay to allow slice recomputation
      await Future.delayed(const Duration(milliseconds: 50));
      final verifyStateAfter = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final verifyGameInfo = verifyStateAfter['gameInfo'] as Map<String, dynamic>? ?? {};
      final verifyCurrentGameId = verifyGameInfo['currentGameId']?.toString() ?? '';
      final verifyIsRoomOwner = verifyGameInfo['isRoomOwner'] ?? false;
      final verifyIsInGame = verifyGameInfo['isInGame'] ?? false;
      _logger.info('🎮 _startPracticeMatch: Verified gameInfo - currentGameId: $verifyCurrentGameId, isRoomOwner: $verifyIsRoomOwner, isInGame: $verifyIsInGame', isOn: LOGGING_SWITCH);
      
      // 🎯 CRITICAL: Trigger game_state_updated event to sync widget slices
      // This ensures widget slices (myHand, centerBoard, opponentsPanel, etc.) are computed
      // Multiplayer does this automatically via WebSocket events, practice mode needs to do it manually
      // This will call _syncWidgetStatesFromGameState and trigger widget slice recomputation
      _logger.info('🎮 _startPracticeMatch: Triggering handleGameStateUpdated for game_id = $practiceRoomId', isOn: LOGGING_SWITCH);
      ClecoEventManager().handleGameStateUpdated({
        'game_id': practiceRoomId,
        'game_state': gameState,
        'owner_id': currentUserId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _logger.info('🎮 _startPracticeMatch: handleGameStateUpdated completed', isOn: LOGGING_SWITCH);
      
      // Navigate to game play screen
      _logger.info('🎮 _startPracticeMatch: Navigating to game play screen', isOn: LOGGING_SWITCH);
      NavigationManager().navigateTo('/cleco/game-play');
      
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
          
          // Join Random Game Widget
          JoinRandomGameWidget(
            onJoinRandomGame: () {
              // Callback after successful random game join
            },
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