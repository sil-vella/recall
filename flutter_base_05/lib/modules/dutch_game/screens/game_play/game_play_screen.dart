import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import 'widgets/game_info_widget.dart';
import 'widgets/unified_game_board_widget.dart';
import '../../widgets/instructions_widget.dart';
import 'widgets/messages_widget.dart';
import 'widgets/action_text_widget.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../managers/feature_registry_manager.dart';
import '../../utils/game_instructions_provider.dart' as instructions;
import '../../managers/game_coordinator.dart';
import '../demo/demo_action_handler.dart';

const bool LOGGING_SWITCH = false; // Enabled for testing and debugging

/// Custom painter for felt texture - creates grainy noise effect
/// Uses seeded random for consistent, stable texture pattern
class FeltTexturePainter extends CustomPainter {
  // Use a fixed seed so the texture pattern is always the same
  static const int _seed = 42;
  
  // Cache the generated pattern points to avoid regenerating on every paint
  List<_GrainPoint>? _cachedPoints;
  Size? _cachedSize;
  
  @override
  void paint(Canvas canvas, Size size) {
    // Regenerate pattern only if size changed
    if (_cachedPoints == null || _cachedSize != size) {
      _cachedSize = size;
      _cachedPoints = [];
      
      // Reset random with same seed for consistent pattern
      final random = math.Random(_seed);
      final pointCount = (size.width * size.height * 0.15).round();
      
      for (int i = 0; i < pointCount; i++) {
        _cachedPoints!.add(_GrainPoint(
          x: random.nextDouble() * size.width,
          y: random.nextDouble() * size.height,
          opacity: random.nextDouble() * 0.3 + 0.1, // 0.1 to 0.4 opacity
        ));
      }
    }
    
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 0.5;
    
    // Draw cached pattern
    for (final point in _cachedPoints!) {
      paint.color = Colors.black.withValues(alpha: point.opacity);
      canvas.drawCircle(Offset(point.x, point.y), 0.5, paint);
    }
  }
  
  @override
  bool shouldRepaint(FeltTexturePainter oldDelegate) {
    // Only repaint if size changed
    return oldDelegate._cachedSize != _cachedSize;
  }
}

/// Helper class to store grain point data
class _GrainPoint {
  final double x;
  final double y;
  final double opacity;
  
  _GrainPoint({
    required this.x,
    required this.y,
    required this.opacity,
  });
}

/// Custom painter for gradient border - fades from light brown to darker brown
/// The gradient starts from the outer edge (light brown) and fades to darker brown at the inner edge
/// From halfway in to the inner edge, it transitions to darker brown
class GradientBorderPainter extends CustomPainter {
  final Color startColor; // Light brown (outer edge)
  final Color endColor; // Darker brown (inner edge)
  final double borderWidth;
  final double borderRadius;
  
  GradientBorderPainter({
    required this.startColor,
    required this.endColor,
    required this.borderWidth,
    required this.borderRadius,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // Draw the border with a gradient that fades from outer edge (light brown) to inner edge (dark brown)
    // The gradient starts at halfway point and intensifies to the inner edge
    // We'll draw multiple concentric strokes with gradually changing colors to create the gradient effect
    
    final gradientSteps = 12; // Number of steps for smooth gradient
    final stepWidth = borderWidth / gradientSteps;
    
    // Draw the entire border width with gradient
    // Outer half (first 50%): solid light brown
    // Inner half (last 50%): gradient from light brown to dark brown
    for (int i = 0; i < gradientSteps; i++) {
      final position = i / gradientSteps; // 0.0 (outer edge) to 1.0 (inner edge)
      
      Color color;
      if (position <= 0.5) {
        // Outer half: solid light brown
        color = startColor;
      } else {
        // Inner half: gradient from light brown to dark brown
        // Map position from 0.5-1.0 to 0.0-1.0 for interpolation
        final t = (position - 0.5) * 2.0; // 0.0 to 1.0
        color = Color.lerp(startColor, endColor, t)!;
      }
      
      final offset = i * stepWidth;
      final rect = Rect.fromLTWH(
        offset,
        offset,
        size.width - (offset * 2),
        size.height - (offset * 2),
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(borderRadius - offset),
      );
      
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stepWidth + 0.5 // Slight overlap to avoid gaps
        ..color = color;
      
      final path = Path()..addRRect(rrect);
      canvas.drawPath(path, paint);
    }
  }
  
  @override
  bool shouldRepaint(GradientBorderPainter oldDelegate) {
    return oldDelegate.startColor != startColor ||
        oldDelegate.endColor != endColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}

/// Background widget that only builds once - contains table color and texture
/// Uses RepaintBoundary to prevent unnecessary repaints
class TableBackgroundWidget extends StatefulWidget {
  const TableBackgroundWidget({Key? key}) : super(key: key);

  @override
  State<TableBackgroundWidget> createState() => _TableBackgroundWidgetState();
}

class _TableBackgroundWidgetState extends State<TableBackgroundWidget> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          
          // Calculate spotlight positions - evenly spaced vertically
          // 2 spotlights from left, 2 from right
          final spotlightSize = 400.0; // Size of circular spotlight
          final topSpotlightY = height * 0.25; // Top spotlight position
          final bottomSpotlightY = height * 0.75; // Bottom spotlight position
          
          return Stack(
            children: [
              // Background color and texture
              Container(
                color: AppColors.pokerTableGreen,
                child: CustomPaint(
                  painter: FeltTexturePainter(),
                  size: Size(width, height),
                ),
              ),
              // Left side spotlights (2 evenly spaced) - bright at edge, quick fade
              Positioned(
                left: -0,
                top: topSpotlightY - spotlightSize / 2,
                child: Container(
                  width: spotlightSize,
                  height: spotlightSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment.centerLeft,
                      radius: 1.0,
                      colors: [
                        AppColors.warmSpotlightColor.withValues(alpha: 0.85), // Warm bright at edge
                        AppColors.warmSpotlightColor.withValues(alpha: 0.15), // Warm fade
                        AppColors.warmSpotlightColor.withValues(alpha: 0.0), // Warm transparent
                      ],
                      stops: const [0.0, 0.05, 0.3], // Fades to zero at 40% - well before edge
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -0,
                top: bottomSpotlightY - spotlightSize / 2,
                child: Container(
                  width: spotlightSize,
                  height: spotlightSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment.centerLeft,
                      radius: 1.0,
                      colors: [
                        AppColors.warmSpotlightColor.withValues(alpha: 0.85), // Warm bright at edge
                        AppColors.warmSpotlightColor.withValues(alpha: 0.15), // Warm fade
                        AppColors.warmSpotlightColor.withValues(alpha: 0.0), // Warm transparent
                      ],
                      stops: const [0.0, 0.05, 0.3], // Fades to zero at 40% - well before edge
                    ),
                  ),
                ),
              ),
              // Right side spotlights (2 evenly spaced) - bright at edge, quick fade
              Positioned(
                right: -0,
                top: topSpotlightY - spotlightSize / 2,
                child: Container(
                  width: spotlightSize,
                  height: spotlightSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment.centerRight,
                      radius: 1.0,
                      colors: [
                        AppColors.warmSpotlightColor.withValues(alpha: 0.85), // Warm bright at edge
                        AppColors.warmSpotlightColor.withValues(alpha: 0.15), // Warm fade
                        AppColors.warmSpotlightColor.withValues(alpha: 0.0), // Warm transparent
                      ],
                      stops: const [0.0, 0.05, 0.3], // Fades to zero at 40% - well before edge
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -0,
                top: bottomSpotlightY - spotlightSize / 2,
                child: Container(
                  width: spotlightSize,
                  height: spotlightSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment.centerRight,
                      radius: 1.0,
                      colors: [
                        AppColors.warmSpotlightColor.withValues(alpha: 0.85), // Warm bright at edge
                        AppColors.warmSpotlightColor.withValues(alpha: 0.15), // Warm fade
                        AppColors.warmSpotlightColor.withValues(alpha: 0.0), // Warm transparent
                      ],
                      stops: const [0.0, 0.05, 0.3], // Fades to zero at 40% - well before edge
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class GamePlayScreen extends BaseScreen {
  const GamePlayScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) => 'Dutch Game';

  @override
  Decoration? getBackground(BuildContext context) {
    return BoxDecoration(
      color: AppColors.pokerTableGreen,
    );
  }

  @override
  GamePlayScreenState createState() => GamePlayScreenState();
}

class GamePlayScreenState extends BaseScreenState<GamePlayScreen> {
  final Logger _logger = Logger();
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  String? _previousGameId;
  
  // GlobalKey for the main Stack to get exact position for animations
  final GlobalKey _mainStackKey = GlobalKey(); // Track game ID to detect navigation away
  
  // Cached background widget - only builds once on screen load
  late final Widget _tableBackground = const TableBackgroundWidget();

  @override
  void initState() {
    super.initState();
    
    _initializeWebSocket().then((_) {
      _setupEventCallbacks();
      _initializeGameState();
    });
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
      // Skip automatic instruction triggering if a demo action is active
      // Demo logic will handle showing instructions manually
      if (DemoActionHandler.isDemoActionActive()) {
        _logger.info('📚 _checkAndShowInitialInstructions: Demo action active, skipping automatic instruction triggering', isOn: LOGGING_SWITCH);
        return;
      }
      
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
    
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: LayoutBuilder(
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
            // Wrapped in container with layered casino table border effect
            Container(
              margin: EdgeInsets.all(AppPadding.mediumPadding.top),
              child: Stack(
                children: [
                  // Outer border layer - dark gray/charcoal
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.casinoOuterBorderColor,
                        width: 20.0,
                      ),
                      borderRadius: BorderRadius.circular(24.0),
                      boxShadow: [
                        // Strong outer shadow for depth
                        BoxShadow(
                          color: AppColors.black.withValues(alpha: 0.8),
                          blurRadius: 35.0,
                          spreadRadius: 5.0,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                  // Inner border layer - gradient brown border (fades from light to dark)
                  Container(
                    margin: const EdgeInsets.all(20.0),
                    child: CustomPaint(
                      painter: GradientBorderPainter(
                        startColor: AppColors.casinoBorderColor, // Light brown (outer edge)
                        endColor: const Color(0xFF5D4A2F), // Darker brown (inner edge)
                        borderWidth: 6.0,
                        borderRadius: 12.0,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12.0),
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                  // Main content with felt texture overlay
                  // Margin matches inner border margin (20px) + border width (6px) = 26px
                  // This ensures content starts right after the inner border with no gap
                  Container(
                    margin: const EdgeInsets.all(26.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.0),
                      color: AppColors.pokerTableGreen, // Fill background to prevent black edges
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      clipBehavior: Clip.antiAlias, // Smooth edges without black artifacts
                      child: Stack(
                        children: [
                          // Background layer - poker table green with felt texture
                          // Uses cached widget instance that only builds once on screen load
                          Positioned.fill(
                            child: _tableBackground,
                          ),
                          // Main content - transparent so background shows through
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
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        
        // Instructions Modal Widget - handles its own state subscription
        const InstructionsWidget(),
        
        // Action Text Widget - overlay at bottom showing contextual prompts
        const ActionTextWidget(),
        
            // Messages Modal Widget - handles its own state subscription
            const MessagesWidget(),
          ],
        );
      },
      ),
    ),
    );
  }
}


