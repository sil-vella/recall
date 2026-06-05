import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../utils/widgets/coin_icon.dart';
import '../../../../utils/widgets/felt_texture_widget.dart';
import '../../../../core/managers/auth_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../utils/dutch_game_play_table_style_mapping.dart';
import '../../backend_core/utils/level_matcher.dart';
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
import '../../../../utils/dev_logger.dart';
import 'utils/table_design_style_helpers.dart';

/// When true, logs table design overlay context on game play screen build.
const bool LOGGING_SWITCH = false;

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

/// Background widget for the play surface: felt texture + edge spotlights from [DutchGamePlayTableStyle].
class TableBackgroundWidget extends StatefulWidget {
  final DutchGamePlayTableStyle tableStyle;
  final bool enableFeltTexture;

  const TableBackgroundWidget({
    Key? key,
    required this.tableStyle,
    this.enableFeltTexture = true,
  }) : super(key: key);

  @override
  State<TableBackgroundWidget> createState() => _TableBackgroundWidgetState();
}

class _TableBackgroundWidgetState extends State<TableBackgroundWidget> {
  @override
  Widget build(BuildContext context) {
    final spot = widget.tableStyle.spotlightColor;
    // Inner hot core of edge spotlights (stop 0.0); 40% dimmer than legacy 0.85.
    const innerSpotAlpha = 0.85 * 0.6;
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
              if (widget.enableFeltTexture)
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
                        spot.withValues(alpha: innerSpotAlpha),
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
                        spot.withValues(alpha: innerSpotAlpha),
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
                        spot.withValues(alpha: innerSpotAlpha),
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
                        spot.withValues(alpha: innerSpotAlpha),
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

/// Full-bleed table design overlay: scales to cover the felt and stays centered.
Widget _tableDesignOverlayImage({
  ImageProvider? image,
  String? networkUrl,
  String? fallbackAsset,
}) {
  Widget buildImage(ImageProvider provider) {
    return SizedBox.expand(
      child: Image(
        image: provider,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }

  if (networkUrl != null && networkUrl.isNotEmpty) {
    return SizedBox.expand(
      child: Image.network(
        networkUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          if (fallbackAsset != null && fallbackAsset.isNotEmpty) {
            return buildImage(AssetImage(fallbackAsset));
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  if (image != null) {
    return buildImage(image);
  }

  return const SizedBox.shrink();
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
  bool get showAdBannerBars => false;

  @override
  Decoration? getBackground(BuildContext context) {
    final dutch = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final level = resolveDutchGamePlayTableLevel(dutch);
    final specialEventId = resolveDutchGamePlaySpecialEventId(dutch);
    final felt = DutchGamePlayTableStyles.resolveStyle(
      level: level,
      specialEventId: specialEventId,
    ).feltBackground;
    return BoxDecoration(color: felt);
  }

  @override
  GamePlayScreenState createState() => GamePlayScreenState();
}

class GamePlayScreenState extends BaseScreenState<GamePlayScreen>
    with WidgetsBindingObserver {
  final WebSocketManager _websocketManager = WebSocketManager.instance;
  String? _previousGameId;
  bool _cardBackPrecached = false;
  final Set<String> _coinStreamShownGameIds = {};

  // GlobalKey for the main Stack
  final GlobalKey _mainStackKey = GlobalKey(); // Track game ID to detect navigation away

  /// Last resolved room table tier; used to avoid rebuilding the whole screen on unrelated state churn.
  int? _cachedPlayTableLevel;
  String _cachedEquippedTableDesignId = '';

  void _onStateManagerForTableStyle() {
    if (!mounted) return;
    final dutch = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final level = resolveDutchGamePlayTableLevel(dutch);
    final seId = resolveDutchGamePlaySpecialEventId(dutch);
    final isSpecialEventMatch = seId != null && seId.trim().isNotEmpty;
    final equippedTableDesignId = isSpecialEventMatch
        ? ''
        : TableDesignStyleHelpers.readEquippedTableDesignId(dutch);
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
    AuthManager().updateMainAppState('active_game');
    unawaited(AuthManager().ensureTokensFreshForGameplay());
    unawaited(WakelockPlus.enable());
    final dutch0 = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    _cachedPlayTableLevel = resolveDutchGamePlayTableLevel(dutch0);
    final se0 = resolveDutchGamePlaySpecialEventId(dutch0);
    _cachedEquippedTableDesignId = (se0 != null && se0.trim().isNotEmpty)
        ? ''
        : TableDesignStyleHelpers.readEquippedTableDesignId(dutch0);
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
    
    
    
    // Check if returning to same game and cancel pending leave timer
    if (currentGameId != null && 
        currentGameId == GameCoordinator().pendingLeaveGameId) {
      
      GameCoordinator().cancelLeaveGameTimer(currentGameId);
    }
    
    // Preload card back and special-card backgrounds once when entering game play (match start)
    if (!_cardBackPrecached && mounted) {
      _cardBackPrecached = true;
      precacheImage(const AssetImage(TableDesignStyleHelpers.defaultCardBackAsset), context);
      precacheImage(const AssetImage(TableDesignStyleHelpers.defaultTableOverlayAsset), context);
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
      
    } catch (e, stackTrace) {
      
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
    AuthManager().updateMainAppState('idle');
    unawaited(WakelockPlus.disable());
    StateManager().removeListener(_onStateManagerForTableStyle);
    
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
        
      }
      if (!showInstructions) {
        
        return;
      }
      
      // Check if we're in waiting phase
      final rawPhase = gameState['phase']?.toString();
      final gamePhase = rawPhase == 'waiting_for_players'
          ? 'waiting'
          : (rawPhase ?? 'playing');
      
      if (gamePhase == 'waiting') {
        
        // Check if initial instructions haven't been dismissed
        final instructionsData = dutchGameState['instructions'] as Map<String, dynamic>? ?? {};
        final dontShowAgain = Map<String, bool>.from(
          instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
        );
        
        
        
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
            
          } else {
            
          }
        } else {
          
        }
      }
    } catch (e) {
      
    }
  }

  void _setupEventCallbacks() {
    // Event callbacks are handled by WSEventManager
    // No need to set up specific callbacks here
    // The WSEventManager handles all WebSocket events automatically
  }


  @override
  Widget buildContent(BuildContext context) {
    final dutchSnapshot = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final playTableLevel = resolveDutchGamePlayTableLevel(dutchSnapshot);
    final userStats = dutchSnapshot['userStats'] as Map<String, dynamic>? ?? {};
    final inventory = userStats['inventory'] as Map<String, dynamic>? ?? {};
    final cosmetics = inventory['cosmetics'] as Map<String, dynamic>? ?? {};
    final equipped = cosmetics['equipped'] as Map<String, dynamic>? ?? {};
    final resolvedSpecialEventId = resolveDutchGamePlaySpecialEventId(dutchSnapshot);
    final bool isSpecialEventMatch =
        resolvedSpecialEventId != null && resolvedSpecialEventId.trim().isNotEmpty;
    
    String eventTableDesignOverlayUrl = '';
    if (isSpecialEventMatch) {
      final row = LevelMatcher.specialEventRowById(resolvedSpecialEventId);
      if (row != null) {
        eventTableDesignOverlayUrl =
            LevelMatcher.resolveEventTableDesignOverlayUrl(row) ?? '';
      }
    }
    // Special-event matches own the table cosmetics; ignore user equipped table design.
    final equippedTableDesignId = isSpecialEventMatch
        ? ''
        : (equipped['table_design_id']?.toString().trim() ?? '');
    final currentGameId = dutchSnapshot['currentGameId']?.toString() ?? '';
    if (LOGGING_SWITCH) {
      customlog(
        'GamePlayScreen table design: skinId=$equippedTableDesignId gameId=$currentGameId '
        'specialEvent=$isSpecialEventMatch level=$playTableLevel',
      );
    }
    final specialEventId = resolvedSpecialEventId;
    final tableStyle = DutchGamePlayTableStyles.resolveStyle(
      level: playTableLevel,
      specialEventId: specialEventId,
    );
    final specialEventBorderStyle =
        TableDesignStyleHelpers.specialEventBorderStyleMap(specialEventId);
    final borderColor = isSpecialEventMatch
        ? TableDesignStyleHelpers.outerBorderColorFromStyle(specialEventBorderStyle)
        : TableDesignStyleHelpers.outerBorderColorForDesign(equippedTableDesignId);
    final borderGlow = isSpecialEventMatch
        ? TableDesignStyleHelpers.outerBorderGlowFromStyle(specialEventBorderStyle)
        : TableDesignStyleHelpers.outerBorderGlowForDesign(equippedTableDesignId);
    final borderColors = isSpecialEventMatch
        ? TableDesignStyleHelpers.borderColorsFromStyle(specialEventBorderStyle)
        : TableDesignStyleHelpers.borderColorsForDesign(equippedTableDesignId);
    final isJuventusBorder = isSpecialEventMatch
        ? TableDesignStyleHelpers.isStripeBorderFromStyle(specialEventBorderStyle)
        : TableDesignStyleHelpers.isJuventusTableDesign(equippedTableDesignId);

    // Tier PNG + opacity on the screen backdrop only ([getBackground] green shows through); table card sits above.
    final content = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: AppOpacity.shadow,
                child: DutchGamePlayTableStyles.tableBackGraphicFillFor(
                  level: playTableLevel,
                  specialEventId: specialEventId,
                ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: LayoutBuilder(
              builder: (context, constraints) {
        
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
                            stripeColors: borderColors.isEmpty
                                ? const [AppColors.black, AppColors.white]
                                : borderColors,
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
                          final overlayNetworkUrl = TableDesignStyleHelpers.buildOverlayNetworkUrl(
                            currentGameId: currentGameId,
                            equippedTableDesignId: equippedTableDesignId,
                            imageVersion: 1,
                          );

                          return Stack(
                            children: [
                              Positioned.fill(
                                child: TableBackgroundWidget(
                                  key: ValueKey<String>(
                                    '${playTableLevel}_${specialEventId ?? ''}_$equippedTableDesignId',
                                  ),
                                  tableStyle: tableStyle,
                                  enableFeltTexture: !isSpecialEventMatch,
                                ),
                              ),
                              if (isSpecialEventMatch && eventTableDesignOverlayUrl.isNotEmpty)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: _tableDesignOverlayImage(
                                      networkUrl: eventTableDesignOverlayUrl,
                                      fallbackAsset: TableDesignStyleHelpers.defaultTableOverlayAsset,
                                    ),
                                  ),
                                )
                              else if (overlayNetworkUrl == null)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: TableDesignStyleHelpers.defaultTableOverlayImage(),
                                  ),
                                )
                              else
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: _tableDesignOverlayImage(
                                      networkUrl: overlayNetworkUrl,
                                      fallbackAsset: TableDesignStyleHelpers.defaultTableOverlayAsset,
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
                child: CoinIcon(
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


