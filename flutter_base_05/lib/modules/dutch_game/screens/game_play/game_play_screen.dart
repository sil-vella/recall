import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../utils/widgets/felt_texture_widget.dart';
import '../../../../core/managers/state_manager.dart';
import '../../utils/dutch_game_play_table_style_mapping.dart';
import '../../../../tools/logging/logger.dart';
import 'widgets/game_info_widget.dart';
import 'widgets/unified_game_board_widget.dart';
import '../../widgets/instructions_widget.dart';
import '../../widgets/dutch_slice_builder.dart';
import 'widgets/messages_widget.dart';
import 'widgets/action_text_widget.dart';
import '../../../../core/managers/websockets/websocket_manager.dart';
import '../../utils/game_instructions_provider.dart' as instructions;
import '../../managers/game_coordinator.dart';
import '../demo/demo_action_handler.dart';
import 'utils/table_design_style_helpers.dart';

/// When true, logs screen build and rebuild timing for this screen.
const bool LOGGING_SWITCH = false; // enable-logging-switch.mdc; one switch per file

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

/// Paints an inner shadow (same style as outer table shadow) along the inner edge of the table.
/// Clips to the table rect and draws a blurred stroke so the shadow falls onto the table surface.
class InnerShadowPainter extends CustomPainter {
  final Color color;
  final double blurRadius;
  final double spreadRadius;
  final Offset offset;
  final double borderRadius;

  InnerShadowPainter({
    required this.color,
    this.blurRadius = 35.0,
    this.spreadRadius = 2.0,
    this.offset = const Offset(0, 4),
    this.borderRadius = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );
    canvas.save();
    canvas.clipRRect(rrect);

    // Draw blurred stroke along the inner edge so shadow falls onto the table
    final strokeWidth = blurRadius + spreadRadius;
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius);

    canvas.translate(offset.dx, offset.dy);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(InnerShadowPainter oldDelegate) {
    return color != oldDelegate.color ||
        blurRadius != oldDelegate.blurRadius ||
        spreadRadius != oldDelegate.spreadRadius ||
        offset != oldDelegate.offset ||
        borderRadius != oldDelegate.borderRadius;
  }
}

/// Stroked rounded-rect ring only (no fill) — wide glow band + crisp inner rim for final round.
/// Alpha across the band: 1 from inner edge through midpoint, then linear to 0 at outer edge.
/// Avoids [BoxDecoration] shadows which bleed across the whole felt.
class _FinalRoundEdgeGlowPainter extends CustomPainter {
  final double borderRadius;
  final double pulse;
  final Color color;

  _FinalRoundEdgeGlowPainter({
    required this.borderRadius,
    required this.pulse,
    required this.color,
  });

  static const double _innerInset = 1.5;
  /// Tripled from original ~12px effective band.
  static const double _glowDepth = 36.0;
  static const int _glowSteps = 28;
  static const double _rimStrokeWidth = 6.0;

  /// t: 0 = inner (table side), 1 = outer. Returns 1 for [0, 0.5], then 1→0 on (0.5, 1].
  static double _edgeFade(double t) {
    if (t <= 0.5) return 1.0;
    return (2.0 - 2.0 * t).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final baseA = 0.35 + 0.45 * pulse;
    final maxR = 0.5 * (size.width < size.height ? size.width : size.height);

    // Outermost → innermost bands; skip i==0 (rim draws the inner edge).
    for (int i = _glowSteps - 1; i >= 1; i--) {
      final t = i / (_glowSteps - 1);
      final fade = _edgeFade(t);
      if (fade <= 0) continue;

      final inset = _innerInset - t * _glowDepth;
      final rr = (borderRadius - inset).clamp(0.0, maxR);
      final rect = Rect.fromLTWH(inset, inset, size.width - 2 * inset, size.height - 2 * inset);
      final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rr)));

      final band = Paint()
        ..color = color.withValues(alpha: (baseA * fade * 0.92).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = _glowDepth / _glowSteps + 1.2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawPath(path, band);
    }

    final rrRim = (borderRadius - _innerInset).clamp(0.0, maxR);
    final rimRect = Rect.fromLTWH(
      _innerInset,
      _innerInset,
      size.width - 2 * _innerInset,
      size.height - 2 * _innerInset,
    );
    final rimPath = Path()..addRRect(RRect.fromRectAndRadius(rimRect, Radius.circular(rrRim)));
    final rim = Paint()
      ..color = color.withValues(alpha: (0.5 + 0.45 * pulse).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = _rimStrokeWidth;
    canvas.drawPath(rimPath, rim);
  }

  @override
  bool shouldRepaint(_FinalRoundEdgeGlowPainter oldDelegate) {
    return oldDelegate.pulse != pulse ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.color != color;
  }
}

/// Pulsing glow on the inner felt edge only (ring, not a full-surface overlay).
class _FinalRoundInnerGlowPulse extends StatefulWidget {
  final double borderRadius;

  const _FinalRoundInnerGlowPulse({required this.borderRadius});

  @override
  State<_FinalRoundInnerGlowPulse> createState() => _FinalRoundInnerGlowPulseState();
}

class _FinalRoundInnerGlowPulseState extends State<_FinalRoundInnerGlowPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return CustomPaint(
          painter: _FinalRoundEdgeGlowPainter(
            borderRadius: widget.borderRadius,
            pulse: t,
            color: AppColors.callFinalRoundChipBackground,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// Background widget for the play surface: felt texture + edge spotlights from [DutchGamePlayTableStyle].
class TableBackgroundWidget extends StatefulWidget {
  final DutchGamePlayTableStyle tableStyle;

  const TableBackgroundWidget({Key? key, required this.tableStyle}) : super(key: key);

  @override
  State<TableBackgroundWidget> createState() => _TableBackgroundWidgetState();
}

class _TableBackgroundWidgetState extends State<TableBackgroundWidget> {
  @override
  Widget build(BuildContext context) {
    final spot = widget.tableStyle.spotlightColor;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;

          // Calculate spotlight positions - evenly spaced vertically
          // 2 spotlights from left, 2 from right
          final spotlightSize = 800.0; // Size of circular spotlight
          final topSpotlightY = height * 0.25; // Top spotlight position
          final bottomSpotlightY = height * 0.75; // Bottom spotlight position

          return Stack(
            children: [
              Positioned.fill(
                child: FeltTextureWidget(
                  backgroundColor: widget.tableStyle.feltBackground,
                ),
              ),
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
                        spot.withValues(alpha: 0.85),
                        spot.withValues(alpha: 0.25),
                        spot.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.08, 0.4],
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
                        spot.withValues(alpha: 0.85),
                        spot.withValues(alpha: 0.25),
                        spot.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.08, 0.4],
                    ),
                  ),
                ),
              ),
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
                        spot.withValues(alpha: 0.85),
                        spot.withValues(alpha: 0.25),
                        spot.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.08, 0.4],
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
                        spot.withValues(alpha: 0.85),
                        spot.withValues(alpha: 0.25),
                        spot.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.08, 0.4],
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
  bool get useLogoInAppBar => true;

  @override
  bool get useGlobalKeyForAppBarFeatureSlot => true;

  @override
  Decoration? getBackground(BuildContext context) {
    final dutch = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final level = resolveDutchGamePlayTableLevel(dutch);
    final felt = DutchGamePlayTableStyles.forLevel(level).feltBackground;
    return BoxDecoration(color: felt);
  }

  @override
  GamePlayScreenState createState() => GamePlayScreenState();
}

class GamePlayScreenState extends BaseScreenState<GamePlayScreen>
    with WidgetsBindingObserver {
  final Logger _logger = Logger();
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  String? _previousGameId;
  bool _cardBackPrecached = false;
  final Set<String> _coinStreamShownGameIds = {};

  /// Rebuild count when LOGGING_SWITCH is enabled.
  static int _playScreenRebuildCount = 0;
  
  // GlobalKey for the main Stack
  final GlobalKey _mainStackKey = GlobalKey(); // Track game ID to detect navigation away

  /// Last resolved room table tier; used to avoid rebuilding the whole screen on unrelated state churn.
  int? _cachedPlayTableLevel;
  String _cachedEquippedTableDesignId = '';

  void _onStateManagerForTableStyle() {
    if (!mounted) return;
    final dutch = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final level = resolveDutchGamePlayTableLevel(dutch);
    final equippedTableDesignId = TableDesignStyleHelpers.readEquippedTableDesignId(dutch);
    if (level != _cachedPlayTableLevel || equippedTableDesignId != _cachedEquippedTableDesignId) {
      _cachedPlayTableLevel = level;
      _cachedEquippedTableDesignId = equippedTableDesignId;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(WakelockPlus.enable());
    _cachedPlayTableLevel = resolveDutchGamePlayTableLevel(
      StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {},
    );
    _cachedEquippedTableDesignId = TableDesignStyleHelpers.readEquippedTableDesignId(
      StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {},
    );
    StateManager().addListener(_onStateManagerForTableStyle);

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
    
    if (LOGGING_SWITCH) {
      _logger.info('GamePlay: Screen loaded with game ID: $_previousGameId');
    }
    
    // Check if returning to same game and cancel pending leave timer
    if (currentGameId != null && 
        currentGameId == GameCoordinator().pendingLeaveGameId) {
      if (LOGGING_SWITCH) {
        _logger.info('GamePlay: Returning to same game $currentGameId - cancelling leave timer');
      }
      GameCoordinator().cancelLeaveGameTimer(currentGameId);
    }
    
    // Preload card back and special-card backgrounds once when entering game play (match start)
    if (!_cardBackPrecached && mounted) {
      _cardBackPrecached = true;
      precacheImage(const AssetImage('assets/images/card_back.webp'), context);
      precacheImage(const AssetImage('assets/images/table_logo.webp'), context);
      precacheImage(const AssetImage('assets/images/backgrounds/queen.webp'), context);
      precacheImage(const AssetImage('assets/images/backgrounds/king.webp'), context);
      precacheImage(const AssetImage('assets/images/backgrounds/jack.webp'), context);
      precacheImage(const AssetImage('assets/images/backgrounds/joker.webp'), context);
    }
    
    // Check for initial instructions after dependencies are set (game state should be ready)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowInitialInstructions();
    });
  }

  Future<void> _initializeWebSocket() async {
    try {
      final ok = await _websocketManager.ensureInitializedAndConnected();
      if (LOGGING_SWITCH) {
        _logger.info('GamePlay: ensureInitializedAndConnected => $ok');
      }
    } catch (e, stackTrace) {
      if (LOGGING_SWITCH) {
        _logger.error(
          'GamePlay: WebSocket initialization error',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }
  
  @override
  void deactivate() {
    // Do not clear here. Clear runs only before any match start (createRoom, joinRoom, joinRandomGame, _startPracticeMatch).
    super.deactivate();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(WakelockPlus.disable());
    StateManager().removeListener(_onStateManagerForTableStyle);
    if (LOGGING_SWITCH) {
      _logger.info('GamePlay: Disposing');
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(WakelockPlus.enable());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(WakelockPlus.disable());
        break;
    }
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
        if (LOGGING_SWITCH) {
          _logger.info('📚 _checkAndShowInitialInstructions: Demo action active, skipping automatic instruction triggering');
        }
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
        if (LOGGING_SWITCH) {
          _logger.info('📚 _checkAndShowInitialInstructions: showInstructions not in gameState, checking practiceSettings=$showInstructions');
        }
      }
      if (!showInstructions) {
        if (LOGGING_SWITCH) {
          _logger.info('📚 _checkAndShowInitialInstructions: Instructions disabled, skipping');
        }
        return;
      }
      
      // Check if we're in waiting phase
      final rawPhase = gameState['phase']?.toString();
      final gamePhase = rawPhase == 'waiting_for_players'
          ? 'waiting'
          : (rawPhase ?? 'playing');
      
      if (gamePhase == 'waiting') {
        if (LOGGING_SWITCH) {
          _logger.info('📚 _checkAndShowInitialInstructions: In waiting phase, showInstructions=$showInstructions');
        }
        // Check if initial instructions haven't been dismissed
        final instructionsData = dutchGameState['instructions'] as Map<String, dynamic>? ?? {};
        final dontShowAgain = Map<String, bool>.from(
          instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
        );
        
        if (LOGGING_SWITCH) {
          _logger.info('📚 _checkAndShowInitialInstructions: dontShowAgain[initial]=${dontShowAgain['initial']}');
        }
        
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
            if (LOGGING_SWITCH) {
              _logger.info('📚 _checkAndShowInitialInstructions: Initial instructions triggered from screen init');
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.info('📚 _checkAndShowInitialInstructions: Initial instructions skipped - already showing');
            }
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('📚 _checkAndShowInitialInstructions: Initial instructions skipped - already marked as dontShowAgain');
          }
        }
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('Error checking initial instructions: $e');
      }
    }
  }

  void _setupEventCallbacks() {
    // Event callbacks are handled by WSEventManager
    // No need to set up specific callbacks here
    // The WSEventManager handles all WebSocket events automatically
  }


  @override
  Widget buildContent(BuildContext context) {
    final stopwatch = LOGGING_SWITCH ? (Stopwatch()..start()) : null;
    if (LOGGING_SWITCH) {
      _logger.info('GamePlayScreen: buildContent called');
    }

    final dutchSnapshot = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final playTableLevel = resolveDutchGamePlayTableLevel(dutchSnapshot);
    final userStats = dutchSnapshot['userStats'] as Map<String, dynamic>? ?? {};
    final inventory = userStats['inventory'] as Map<String, dynamic>? ?? {};
    final cosmetics = inventory['cosmetics'] as Map<String, dynamic>? ?? {};
    final equipped = cosmetics['equipped'] as Map<String, dynamic>? ?? {};
    final equippedTableDesignId = equipped['table_design_id']?.toString() ?? '';
    final currentGameId = dutchSnapshot['currentGameId']?.toString() ?? '';
    final tableStyle = DutchGamePlayTableStyles.forLevel(playTableLevel);
    final borderColor = TableDesignStyleHelpers.outerBorderColorForDesign(equippedTableDesignId);
    final borderGlow = TableDesignStyleHelpers.outerBorderGlowForDesign(equippedTableDesignId);
    final isJuventusBorder = TableDesignStyleHelpers.isJuventusTableDesign(equippedTableDesignId);

    // Tier PNG + opacity on the screen backdrop only ([getBackground] green shows through); table card sits above.
    final content = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: AppOpacity.shadow,
              child: Image.asset(
                DutchGamePlayTableStyles.tableBackGraphicAssetPath(playTableLevel),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: LayoutBuilder(
              builder: (context, constraints) {
        if (LOGGING_SWITCH) {
          _logger.info(
            'GamePlayScreen: LayoutBuilder - maxHeight=${constraints.maxHeight}, '
            'maxWidth=${constraints.maxWidth}',
          );
        }
        // Outer border (customizable): doubled thickness from previous sizing.
        final tableWidth = constraints.maxWidth;
        final outerBorderWidth = (tableWidth * 0.04).clamp(0.0, 50.0);

        return Stack(
          key: _mainStackKey,
          clipBehavior: Clip.none,
          children: [
            // Main game content - full size of content area (no outer padding/margin)
            Stack(
              children: [
                // Outer border layer - dark gray/charcoal (% of table width)
                Container(
                  decoration: BoxDecoration(
                    border: isJuventusBorder
                        ? null
                        : Border.all(
                            color: borderColor,
                            width: outerBorderWidth,
                          ),
                    borderRadius: BorderRadius.circular(24.0),
                    boxShadow: [
                      // Strong outer shadow for depth
                      BoxShadow(
                        color: borderGlow,
                        blurRadius: 35.0,
                        spreadRadius: 5.0,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: isJuventusBorder
                      ? CustomPaint(
                          painter: JuventusStripeBorderPainter(
                            borderWidth: outerBorderWidth,
                            borderRadius: 24.0,
                          ),
                          child: const SizedBox.expand(),
                        )
                      : null,
                ),
                  // Inner border layer - inset by outer border width so outer border stays visible
                  Container(
                    margin: EdgeInsets.all(outerBorderWidth),
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
                  // Main content - inset by outer border + gradient width (6px)
                  Container(
                    margin: EdgeInsets.all(outerBorderWidth + 6.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.0),
                      color: tableStyle.feltBackground, // Match felt; prevents black edges at clip
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      clipBehavior: Clip.antiAlias, // Smooth edges without black artifacts
                      child: LayoutBuilder(
                        builder: (context, innerConstraints) {
                          final isPracticeMode = currentGameId.startsWith('practice_room_');
                          final overlayUrl = TableDesignStyleHelpers.buildOverlayUrl(
                            currentGameId: currentGameId,
                            equippedTableDesignId: equippedTableDesignId,
                            imageVersion: 1,
                          );
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: TableBackgroundWidget(
                                  key: ValueKey<String>('${playTableLevel}_$equippedTableDesignId'),
                                  tableStyle: tableStyle,
                                ),
                              ),
                              // Table cosmetic overlay: centered and 90% of table area with preserved ratio.
                              Positioned.fill(
                                child: Center(
                                  child: SizedBox(
                                    // Strict 65% width of table; height is capped to 65% only if ratio would overflow.
                                    width: innerConstraints.maxWidth * 0.65,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: innerConstraints.maxHeight * 0.65,
                                      ),
                                      child: Opacity(
                                        opacity: 0.22,
                                        child: FittedBox(
                                          fit: BoxFit.fitWidth,
                                          alignment: Alignment.center,
                                          child: isPracticeMode
                                              ? Image(
                                                  image: const AssetImage('assets/images/table_logo.webp'),
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (context, error, stackTrace) =>
                                                      const SizedBox.shrink(),
                                                )
                                              : Image.network(
                                                  overlayUrl,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Image(
                                                      image: const AssetImage('assets/images/table_logo.webp'),
                                                      fit: BoxFit.contain,
                                                      errorBuilder: (context, err, st) =>
                                                          const SizedBox.shrink(),
                                                    );
                                                  },
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Main content - transparent so background shows through
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Game Information Widget - takes natural height
                                  const GameInfoWidget(),
                                  SizedBox(height: AppPadding.smallPadding.top),
                                  // Unified Game Board Widget - takes all remaining available space
                                  Expanded(
                                    child: const UnifiedGameBoardWidget(),
                                  ),
                                ],
                              ),
                              // Inner shadow - same as outer, cast from inside the light brown border onto the table
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: InnerShadowPainter(
                                      color: AppColors.black.withValues(alpha: 0.8),
                                      blurRadius: 3.0,
                                      spreadRadius: 2.0,
                                      offset: const Offset(0, 2),
                                      borderRadius: 3.0,
                                    ),
                                    size: Size(innerConstraints.maxWidth, innerConstraints.maxHeight),
                                  ),
                                ),
                              ),
                              // Final round: pulsing glow on inner felt edge (matches call-final-round chip color)
                              Positioned.fill(
                                child: DutchSliceBuilder<bool>(
                                  selector: (dutch) {
                                    final gameId = dutch['currentGameId']?.toString() ?? '';
                                    final games = dutch['games'] as Map<String, dynamic>? ?? {};
                                    final game = games[gameId] as Map<String, dynamic>?;
                                    final gs = game?['gameData'] as Map<String, dynamic>?;
                                    final gameState = gs?['game_state'] as Map<String, dynamic>?;
                                    return gameState?['finalRoundActive'] as bool? ?? false;
                                  },
                                  builder: (context, finalRoundActive, _) {
                                    if (!finalRoundActive) return const SizedBox.shrink();
                                    return const IgnorePointer(
                                      child: _FinalRoundInnerGlowPulse(borderRadius: 8.0),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
        
        // Instructions Modal Widget - handles its own state subscription
        const InstructionsWidget(),
        
        // Action Text Widget - overlay at bottom showing contextual prompts
        const ActionTextWidget(),
        
            // Messages Modal Widget - handles its own state subscription
            const MessagesWidget(),
            // Coin stream overlay when user wins (non-practice, non-promotional)
            DutchSliceBuilder<Map<String, dynamic>>(
              selector: (dutchState) => {
                'gamePhase': dutchState['gamePhase']?.toString() ?? '',
                'messages': Map<String, dynamic>.from(
                  dutchState['messages'] as Map<String, dynamic>? ?? {},
                ),
                'currentGameId': dutchState['currentGameId']?.toString() ?? '',
                'subscriptionTier': (dutchState['userStats'] as Map<String, dynamic>?)?['subscription_tier']
                        ?.toString() ??
                    'promotional',
              },
              builder: (context, slice, _) {
                final gamePhase = slice['gamePhase']?.toString() ?? '';
                final messages = slice['messages'] as Map<String, dynamic>? ?? {};
                final isCurrentUserWinner = messages['isCurrentUserWinner'] == true;
                final currentGameId = slice['currentGameId']?.toString() ?? '';
                final subscriptionTier = slice['subscriptionTier']?.toString() ?? 'promotional';
                final showCoinStream = gamePhase == 'game_ended' &&
                    isCurrentUserWinner &&
                    !currentGameId.startsWith('practice_room_') &&
                    subscriptionTier != 'promotional' &&
                    appBarFeatureSlotKeyIfUsed != null &&
                    !_coinStreamShownGameIds.contains(currentGameId);
                if (!showCoinStream) return const SizedBox.shrink();
                return _GameEndCoinStreamTrigger(
                  targetKey: appBarFeatureSlotKeyIfUsed!,
                  gameId: currentGameId,
                  onShown: () {
                    setState(() {
                      _coinStreamShownGameIds.add(currentGameId);
                    });
                  },
                );
              },
            ),
          ],
        );
              },
            ),
          ),
        ),
      ],
    );
    if (LOGGING_SWITCH && stopwatch != null) {
      stopwatch.stop();
      _playScreenRebuildCount++;
      _logger.info('📊 GamePlayScreen REBUILD #$_playScreenRebuildCount duration=${stopwatch.elapsedMilliseconds} ms');
    }
    return content;
  }
}

/// Triggers the coin stream overlay once when game ends and user is winner (non-practice, non-promotional).
class _GameEndCoinStreamTrigger extends StatefulWidget {
  final GlobalKey targetKey;
  final String gameId;
  final VoidCallback onShown;

  const _GameEndCoinStreamTrigger({
    required this.targetKey,
    required this.gameId,
    required this.onShown,
  });

  @override
  State<_GameEndCoinStreamTrigger> createState() => _GameEndCoinStreamTriggerState();
}

class _GameEndCoinStreamTriggerState extends State<_GameEndCoinStreamTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => _CoinStreamOverlay(
          targetKey: widget.targetKey,
          onComplete: () {
            entry.remove();
          },
        ),
      );
      overlay.insert(entry);
      widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Full-screen overlay that animates coins from center to the app bar coins slot.
class _CoinStreamOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final VoidCallback onComplete;

  const _CoinStreamOverlay({
    required this.targetKey,
    required this.onComplete,
  });

  @override
  State<_CoinStreamOverlay> createState() => _CoinStreamOverlayState();
}

class _CoinStreamOverlayState extends State<_CoinStreamOverlay> with SingleTickerProviderStateMixin {
  static const int _particleCount = 12;
  static const Duration _duration = Duration(milliseconds: 3000);

  late AnimationController _controller;
  Offset? _targetOffset;
  Size? _targetSize;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        setState(() {
          _targetOffset = box.localToGlobal(Offset.zero);
          _targetSize = box.size;
        });
        _controller.forward();
      } else {
        widget.onComplete();
      }
    });
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_targetOffset == null || _targetSize == null) {
      return const SizedBox.shrink();
    }
    final size = MediaQuery.sizeOf(context);
    final source = Offset(size.width * 0.5, size.height * 0.4);
    final target = Offset(
      _targetOffset!.dx + _targetSize!.width * 0.5,
      _targetOffset!.dy + _targetSize!.height * 0.5,
    );
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: List.generate(_particleCount, (i) {
              final stagger = i / _particleCount;
              final t = ((_controller.value * 1.2) - stagger).clamp(0.0, 1.0);
              final curveT = Curves.easeInOutCubic.transform(t);
              final x = source.dx + (target.dx - source.dx) * curveT;
              final y = source.dy + (target.dy - source.dy) * curveT;
              return Positioned(
                left: x - 12,
                top: y - 12,
                child: Icon(
                  Icons.monetization_on,
                  size: 24,
                  color: AppColors.accentColor2.withValues(alpha: 1.0 - t * 0.5),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}


