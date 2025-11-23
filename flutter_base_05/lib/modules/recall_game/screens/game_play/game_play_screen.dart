import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../game_logic/practice_match/practice_game.dart';
import 'widgets/game_info_widget.dart';
import 'widgets/opponents_panel_widget.dart';
import 'widgets/game_board_widget.dart';
import 'widgets/my_hand_widget.dart';
import 'widgets/instructions_widget.dart';
import 'widgets/messages_widget.dart';
import 'widgets/card_animation_layer.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../../../modules/recall_game/managers/feature_registry_manager.dart';
import '../../../../core/widgets/state_aware_features/game_phase_chip_feature.dart';
import 'card_position_tracker.dart';

const bool LOGGING_SWITCH = false;

class GamePlayScreen extends BaseScreen {
  const GamePlayScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Recall Game';

  @override
  GamePlayScreenState createState() => GamePlayScreenState();
}

class GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  final Logger _logger = Logger();
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  String? _previousGameId; // Track game ID to detect navigation away

  @override
  void initState() {
    super.initState();
    
    // Initialize card position tracker (singleton, initialized on first access)
    CardPositionTracker.instance();
    
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
    final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
    _previousGameId = recallGameState['currentGameId']?.toString();
    
    _logger.info('GamePlay: Screen loaded with game ID: $_previousGameId', isOn: LOGGING_SWITCH);
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
    // Check if we're navigating away from a recall game
    if (_previousGameId != null && _previousGameId!.startsWith('recall_game_')) {
      _logger.info('GamePlay: Navigating away from recall game $_previousGameId - cleaning up', isOn: LOGGING_SWITCH);
      
      // Clean up recall game state
      PracticeGameCoordinator().cleanupPracticeState();
    }
    
    super.deactivate();
  }
  
  @override
  void dispose() {
    // Unregister game phase chip feature
    FeatureRegistryManager.instance.unregister(
      scopeKey: featureScopeKey,
      featureId: 'game_phase_chip',
    );
    
    // Clear card position tracker
    CardPositionTracker.instance().clearAllPositions();
    
    // Additional cleanup on dispose (failsafe)
    if (_previousGameId != null && _previousGameId!.startsWith('recall_game_')) {
      _logger.info('GamePlay: Disposing recall game $_previousGameId - final cleanup', isOn: LOGGING_SWITCH);
      
      PracticeGameCoordinator().cleanupPracticeState();
    }
    
    // Clean up any game-specific resources
    super.dispose();
  }

  void _initializeGameState() {
    // Initialize game-specific state
    // This will be expanded as we add more game functionality
  }

  void _setupEventCallbacks() {
    // Event callbacks are handled by WSEventManager
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
    return Stack(
      children: [
        // Main game content
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              // Game Information Widget
              const GameInfoWidget(),
              
              // Opponents Panel Section
              const OpponentsPanelWidget(),
              
              // Game Board Section
              const GameBoardWidget(),
              
              // My Hand Section
              const MyHandWidget(),
            ],
          ),
        ),
        
        
        // Instructions Modal Widget - handles its own state subscription
        const InstructionsWidget(),
        
        // Messages Modal Widget - handles its own state subscription
        const MessagesWidget(),
        
        // Card Animation Layer - overlay for card animations (topmost layer)
        CardAnimationLayer(),
      ],
    );
  }
}


