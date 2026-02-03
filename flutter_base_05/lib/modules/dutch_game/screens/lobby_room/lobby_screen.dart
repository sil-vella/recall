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
  static const bool LOGGING_SWITCH = true; // Enabled for join/games investigation and joinedGamesSlice recomputation
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  final LobbyFeatureRegistrar _featureRegistrar = LobbyFeatureRegistrar();

  @override
  void initState() {
    super.initState();
    
    // Set Current Rooms section to be expanded on load
    _expandedSection = 'Current Rooms';
    
    // Defer until after first frame: (1) clear game state so lobby loads fresh, (2) recompute joinedGamesSlice, (3) WebSocket init and setup so ScaffoldMessenger/context is valid
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await DutchGameHelpers.clearAllGameStateBeforeNewGame();
      if (!mounted) return;
      _ensureJoinedGamesSliceComputed();
      _initializeWebSocket().then((_) {
        if (!mounted) return;
        _setupEventCallbacks();
        _initializeRoomState();
        _featureRegistrar.registerDefaults(context);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recompute joinedGamesSlice when screen becomes visible (e.g., navigating back to lobby)
    // This ensures the widget always reflects current state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureJoinedGamesSliceComputed();
      }
    });
  }
  
  /// Ensure joinedGamesSlice is computed from games map - ALWAYS recompute on lobby screen load/build/focus
  /// This ensures the widget always reflects the current games map state
  void _ensureJoinedGamesSliceComputed() {
    final Logger _logger = Logger();
    final stateManager = StateManager();
    final dutchGameState = stateManager.getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final joinedGamesSlice = dutchGameState['joinedGamesSlice'] as Map<String, dynamic>? ?? {};
    final currentJoinedGames = joinedGamesSlice['games'] as List<dynamic>? ?? [];
    
    if (LOGGING_SWITCH) {
      _logger.info('LobbyScreen: _ensureJoinedGamesSliceComputed - games map has ${games.length} games, joinedGamesSlice has ${currentJoinedGames.length} games');
      _logger.info('LobbyScreen: Forcing joinedGamesSlice recomputation from games map (${games.length} games)');
    }
    
    // ALWAYS trigger recomputation when lobby screen loads/builds/becomes visible
    // This ensures the widget reflects the current games map state, even if stale data exists
    // Trigger recomputation by updating games (even if unchanged, this will recompute the slice)
    DutchGameHelpers.updateUIState({
      'games': games, // This will trigger _updateWidgetSlices which will recompute joinedGamesSlice
    });
  }

  Future<void> _initializeWebSocket() async {
    final Logger _logger = Logger();
    if (LOGGING_SWITCH) {
      _logger.info('LobbyScreen: _initializeWebSocket called, mounted: $mounted');
    }
    
    // Check if user is logged in before attempting WebSocket connection
    final stateManager = StateManager();
    final loginState = stateManager.getModuleState<Map<String, dynamic>>('login') ?? {};
    final isLoggedIn = loginState['isLoggedIn'] == true;
    if (LOGGING_SWITCH) {
      _logger.info('LobbyScreen: User login status - isLoggedIn: $isLoggedIn');
    }
    
    // Allow unauthenticated users to stay on lobby screen (they can see the lobby but can't play)
    // Individual game actions will check authentication and redirect if needed
    if (!isLoggedIn) {
      if (LOGGING_SWITCH) {
        _logger.info('LobbyScreen: User is not logged in, skipping WebSocket initialization. User can stay on lobby screen.');
      }
      return;
    }
    
    try {
      // Initialize WebSocket manager if not already initialized
      if (!_websocketManager.isInitialized) {
        if (LOGGING_SWITCH) {
          _logger.info('LobbyScreen: WebSocket not initialized, initializing...');
        }
        final initialized = await _websocketManager.initialize();
        if (LOGGING_SWITCH) {
          _logger.info('LobbyScreen: WebSocket initialization result: $initialized');
        }
        if (!initialized) {
          if (LOGGING_SWITCH) {
            _logger.warning('LobbyScreen: WebSocket initialization failed, mounted: $mounted');
          }
          if (mounted) {
            _showSnackBar('Unable to initialize game connection', isError: true);
          }
          return;
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('LobbyScreen: WebSocket already initialized');
        }
      }
      
      // Connect to WebSocket if not already connected
      if (!_websocketManager.isConnected) {
        if (LOGGING_SWITCH) {
          _logger.info('LobbyScreen: WebSocket not connected, connecting...');
        }
        final connected = await _websocketManager.connect();
        if (LOGGING_SWITCH) {
          _logger.info('LobbyScreen: WebSocket connection result: $connected');
        }
        if (!connected) {
          if (LOGGING_SWITCH) {
            _logger.warning('LobbyScreen: WebSocket connection failed, mounted: $mounted');
          }
          if (mounted) {
            _showSnackBar('Unable to connect to game server', isError: true);
          }
          return;
        }
        if (mounted) {
        _showSnackBar('WebSocket connected successfully!');
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('LobbyScreen: WebSocket already connected');
        }
        if (mounted) {
        _showSnackBar('WebSocket already connected!');
      }
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error('LobbyScreen: WebSocket initialization error: $e', error: e, stackTrace: stackTrace);
      }
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
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Starting practice match setup');
      }
      
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
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Generated practice user: $currentUserId');
      }
      
      // Force showInstructions to false for practice matches (instructions are only used in demo matches)
      final updatedPracticeSettings = Map<String, dynamic>.from(practiceSettings);
      updatedPracticeSettings['showInstructions'] = false;
      
      // Store practice user data and settings SYNCHRONOUSLY so state has them before any async/queue.
      // CRITICAL: practiceUser must be in state immediately so (1) handleGameStateUpdated ignores
      // late WebSocket game_state_updated and (2) getCurrentUserId returns practice ID on game play screen.
      DutchGameHelpers.setPracticeStateSync(practiceUserData, updatedPracticeSettings);
      DutchGameHelpers.updateUIState({
        'practiceUser': practiceUserData,
        'practiceSettings': updatedPracticeSettings,
      });
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Stored practice user data and settings in state (sync + queue)');
        _logger.info('🎮 _startPracticeMatch: showInstructions = false (always disabled for practice matches)');
      }
      
      // Verify practice user data was stored (read back from state)
      final verifyState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final verifyPracticeUser = verifyState['practiceUser'] as Map<String, dynamic>?;
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Verified practice user in state: $verifyPracticeUser');
      }
      
      // Switch event emitter to practice mode
      final eventEmitter = DutchGameEventEmitter.instance;
      eventEmitter.setTransportMode(EventTransportMode.practice);
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Switched to practice mode');
      }
      
      // Initialize and start practice session
      final practiceBridge = PracticeModeBridge.instance;
      await practiceBridge.initialize();
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Practice bridge initialized');
      }
      
      // Get difficulty from practice settings
      final practiceDifficulty = updatedPracticeSettings['difficulty'] as String? ?? 'medium';
      
      final practiceRoomId = await practiceBridge.startPracticeSession(
        userId: currentUserId,
        maxPlayers: 4,
        minPlayers: 2,
        gameType: 'practice',
        difficulty: practiceDifficulty, // Pass difficulty from lobby selection
      );
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Practice room created: $practiceRoomId');
      }
      
      // Get game state from GameStateStore (after hooks have initialized it)
      final gameStateStore = GameStateStore.instance;
      final gameState = gameStateStore.getGameState(practiceRoomId);
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Got game state, phase = ${gameState['phase']}');
      }
      
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
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Updating UI state with currentGameId = $practiceRoomId');
      }
      
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
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Critical state fields updated directly');
      }
      
      // Now trigger slice recomputation via the queue (this will use the updated currentGameId)
      DutchGameHelpers.updateUIState({
        'currentGameId': practiceRoomId,  // Trigger gameInfo slice recomputation
        'games': games,  // Trigger gameInfo slice recomputation
        'gamePhase': uiPhase,  // Trigger gameInfo slice recomputation
      });
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: UI state updated and slices triggered');
      }
      
      // Small delay to allow slice recomputation
      await Future.delayed(const Duration(milliseconds: 50));
      final verifyStateAfter = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final verifyGameInfo = verifyStateAfter['gameInfo'] as Map<String, dynamic>? ?? {};
      final verifyCurrentGameId = verifyGameInfo['currentGameId']?.toString() ?? '';
      final verifyIsRoomOwner = verifyGameInfo['isRoomOwner'] ?? false;
      final verifyIsInGame = verifyGameInfo['isInGame'] ?? false;
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: Verified gameInfo - currentGameId: $verifyCurrentGameId, isRoomOwner: $verifyIsRoomOwner, isInGame: $verifyIsInGame');
        _logger.info('🎮 _startPracticeMatch: Triggering handleGameStateUpdated for game_id = $practiceRoomId');
      }
      
      // 🎯 CRITICAL: Trigger game_state_updated event to sync widget slices
      // This ensures widget slices (myHand, centerBoard, opponentsPanel, etc.) are computed
      // Multiplayer does this automatically via WebSocket events, practice mode needs to do it manually
      // This will call _syncWidgetStatesFromGameState and trigger widget slice recomputation
      DutchEventManager().handleGameStateUpdated({
        'game_id': practiceRoomId,
        'game_state': gameState,
        'owner_id': currentUserId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      if (LOGGING_SWITCH) {
        _logger.info('🎮 _startPracticeMatch: handleGameStateUpdated completed');
        _logger.info('🎮 _startPracticeMatch: Navigating to game play screen');
      }
      
      // Navigate to game play screen
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
    // CRITICAL: Recompute joinedGamesSlice on every build to ensure widget reflects current state
    // This handles cases where state contains stale games that need to be cleared
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureJoinedGamesSliceComputed();
      }
    });
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: SingleChildScrollView(
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
        ),
      ),
    );
  }
} 