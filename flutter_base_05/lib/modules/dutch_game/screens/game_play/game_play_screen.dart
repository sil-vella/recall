import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import 'widgets/game_info_widget.dart';
import 'widgets/unified_game_board_widget.dart';
import 'widgets/instructions_widget.dart';
import 'widgets/messages_widget.dart';
import 'widgets/card_animation_layer.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../managers/feature_registry_manager.dart';
import '../../../../core/widgets/state_aware_features/game_phase_chip_feature.dart';
import '../../utils/game_instructions_provider.dart' as instructions;
import '../../managers/game_coordinator.dart';

const bool LOGGING_SWITCH = false; // Enabled for testing and debugging

class GamePlayScreen extends BaseScreen {
  const GamePlayScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Dutch Game';

  @override
  GamePlayScreenState createState() => GamePlayScreenState();
}

class GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  final Logger _logger = Logger();
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  String? _previousGameId;
  
  // GlobalKey for the main Stack to get exact position for animations
  final GlobalKey _mainStackKey = GlobalKey(); // Track game ID to detect navigation away

  @override
  void initState() {
    super.initState();
    
    // Register game phase chip feature in app bar
    _registerGamePhaseChipFeature();
    
    _initializeWebSocket().then((_) {
      _setupEventCallbacks();
      _initializeGameState();
    });
  }
  
  /// Register game phase chip feature in app bar
  void _registerGamePhaseChipFeature() {
    final gamePhaseFeature = FeatureDescriptor(
      featureId: 'game_phase_chip',
      slotId: 'app_bar_actions',
      builder: (context) => const StateAwareGamePhaseChipFeature(),
      priority: 5, // Lowest priority - appears first (leftmost, before connection)
    );
    
    FeatureRegistryManager.instance.register(
      scopeKey: featureScopeKey, // Screen-specific scope
      feature: gamePhaseFeature,
      context: context,
    );
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Get current game ID when screen loads
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentGameId = dutchGameState['currentGameId']?.toString();
    _previousGameId = currentGameId;
    
    _logger.info('GamePlay: Screen loaded with game ID: $_previousGameId', isOn: LOGGING_SWITCH);
    
    // Check if returning to same game and cancel pending leave timer
    if (currentGameId != null && 
        currentGameId == GameCoordinator().pendingLeaveGameId) {
      _logger.info('GamePlay: Returning to same game $currentGameId - cancelling leave timer', isOn: LOGGING_SWITCH);
      GameCoordinator().cancelLeaveGameTimer(currentGameId);
    }
    
    // Check for initial instructions after dependencies are set (game state should be ready)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowInitialInstructions();
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
  void deactivate() {
    // Check if we're navigating away from a game
    if (_previousGameId != null && _previousGameId!.isNotEmpty) {
      _logger.info('GamePlay: Navigating away from game $_previousGameId - starting 30-second leave timer', isOn: LOGGING_SWITCH);
      
      // Start 30-second timer before leaving (gives user chance to return)
      // Timer is managed by GameCoordinator (singleton) so it survives widget disposal
      GameCoordinator().startLeaveGameTimer(_previousGameId!);
    }
    
    super.deactivate();
  }
  
  @override
  void dispose() {
    // Don't cancel timer here - it's managed by GameCoordinator and needs to survive disposal
    // The timer will be cancelled if user returns to the same game (in initState)
    _logger.info('GamePlay: Disposing - leave timer continues in GameCoordinator', isOn: LOGGING_SWITCH);
    
    // Unregister game phase chip feature
    FeatureRegistryManager.instance.unregister(
      scopeKey: featureScopeKey,
      featureId: 'game_phase_chip',
    );
    
    // Clean up any game-specific resources
    super.dispose();
  }

  void _initializeGameState() {
    // Initialize game-specific state
    // This will be expanded as we add more game functionality
    
    // Check if we should show initial instructions
    _checkAndShowInitialInstructions();
  }
  
  /// Check if initial instructions should be shown when screen loads
  void _checkAndShowInitialInstructions() {
    try {
      final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameId = dutchGameState['currentGameId']?.toString();
      
      if (currentGameId == null || currentGameId.isEmpty) {
        return;
      }
      
      // Get game from games map
      final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
      final game = games[currentGameId] as Map<String, dynamic>?;
      if (game == null) {
        return;
      }
      
      final gameData = game['gameData'] as Map<String, dynamic>?;
      final gameState = gameData?['game_state'] as Map<String, dynamic>?;
      
      if (gameState == null) {
        return;
      }
      
      // Check if showInstructions is enabled (check both game state and practice settings)
      bool showInstructions = gameState['showInstructions'] as bool? ?? false;
      if (!showInstructions) {
        // Fallback to practice settings if not in game state
        final practiceSettings = dutchGameState['practiceSettings'] as Map<String, dynamic>?;
        showInstructions = practiceSettings?['showInstructions'] as bool? ?? false;
        _logger.info('📚 _checkAndShowInitialInstructions: showInstructions not in gameState, checking practiceSettings=$showInstructions', isOn: LOGGING_SWITCH);
      }
      if (!showInstructions) {
        _logger.info('📚 _checkAndShowInitialInstructions: Instructions disabled, skipping', isOn: LOGGING_SWITCH);
        return;
      }
      
      // Check if we're in waiting phase
      final rawPhase = gameState['phase']?.toString();
      final gamePhase = rawPhase == 'waiting_for_players'
          ? 'waiting'
          : (rawPhase ?? 'playing');
      
      if (gamePhase == 'waiting') {
        _logger.info('📚 _checkAndShowInitialInstructions: In waiting phase, showInstructions=$showInstructions', isOn: LOGGING_SWITCH);
        // Check if initial instructions haven't been dismissed
        final instructionsData = dutchGameState['instructions'] as Map<String, dynamic>? ?? {};
        final dontShowAgain = Map<String, bool>.from(
          instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
        );
        
        _logger.info('📚 _checkAndShowInitialInstructions: dontShowAgain[initial]=${dontShowAgain['initial']}', isOn: LOGGING_SWITCH);
        
        if (dontShowAgain['initial'] != true) {
          // Check if initial instructions are already showing
          final instructionsData = dutchGameState['instructions'] as Map<String, dynamic>? ?? {};
          final currentlyVisible = instructionsData['isVisible'] == true;
          final currentKey = instructionsData['key']?.toString();
          
          // Only show if not already showing
          if (!currentlyVisible || currentKey != 'initial') {
            // Get initial instructions
            final initialInstructions = instructions.GameInstructionsProvider.getInitialInstructions();
            StateManager().updateModuleState('dutch_game', {
              'instructions': {
                'isVisible': true,
                'title': initialInstructions['title'] ?? 'Welcome to Dutch!',
                'content': initialInstructions['content'] ?? '',
                'key': initialInstructions['key'] ?? 'initial',
                'hasDemonstration': initialInstructions['hasDemonstration'] ?? false,
                'dontShowAgain': dontShowAgain,
              },
            });
            _logger.info('📚 _checkAndShowInitialInstructions: Initial instructions triggered from screen init', isOn: LOGGING_SWITCH);
          } else {
            _logger.info('📚 _checkAndShowInitialInstructions: Initial instructions skipped - already showing', isOn: LOGGING_SWITCH);
          }
        } else {
          _logger.info('📚 _checkAndShowInitialInstructions: Initial instructions skipped - already marked as dontShowAgain', isOn: LOGGING_SWITCH);
        }
      }
    } catch (e) {
      _logger.error('Error checking initial instructions: $e', isOn: LOGGING_SWITCH);
    }
  }

  void _setupEventCallbacks() {
    // Event callbacks are handled by WSEventManager
    // No need to set up specific callbacks here
    // The WSEventManager handles all WebSocket events automatically
  }


  void _showSnackBar(String message, {bool isError = false}) {
    // Check if the widget is still mounted before accessing context
    if (!mounted) return;
    
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.errorColor : AppColors.successColor,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // ScaffoldMessenger might not be available if widget is being disposed
      // Just log the error instead of crashing
      _logger.warning('GamePlay: Could not show snackbar - $e', isOn: LOGGING_SWITCH);
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    _logger.info('GamePlayScreen: buildContent called', isOn: LOGGING_SWITCH);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        _logger.info(
          'GamePlayScreen: LayoutBuilder - maxHeight=${constraints.maxHeight}, '
          'maxWidth=${constraints.maxWidth}',
          isOn: LOGGING_SWITCH,
        );
        
        return Stack(
          key: _mainStackKey,
          clipBehavior: Clip.none,
          children: [
            // Main game content - takes full size of content area
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Game Information Widget - takes natural height
                const GameInfoWidget(),
                
                SizedBox(height: AppPadding.smallPadding.top),
                
                // Unified Game Board Widget - takes all remaining available space
                // It will be scrollable internally with my hand aligned to bottom
                Expanded(
                  child: const UnifiedGameBoardWidget(),
                ),
              ],
            ),
        
        // Card Animation Layer - full-screen overlay for animated cards
        CardAnimationLayer(stackKey: _mainStackKey),
        
        // Instructions Modal Widget - handles its own state subscription
        const InstructionsWidget(),
        
            // Messages Modal Widget - handles its own state subscription
            const MessagesWidget(),
          ],
        );
      },
    );
  }
}


