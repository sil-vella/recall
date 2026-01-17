import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../core/managers/navigation_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../managers/game_coordinator.dart';
import '../../managers/validated_event_emitter.dart';
import '../../../dutch_game/managers/dutch_event_manager.dart';
import '../../practice/practice_mode_bridge.dart';
import '../../backend_core/services/game_state_store.dart';
import '../../../dutch_game/utils/dutch_game_helpers.dart';
import 'widgets/create_join_game_widget.dart';
import 'widgets/join_random_game_widget.dart';
import 'widgets/current_games_widget.dart';
import 'widgets/practice_match_widget.dart';
import 'widgets/collapsible_section_widget.dart';
import 'features/lobby_features.dart';


class LobbyScreen extends BaseScreen {
  const LobbyScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Game Lobby';

  @override
  _LobbyScreenState createState() => _LobbyScreenState();
}

class _LobbyScreenState extends BaseScreenState<LobbyScreen> {
  static const bool LOGGING_SWITCH = false; // Enabled for debugging navigation issues
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
    final Logger _logger = Logger();
    _logger.info('LobbyScreen: _initializeWebSocket called, mounted: $mounted', isOn: LOGGING_SWITCH);
    
    // Check if user is logged in before attempting WebSocket connection
    final stateManager = StateManager();
    final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
    final isLoggedIn = loginState['isLoggedIn'] == true;
    _logger.info('LobbyScreen: User login status - isLoggedIn: $isLoggedIn', isOn: LOGGING_SWITCH);
    
    // Allow unauthenticated users to stay on lobby screen (they can see the lobby but can't play)
    // Individual game actions will check authentication and redirect if needed
    if (!isLoggedIn) {
      _logger.info('LobbyScreen: User is not logged in, skipping WebSocket initialization. User can stay on lobby screen.', isOn: LOGGING_SWITCH);
      return;
    }
    
    try {
      // Initialize WebSocket manager if not already initialized
      if (!_websocketManager.isInitialized) {
        _logger.info('LobbyScreen: WebSocket not initialized, initializing...', isOn: LOGGING_SWITCH);
        final initialized = await _websocketManager.initialize();
        _logger.info('LobbyScreen: WebSocket initialization result: $initialized', isOn: LOGGING_SWITCH);
        if (!initialized) {
          _logger.warning('LobbyScreen: WebSocket initialization failed, mounted: $mounted', isOn: LOGGING_SWITCH);
          if (mounted) {
            _showSnackBar('Unable to initialize game connection', isError: true);
          }
          return;
        }
      } else {
        _logger.info('LobbyScreen: WebSocket already initialized', isOn: LOGGING_SWITCH);
      }
      
      // Connect to WebSocket if not already connected
      if (!_websocketManager.isConnected) {
        _logger.info('LobbyScreen: WebSocket not connected, connecting...', isOn: LOGGING_SWITCH);
        final connected = await _websocketManager.connect();
        _logger.info('LobbyScreen: WebSocket connection result: $connected', isOn: LOGGING_SWITCH);
        if (!connected) {
          _logger.warning('LobbyScreen: WebSocket connection failed, mounted: $mounted', isOn: LOGGING_SWITCH);
          if (mounted) {
            _showSnackBar('Unable to connect to game server', isError: true);
          }
          return;
        }
        if (mounted) {
        _showSnackBar('WebSocket connected successfully!');
        }
      } else {
        _logger.info('LobbyScreen: WebSocket already connected', isOn: LOGGING_SWITCH);
        if (mounted) {
        _showSnackBar('WebSocket already connected!');
      }
      }
    } catch (e, stackTrace) {
      _logger.error('LobbyScreen: WebSocket initialization error: $e', error: e, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
      if (mounted) {
        _showSnackBar('WebSocket connection error: $e', isError: true);
      }
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
      // 🎯 CRITICAL: Clear all existing game state before starting new game
      // This prevents overlapping or old game state from interfering
      await DutchGameHelpers.clearAllGameStateBeforeNewGame();
      
      // Check if user has enough coins (default 25, can be overridden in roomSettings)
      // Fetch fresh stats from API before checking
      final requiredCoins = roomSettings['requiredCoins'] as int? ?? 25;
      final hasEnoughCoins = await DutchGameHelpers.checkCoinsRequirement(requiredCoins: requiredCoins, fetchFromAPI: true);
      if (!hasEnoughCoins) {
        if (mounted) _showSnackBar('Insufficient coins to create a game. Required: $requiredCoins', isError: true);
        return;
      }
      
      // Clear practice user data when switching to multiplayer
      DutchGameHelpers.updateUIState({
        'practiceUser': null,
      });
      
      // Ensure we're in WebSocket mode for multiplayer
      final eventEmitter = DutchGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.websocket);
      
      // Ensure WebSocket is ready (logged in, initialized, and connected)
      final isReady = await DutchGameHelpers.ensureWebSocketReady();
      if (!isReady) {
        if (mounted) {
          _showSnackBar('Unable to connect to game server. Please log in to continue.', isError: true);
          DutchGameHelpers.navigateToAccountScreen('ws_not_ready', 'Unable to connect to game server. Please log in to continue.');
        }
        return;
      }
      
      // Now proceed with room creation - bypass RoomService and call helper directly
      final result = await DutchGameHelpers.createRoom(
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
      // 🎯 CRITICAL: Clear all existing game state before starting new game
      // This prevents overlapping or old game state from interfering
      await DutchGameHelpers.clearAllGameStateBeforeNewGame();
      
      // Check if user has enough coins (default 25)
      // Fetch fresh stats from API before checking
      final hasEnoughCoins = await DutchGameHelpers.checkCoinsRequirement(fetchFromAPI: true);
      if (!hasEnoughCoins) {
        if (mounted) _showSnackBar('Insufficient coins to join a game. Required: 25', isError: true);
        return;
      }
      
      // Clear practice user data when switching to multiplayer
      DutchGameHelpers.updateUIState({
        'practiceUser': null,
      });
      
      // Ensure we're in WebSocket mode for multiplayer
      final eventEmitter = DutchGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.websocket);
      
      // Ensure WebSocket is ready (logged in, initialized, and connected)
      final isReady = await DutchGameHelpers.ensureWebSocketReady();
      if (!isReady) {
        if (mounted) {
          _showSnackBar('Unable to connect to game server', isError: true);
        }
        return;
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


  Future<void> _startPracticeMatch(Map<String, dynamic> practiceSettings) async {
    try {
      final Logger _logger = Logger();
      _logger.info('🎮 _startPracticeMatch: Starting practice match setup', isOn: LOGGING_SWITCH);
      
      // 🎯 CRITICAL: Clear all existing game state before starting new game
      // This prevents overlapping or old game state from interfering
      await DutchGameHelpers.clearAllGameStateBeforeNewGame();
      
      // Generate practice mode user data (self-contained, doesn't rely on login module)
      final currentUserId = 'practice_user_${DateTime.now().millisecondsSinceEpoch}';
      final practiceUserData = {
        'userId': currentUserId,
        'displayName': 'Practice Player',
        'isPracticeUser': true,
      };
      _logger.info('🎮 _startPracticeMatch: Generated practice user: $currentUserId', isOn: LOGGING_SWITCH);
      
      // Force showInstructions to false for practice matches (instructions are only used in demo matches)
      final updatedPracticeSettings = Map<String, dynamic>.from(practiceSettings);
      updatedPracticeSettings['showInstructions'] = false;
      
      // Store practice user data and settings in dutch_game state (accessible to event handlers)
      // Use validated state updater to ensure proper validation
      DutchGameHelpers.updateUIState({
        'practiceUser': practiceUserData,
        'practiceSettings': updatedPracticeSettings,
      });
      _logger.info('🎮 _startPracticeMatch: Stored practice user data and settings in state', isOn: LOGGING_SWITCH);
      _logger.info('🎮 _startPracticeMatch: showInstructions = false (always disabled for practice matches)', isOn: LOGGING_SWITCH);
      
      // Verify practice user data was stored (read back from state)
      final verifyState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final verifyPracticeUser = verifyState['practiceUser'] as Map<String, dynamic>?;
      _logger.info('🎮 _startPracticeMatch: Verified practice user in state: $verifyPracticeUser', isOn: LOGGING_SWITCH);
      
      // Switch event emitter to practice mode
      final eventEmitter = DutchGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.practice);
      _logger.info('🎮 _startPracticeMatch: Switched to practice mode', isOn: LOGGING_SWITCH);
      
      // Initialize and start practice session
      final practiceBridge = PracticeModeBridge.instance;
      await practiceBridge.initialize();
      _logger.info('🎮 _startPracticeMatch: Practice bridge initialized', isOn: LOGGING_SWITCH);
      
      // Get difficulty from practice settings
      final practiceDifficulty = updatedPracticeSettings['difficulty'] as String? ?? 'medium';
      
      final practiceRoomId = await practiceBridge.startPracticeSession(
        userId: currentUserId,
        maxPlayers: 4,
        minPlayers: 2,
        gameType: 'practice',
        difficulty: practiceDifficulty, // Pass difficulty from lobby selection
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
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
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
      final dutchStateManager = StateManager();
      final currentDutchState = dutchStateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final updatedDutchState = Map<String, dynamic>.from(currentDutchState);
      
      // Update critical fields directly
      updatedDutchState['currentGameId'] = practiceRoomId;
      updatedDutchState['currentRoomId'] = practiceRoomId;
      updatedDutchState['isInRoom'] = true;
      updatedDutchState['isRoomOwner'] = true;
      updatedDutchState['gameType'] = 'practice';
      updatedDutchState['games'] = games;
      updatedDutchState['gamePhase'] = uiPhase;
      updatedDutchState['currentSize'] = 1;
      updatedDutchState['maxSize'] = maxPlayersValue;
      updatedDutchState['isInGame'] = true;
      
      // Update StateManager directly to ensure immediate availability
      dutchStateManager.updateModuleState('dutch_game', updatedDutchState);
      _logger.info('🎮 _startPracticeMatch: Critical state fields updated directly', isOn: LOGGING_SWITCH);
      
      // Now trigger slice recomputation via the queue (this will use the updated currentGameId)
      DutchGameHelpers.updateUIState({
        'currentGameId': practiceRoomId,  // Trigger gameInfo slice recomputation
        'games': games,  // Trigger gameInfo slice recomputation
        'gamePhase': uiPhase,  // Trigger gameInfo slice recomputation
      });
      _logger.info('🎮 _startPracticeMatch: UI state updated and slices triggered', isOn: LOGGING_SWITCH);
      
      // Small delay to allow slice recomputation
      await Future.delayed(const Duration(milliseconds: 50));
      final verifyStateAfter = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
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
      DutchEventManager().handleGameStateUpdated({
        'game_id': practiceRoomId,
        'game_state': gameState,
        'owner_id': currentUserId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _logger.info('🎮 _startPracticeMatch: handleGameStateUpdated completed', isOn: LOGGING_SWITCH);
      
      // Navigate to game play screen
      _logger.info('🎮 _startPracticeMatch: Navigating to game play screen', isOn: LOGGING_SWITCH);
      NavigationManager().navigateTo('/dutch/game-play');
      
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
        backgroundColor: isError ? AppColors.errorColor : AppColors.successColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String? _expandedSection; // Track which section is currently expanded

  void _handleSectionToggled(String sectionTitle) {
    setState(() {
      // If clicking the same section, close it. Otherwise, open the new one and close others
      if (_expandedSection == sectionTitle) {
        _expandedSection = null;
      } else {
        _expandedSection = sectionTitle;
      }
    });
  }

  @override
  Widget buildContent(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current Rooms Section (Collapsible) - First
          CollapsibleSectionWidget(
            title: 'Current Rooms',
            icon: Icons.meeting_room,
            isExpanded: _expandedSection == 'Current Rooms',
            onExpandedChanged: () => _handleSectionToggled('Current Rooms'),
            child: CurrentRoomWidget(
              onJoinRoom: _joinRoom,
            ),
          ),
          
          // Join Random Game Section (Collapsible) - Second
          CollapsibleSectionWidget(
            title: 'Join Random Game',
            icon: Icons.flash_on,
            isExpanded: _expandedSection == 'Join Random Game',
            onExpandedChanged: () => _handleSectionToggled('Join Random Game'),
            child: JoinRandomGameWidget(
              onJoinRandomGame: () {
                // Callback after successful random game join
              },
            ),
          ),
          
          // Practice Match Section (Collapsible) - Third
          CollapsibleSectionWidget(
            title: 'Practice Match',
            icon: Icons.school,
            isExpanded: _expandedSection == 'Practice Match',
            onExpandedChanged: () => _handleSectionToggled('Practice Match'),
            child: PracticeMatchWidget(
              onStartPractice: _startPracticeMatch,
            ),
          ),
          
          // Create & Join Room Section (Collapsible) - Last
          CollapsibleSectionWidget(
            title: 'Create & Join Room',
            icon: Icons.group_add,
            isExpanded: _expandedSection == 'Create & Join Room',
            onExpandedChanged: () => _handleSectionToggled('Create & Join Room'),
            child: CreateJoinGameWidget(
              onCreateRoom: _createRoom,
              onJoinRoom: () {
                // Callback after successful join request
              },
            ),
          ),
        ],
      ),
    );
  }
} 