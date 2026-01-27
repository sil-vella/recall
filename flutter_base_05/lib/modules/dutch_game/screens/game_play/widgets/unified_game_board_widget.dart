import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../utils/card_dimensions.dart';
import '../../../widgets/card_widget.dart';
import 'player_status_chip_widget.dart';
import 'circular_timer_widget.dart';
import '../../../managers/player_action.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../dutch_game/managers/dutch_event_handler_callbacks.dart';
import '../../../../../utils/consts/theme_consts.dart';
import '../../demo/demo_functionality.dart';
import '../functionality/playscreenfunctions.dart';
import '../functionality/animations.dart';

const bool LOGGING_SWITCH = true; // Enabled for testing and debugging

/// Unified widget that combines OpponentsPanelWidget, DrawPileWidget, 
/// DiscardPileWidget, MatchPotWidget, and MyHandWidget into a single widget.
class UnifiedGameBoardWidget extends StatefulWidget {
  const UnifiedGameBoardWidget({Key? key}) : super(key: key);

  @override
  State<UnifiedGameBoardWidget> createState() => _UnifiedGameBoardWidgetState();
}

class _UnifiedGameBoardWidgetState extends State<UnifiedGameBoardWidget> with TickerProviderStateMixin {
  final Logger _logger = Logger();
  
  // ========== Opponents Panel State ==========
  String? _clickedCardId;
  bool _isCardsToPeekProtected = false;
  List<dynamic>? _protectedCardsToPeek;
  Timer? _cardsToPeekProtectionTimer;
  
  // ========== Draw Pile State ==========
  String? _clickedPileType;
  AnimationController? _glowAnimationController;
  Animation<double>? _glowAnimation;
  
  // ========== Discard Pile State ==========
  // (No state needed - using _cardKeys for all cards)
  
  // ========== My Hand State ==========
  int _initialPeekSelectionCount = 0;
  List<String> _initialPeekSelectedCardIds = [];
  bool _isProcessingAction = false;
  bool _isMyHandCardsToPeekProtected = false;
  List<dynamic>? _protectedMyHandCardsToPeek;
  Timer? _myHandCardsToPeekProtectionTimer;
  String? _previousPlayerStatus; // Track previous status to detect transitions
  
  // ========== Card Keys (for widget identification) ==========
  /// Map of cardId -> GlobalKey for all cards (reused across rebuilds)
  final Map<String, GlobalKey> _cardKeys = {};
  
  /// GlobalKey for game board section
  final GlobalKey _gameBoardKey = GlobalKey(debugLabel: 'game_board_section');
  
  /// GlobalKey for draw pile section
  final GlobalKey _drawPileKey = GlobalKey(debugLabel: 'draw_pile_section');
  
  /// GlobalKey for discard pile section
  final GlobalKey _discardPileKey = GlobalKey(debugLabel: 'discard_pile_section');
  
  /// GlobalKey for the main Stack (for overlay positioning)
  final GlobalKey _mainStackKey = GlobalKey(debugLabel: 'main_stack');
  
  /// PlayScreenFunctions instance for getting RenderBox information
  late final PlayScreenFunctions _playScreenFunctions = PlayScreenFunctions(
    drawPileKey: _drawPileKey,
    discardPileKey: _discardPileKey,
    gameBoardKey: _gameBoardKey,
  )..onCardBoundsChanged = () {
      // Trigger rebuild when card bounds change
      if (mounted) {
        setState(() {});
      }
    };
  
  // ========== State Interception (prev_state_* slices) ==========
  /// Local cache of state slices with prev_state_* prefix for animation timing
  /// This cache holds the previous state that widgets read from, allowing animations
  /// to run before the widgets update to the new state
  Map<String, dynamic> _prevStateCache = {};
  
  /// Initialize prev_state cache from actual state
  void _initializePrevStateCache() {
    final actualState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    _prevStateCache = Map<String, dynamic>.from(actualState);
  }
  
  /// Update prev_state cache from actual state (called after animations complete)
  void _updatePrevStateCache() {
    final actualState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    _prevStateCache = Map<String, dynamic>.from(actualState);
  }
  
  /// Get prev_state dutch_game state (for widgets to read from)
  /// Returns the cached previous state, allowing animations time to complete
  /// before widgets update to new state
  Map<String, dynamic> _getPrevStateDutchGame() {
    // If cache is empty, initialize from actual state
    if (_prevStateCache.isEmpty) {
      _initializePrevStateCache();
    }
    
    // Return cached prev_state version
    return Map<String, dynamic>.from(_prevStateCache);
  }

  @override
  void initState() {
    super.initState();
    // Initialize glow animation controller
    _glowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowAnimationController!,
      curve: Curves.easeInOut,
    ));
    
    // Initialize prev_state cache from actual state
    _initializePrevStateCache();
    
    // Listen to state changes and update prev_state after a delay (for animations)
    StateManager().addListener(_onStateChanged);
  }
  
  /// Handle state changes - update prev_state cache after animations complete
  void _onStateChanged() async {
    if (!mounted) return;
    
    // Get current state
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    
    // If already processing, cache this state update (replacing any previous cached state)
    if (_isProcessingStateChange) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _onStateChanged: Already processing, caching state update');
      }
      _cachedStateUpdate = currentState;
      return;
    }
    
    // Process this state update
    await _processStateUpdate(currentState);
  }
  
  /// Process a state update - handle animations and update prev_state
  Future<void> _processStateUpdate(Map<String, dynamic> currentState) async {
    if (!mounted) return;
    
    _isProcessingStateChange = true;
    
    try {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _processStateUpdate: Starting state change processing');
      }
      
      // Clear any cached state (we're processing now)
      _cachedStateUpdate = null;
      
      // Cancel any existing timeout timer
      _animationTimeoutTimer?.cancel();
      _animationTimeoutTimer = null;
      
      final games = currentState['games'] as Map<String, dynamic>? ?? {};
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      
      if (currentGameId.isEmpty) {
        // No game active, just update prev_state
        _updatePrevStateCache();
        if (mounted) setState(() {});
        return;
      }
      
      final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
      final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
      final players = gameState['players'] as List<dynamic>? ?? [];
      
      // Collect all actions from players and trigger animations
      List<Future<void>> animationFutures = [];
      
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _processStateUpdate: Checking ${players.length} players for actions');
      }
      
      for (var player in players) {
        if (player is! Map<String, dynamic>) continue;
        
        final playerId = player['id']?.toString();
        final action = player['action']?.toString();
        final actionData = player['actionData'] as Map<String, dynamic>?;
        
        if (LOGGING_SWITCH) {
          _logger.info('🎬 _processStateUpdate: Player $playerId - action: $action, actionData: $actionData');
        }
        
        if (action != null && actionData != null && Animations.requiresAnimation(action)) {
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _processStateUpdate: Action $action requires animation');
          }
          
          // Validate action data
          if (Animations.validateActionData(action, actionData)) {
            if (LOGGING_SWITCH) {
              _logger.info('🎬 _processStateUpdate: Action data validated successfully');
            }
            
            // Check if already in active animations or already processed
            if (!_activeAnimations.containsKey(action)) {
              if (LOGGING_SWITCH) {
                _logger.info('🎬 _processStateUpdate: Triggering animation for action: $action');
              }
              // Trigger animation in overlay
              final future = _triggerAnimation(action, actionData);
              if (future != null) {
                animationFutures.add(future);
              }
            } else {
              if (LOGGING_SWITCH) {
                _logger.info('🎬 _processStateUpdate: Action $action already in active animations, skipping');
              }
            }
          } else {
            if (LOGGING_SWITCH) {
              _logger.warning('🎬 _processStateUpdate: Action data validation failed for action: $action');
            }
          }
        }
      }
      
      // Set up 4-second timeout to bypass animation wait if needed
      bool timeoutTriggered = false;
      if (animationFutures.isNotEmpty) {
        _animationTimeoutTimer = Timer(const Duration(seconds: 4), () {
          if (mounted && !timeoutTriggered) {
            timeoutTriggered = true;
            if (LOGGING_SWITCH) {
              _logger.warning('🎬 _processStateUpdate: Animation timeout (4s) - clearing animations and continuing');
            }
            
            // Clear all active animations
            for (final animData in _activeAnimations.values) {
              final controller = animData['controller'] as AnimationController?;
              controller?.dispose();
            }
            _activeAnimations.clear();
            
            // Hide overlay
            if (mounted) {
              setState(() {});
            }
            
            // Continue with state update
            _completeStateUpdate();
          }
        });
      }
      
      // Wait for all animations to complete BEFORE updating prev_state
      if (animationFutures.isNotEmpty) {
        if (LOGGING_SWITCH) {
          _logger.info('🎬 _processStateUpdate: Waiting for ${animationFutures.length} animation(s) to complete...');
        }
        
        try {
          await Future.wait(animationFutures);
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _processStateUpdate: All animations completed, now updating prev_state');
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.error('🎬 _processStateUpdate: Animation error: $e');
          }
        }
        
        // Cancel timeout timer if animations completed in time
        _animationTimeoutTimer?.cancel();
        _animationTimeoutTimer = null;
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('🎬 _processStateUpdate: No animations to wait for, updating prev_state immediately');
        }
      }
      
      // Complete state update
      _completeStateUpdate();
    } finally {
      _isProcessingStateChange = false;
    }
  }
  
  /// Complete state update - update prev_state and process any cached state
  void _completeStateUpdate() {
    if (!mounted) return;
    
    // Update prev_state cache
    _updatePrevStateCache();
    setState(() {});
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _completeStateUpdate: prev_state updated');
    }
    
    // Check if there's a cached state update to process
    final cachedState = _cachedStateUpdate;
    if (cachedState != null) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _completeStateUpdate: Found cached state update, processing...');
      }
      _cachedStateUpdate = null; // Clear cache before processing
      
      // Process cached state update (this will set _isProcessingStateChange again)
      _processStateUpdate(cachedState);
    } else {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _completeStateUpdate: No cached state update, processing complete');
      }
    }
  }

  @override
  void dispose() {
    _cardsToPeekProtectionTimer?.cancel();
    _myHandCardsToPeekProtectionTimer?.cancel();
    _glowAnimationController?.dispose();
    _animationTimeoutTimer?.cancel();
    
    // Dispose all active animation controllers
    for (final animData in _activeAnimations.values) {
      final controller = animData['controller'] as AnimationController?;
      controller?.dispose();
    }
    _activeAnimations.clear();
    
    StateManager().removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Schedule position update (rate-limited and uses postFrameCallback)
    _playScreenFunctions.updatePilePositions(
      onUpdate: (message) {
        if (LOGGING_SWITCH) {
          _logger.debug(message);
        }
      },
      onBoundsChanged: () {
        // Trigger rebuild when bounds change to update the overlay borders
        if (mounted) {
          setState(() {});
        }
      },
    );
    
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        return Stack(
          key: _mainStackKey,
          clipBehavior: Clip.none,
          children: [
            // Main widget tree
            LayoutBuilder(
              builder: (context, constraints) {
                // New layout: Opponents spread evenly, Game Board above My Hand
                return Column(
                  children: [
                    // Opponents Panel Section - spread evenly vertically
                    Expanded(
                      child: _buildOpponentsPanel(),
                    ),
                    
                    // Spacer above game board (doubled)
                    const SizedBox(height: 32),
                    
                    // Game Board Section - Draw Pile, Match Pot, Discard Pile (just above My Hand)
                    _buildGameBoard(),
                    
                    // Small spacer below game board
                    const SizedBox(height: 16),
                    
                    // My Hand Section - at the bottom
                    _buildMyHand(),
                  ],
                );
              },
            ),
            // Animation overlay layer for card transitions
            _buildAnimationOverlay(),
          ],
        );
      },
    );
  }
  
  // ========== Card Key Management ==========
  
  /// Get or create GlobalKey for a card (for widget identification)
  GlobalKey _getOrCreateCardKey(String cardId, String keyType) {
    final key = '${keyType}_$cardId';
    if (!_cardKeys.containsKey(key)) {
      _cardKeys[key] = GlobalKey(debugLabel: key);
    }
    return _cardKeys[key]!;
  }
  
  // ========== Position and Size Getter Methods ==========
  
  /// Get cached draw pile bounds (position and size)
  /// Returns the last cached value from PlayScreenFunctions
  Map<String, dynamic>? getDrawPileBounds() => _playScreenFunctions.getCachedDrawPileBounds();
  
  /// Get cached discard pile bounds (position and size)
  /// Returns the last cached value from PlayScreenFunctions
  Map<String, dynamic>? getDiscardPileBounds() => _playScreenFunctions.getCachedDiscardPileBounds();
  
  /// Get cached bounds for a specific my hand card by index
  /// Returns the last cached value from PlayScreenFunctions
  Map<String, dynamic>? getMyHandCardBounds(int index) => _playScreenFunctions.getCachedMyHandCardBounds(index);
  
  /// Get all cached my hand card bounds
  Map<int, Map<String, dynamic>> getMyHandCardBoundsAll() => _playScreenFunctions.getCachedMyHandCardBoundsAll();
  
  /// Get cached game board bounds (position and size)
  /// Returns the last cached value from PlayScreenFunctions
  Map<String, dynamic>? getGameBoardBounds() => _playScreenFunctions.getCachedGameBoardBounds();
  
  // ========== Animation Overlay ==========
  
  /// Active animations map: actionName -> animation data
  final Map<String, Map<String, dynamic>> _activeAnimations = {};
  
  /// Flag to prevent concurrent state change handling
  bool _isProcessingStateChange = false;
  
  /// Cached state update - stores the latest state update attempt while processing
  Map<String, dynamic>? _cachedStateUpdate;
  
  /// Timer for animation timeout (4 seconds)
  Timer? _animationTimeoutTimer;
  
  /// Build animation overlay layer for card transitions
  Widget _buildAnimationOverlay() {
    if (_activeAnimations.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Get the Stack's global position to convert global coordinates to local
    final stackContext = _mainStackKey.currentContext;
    Offset stackGlobalOffset = Offset.zero;
    if (stackContext != null) {
      final stackRenderBox = stackContext.findRenderObject() as RenderBox?;
      if (stackRenderBox != null) {
        stackGlobalOffset = stackRenderBox.localToGlobal(Offset.zero);
      }
    }
    
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: _activeAnimations.values.map((animData) {
          return _buildAnimatedCard(animData, stackGlobalOffset);
        }).toList(),
      ),
    );
  }
  
  /// Trigger animation for an action - creates animation controller and adds to overlay
  Future<void>? _triggerAnimation(String actionName, Map<String, dynamic> actionData) {
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _triggerAnimation: Starting for action: $actionName');
      _logger.info('🎬 _triggerAnimation: actionData: $actionData');
    }
    
    // Check if already cached/processed
    if (_activeAnimations.containsKey(actionName)) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _triggerAnimation: Action $actionName already in active animations, skipping');
      }
      return null;
    }
    
    final animationType = Animations.getAnimationTypeForAction(actionName);
    if (animationType == AnimationType.none) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _triggerAnimation: AnimationType is none, skipping');
      }
      return null;
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _triggerAnimation: AnimationType: $animationType');
    }
    
    final duration = Animations.getAnimationDuration(animationType);
    final curve = Animations.getAnimationCurve(animationType);
    
    // Get current user's playerId to determine if this is my hand or opponent's hand
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _triggerAnimation: Current user ID: $currentUserId');
    }
    
    // Get source and destination bounds
    Map<String, dynamic>? sourceBounds;
    Map<String, dynamic>? destBounds;
    
    final card1Data = actionData['card1Data'] as Map<String, dynamic>?;
    if (card1Data != null) {
      final playerId = card1Data['playerId']?.toString();
      final cardIndex = card1Data['cardIndex'] as int?;
      
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _triggerAnimation: card1Data - playerId: $playerId, cardIndex: $cardIndex');
      }
      
      if (playerId != null && cardIndex != null) {
        // Check if this is the current user's hand or an opponent's hand
        final isMyHand = playerId == currentUserId;
        
        if (LOGGING_SWITCH) {
          _logger.info('🎬 _triggerAnimation: isMyHand: $isMyHand (playerId: $playerId, currentUserId: $currentUserId)');
        }
        
        // Get destination bounds based on whether it's my hand or opponent's hand
        if (isMyHand) {
          destBounds = _playScreenFunctions.getCachedMyHandCardBounds(cardIndex);
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _triggerAnimation: My hand bounds for index $cardIndex: $destBounds');
          }
        } else {
          // Log all available opponent bounds for debugging
          if (LOGGING_SWITCH) {
            final allOpponentBounds = _playScreenFunctions.getCachedOpponentCardBoundsAll();
            _logger.info('🎬 _triggerAnimation: Available opponent bounds keys: ${allOpponentBounds.keys.toList()}');
            if (allOpponentBounds.containsKey(playerId)) {
              _logger.info('🎬 _triggerAnimation: Opponent $playerId has bounds for indices: ${allOpponentBounds[playerId]?.keys.toList()}');
            } else {
              _logger.warning('🎬 _triggerAnimation: Opponent $playerId NOT found in cached bounds!');
            }
          }
          
          destBounds = _playScreenFunctions.getCachedOpponentCardBounds(playerId, cardIndex);
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _triggerAnimation: Opponent ($playerId) hand bounds for index $cardIndex: $destBounds');
          }
        }
        
        // For moveCard, source is draw pile
        if (animationType == AnimationType.moveCard) {
          sourceBounds = _playScreenFunctions.getCachedDrawPileBounds();
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _triggerAnimation: Draw pile bounds: $sourceBounds');
          }
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.warning('🎬 _triggerAnimation: Missing playerId or cardIndex in card1Data');
        }
      }
    } else {
      if (LOGGING_SWITCH) {
        _logger.warning('🎬 _triggerAnimation: Missing card1Data in actionData');
      }
    }
    
    if (sourceBounds == null || destBounds == null) {
      if (LOGGING_SWITCH) {
        _logger.warning('🎬 _triggerAnimation: Missing bounds - sourceBounds: ${sourceBounds != null}, destBounds: ${destBounds != null}');
      }
      return null;
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _triggerAnimation: Successfully got bounds - proceeding with animation');
    }
    
    // Create animation controller
    final controller = AnimationController(
      duration: duration,
      vsync: this,
    );
    
    final animation = CurvedAnimation(
      parent: controller,
      curve: curve,
    );
    
    // Get card data for the animation
    Map<String, dynamic>? cardData;
    if (card1Data != null) {
      final playerId = card1Data['playerId']?.toString();
      final cardIndex = card1Data['cardIndex'] as int?;
      
      if (playerId != null && cardIndex != null) {
        // Get card data from game state
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final games = currentState['games'] as Map<String, dynamic>? ?? {};
        final currentGameId = currentState['currentGameId']?.toString() ?? '';
        
        if (currentGameId.isNotEmpty && games.containsKey(currentGameId)) {
          final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
          final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
          final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
          final players = gameState['players'] as List<dynamic>? ?? [];
          
          // Find the player
          for (var player in players) {
            if (player is Map<String, dynamic> && player['id']?.toString() == playerId) {
              final hand = player['hand'] as List<dynamic>? ?? [];
              if (cardIndex < hand.length) {
                final card = hand[cardIndex];
                if (card is Map<String, dynamic>) {
                  cardData = card;
                  break;
                }
              }
            }
          }
        }
      }
    }
    
    // Store animation data
    _activeAnimations[actionName] = {
      'animationType': animationType,
      'sourceBounds': sourceBounds,
      'destBounds': destBounds,
      'controller': controller,
      'animation': animation,
      'cardData': cardData, // Store card data for rendering
    };
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _triggerAnimation: Animation stored, starting animation controller');
    }
    
    // Trigger rebuild to show animation (this just shows the overlay, doesn't update prev_state)
    if (mounted) {
      setState(() {});
    }
    
    // Start animation and return future that completes when animation finishes
    // The future from controller.forward() completes when the animation finishes
    return controller.forward().then((_) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _triggerAnimation: Animation completed for $actionName');
      }
      
      // Animation complete - remove from active animations
      if (mounted) {
        _activeAnimations.remove(actionName);
        controller.dispose();
        setState(() {}); // Remove animation from overlay
      }
    }).catchError((error) {
      if (LOGGING_SWITCH) {
        _logger.error('🎬 _triggerAnimation: Animation error for $actionName: $error');
      }
      if (mounted) {
        _activeAnimations.remove(actionName);
        controller.dispose();
      }
      // Re-throw to propagate error
      throw error;
    });
  }
  
  /// Build an animated card widget for the overlay
  /// This is just a visual overlay card, not tracking its own position
  Widget _buildAnimatedCard(Map<String, dynamic> animData, Offset stackGlobalOffset) {
    final animationType = animData['animationType'] as AnimationType?;
    final sourceBounds = animData['sourceBounds'] as Map<String, dynamic>?;
    final destBounds = animData['destBounds'] as Map<String, dynamic>?;
    final animationController = animData['controller'] as AnimationController?;
    final animation = animData['animation'] as Animation<double>?;
    final cardData = animData['cardData'] as Map<String, dynamic>?;
    
    if (animationType == null || sourceBounds == null || animationController == null || animation == null) {
      return const SizedBox.shrink();
    }
    
    // Get source position and size (convert global to local)
    final sourcePosition = sourceBounds['position'] as Offset?;
    final sourceSize = sourceBounds['size'] as Size?;
    
    if (sourcePosition == null || sourceSize == null) {
      return const SizedBox.shrink();
    }
    
    final localSourcePosition = sourcePosition - stackGlobalOffset;
    
    // Calculate destination position if available (for interpolation)
    Offset? localDestPosition;
    Size? destSize;
    if (destBounds != null) {
      final destPosition = destBounds['position'] as Offset?;
      destSize = destBounds['size'] as Size?;
      if (destPosition != null) {
        localDestPosition = destPosition - stackGlobalOffset;
      }
    }
    
    // Use destination size if available, otherwise use source size
    final cardSize = destSize ?? sourceSize;
    
    // Build card widget using actual CardWidget
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // For moveCard animation, interpolate between source and destination positions
        // For other animations, just use source position
        Offset cardPosition = localSourcePosition;
        if (animationType == AnimationType.moveCard && localDestPosition != null) {
          cardPosition = Offset.lerp(localSourcePosition, localDestPosition, animation.value) ?? localSourcePosition;
        }
        
        // Build card widget
        Widget cardWidget;
        if (cardData != null) {
          // Use actual card data to render CardWidget
          final cardModel = CardModel.fromMap(cardData);
          cardWidget = CardWidget(
            card: cardModel,
            dimensions: cardSize,
            config: CardDisplayConfig.forDiscardPile(), // Use discard pile config (face up)
            showBack: false, // Show face up during animation
            isSelected: false,
          );
        } else {
          // Fallback to card back if no card data available
          cardWidget = CardWidget(
            card: CardModel(
              cardId: 'animated_card',
              rank: '?',
              suit: '?',
              points: 0,
            ),
            dimensions: cardSize,
            config: CardDisplayConfig.forDiscardPile(),
            showBack: true, // Show back if no data
            isSelected: false,
          );
        }
        
        // For moveCard, keep fully visible during movement
        // For other animations, use opacity based on animation value
        final opacity = animationType == AnimationType.moveCard ? 1.0 : animation.value;
        
        return Positioned(
          left: cardPosition.dx,
          top: cardPosition.dy,
          child: Opacity(
            opacity: opacity,
            child: cardWidget,
          ),
        );
      },
    );
  }
  
  /// Get RenderBox for draw pile widget
  RenderBox? getDrawPileRenderBox() {
    return _playScreenFunctions.getDrawPileRenderBox();
  }
  
  /// Get RenderBox for discard pile widget
  RenderBox? getDiscardPileRenderBox() {
    return _playScreenFunctions.getDiscardPileRenderBox();
  }
  
  /// Get PlayScreenFunctions instance for accessing additional functionality
  PlayScreenFunctions get playScreenFunctions => _playScreenFunctions;
  
  // ========== Opponents Panel Methods ==========

  /// Protect cardsToPeek data for 5 seconds
  void _protectCardsToPeek(List<dynamic> cardsToPeek) {
    _cardsToPeekProtectionTimer?.cancel();
    _isCardsToPeekProtected = true;
    _protectedCardsToPeek = List<dynamic>.from(cardsToPeek);
    _cardsToPeekProtectionTimer = Timer(Duration(seconds: 5), () {
      _clearCardsToPeekProtection();
    });
  }

  /// Clear cardsToPeek protection
  void _clearCardsToPeekProtection() {
    _isCardsToPeekProtected = false;
    _protectedCardsToPeek = null;
    _cardsToPeekProtectionTimer?.cancel();
    _cardsToPeekProtectionTimer = null;
    if (mounted) {
      setState(() {});
    }
  }

  /// Build the opponents panel widget
  Widget _buildOpponentsPanel() {
    final dutchGameState = _getPrevStateDutchGame();
    final opponentsPanel = dutchGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    final currentTurnIndex = opponentsPanel['currentTurnIndex'] ?? -1;
    final cardsToPeekFromState = dutchGameState['myCardsToPeek'] as List<dynamic>? ?? [];
    
    // Check if we need to protect cardsToPeek
    if (cardsToPeekFromState.isNotEmpty && !_isCardsToPeekProtected) {
      final hasFullCardData = cardsToPeekFromState.any((card) {
        if (card is Map<String, dynamic>) {
          return card.containsKey('suit') || card.containsKey('rank');
        }
        return false;
      });
      if (hasFullCardData) {
        _protectCardsToPeek(cardsToPeekFromState);
      }
    }
    
    final cardsToPeek = _isCardsToPeekProtected && _protectedCardsToPeek != null
        ? _protectedCardsToPeek!
        : cardsToPeekFromState;
    
    final otherPlayers = opponents;
    final isGameActive = dutchGameState['isGameActive'] ?? false;
    final playerStatus = dutchGameState['playerStatus']?.toString() ?? 'unknown';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opponents.isEmpty)
          _buildEmptyOpponents()
        else
          // Spread opponents evenly vertically using Expanded and Spacers
          Expanded(
            child: _buildOpponentsGrid(otherPlayers, cardsToPeek, currentTurnIndex, isGameActive, playerStatus),
          ),
      ],
    );
  }

  Widget _buildEmptyOpponents() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people,
              size: 24,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              'No other players',
              style: AppTextStyles.bodySmall().copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpponentsGrid(List<dynamic> opponents, List<dynamic> cardsToPeek, int currentTurnIndex, bool isGameActive, String playerStatus) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final dutchGameState = _getPrevStateDutchGame();
        final currentPlayerRaw = dutchGameState['currentPlayer'];
        Map<String, dynamic>? currentPlayerData;
        if (currentPlayerRaw == null || currentPlayerRaw == 'null' || currentPlayerRaw == '') {
          currentPlayerData = null;
        } else if (currentPlayerRaw is Map<String, dynamic>) {
          currentPlayerData = currentPlayerRaw;
        } else {
          currentPlayerData = null;
        }
        final currentPlayerId = currentPlayerData?['id']?.toString() ?? '';
        // Use current user's status for card glow (same source as status chip)
        final currentPlayerStatus = _getCurrentUserStatus();
        final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'waiting';
        final isInitialPeekPhase = gamePhase == 'initial_peek';
        
        // Get game state for timer configuration
        final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
        final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
        final gameData = games[currentGameId] as Map<String, dynamic>?;
        final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
        final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
        final phase = gameState?['phase'] as String?;
        // Safely convert Map<String, dynamic> to Map<String, int>
        final timerConfigRaw = gameState?['timerConfig'] as Map<String, dynamic>?;
        final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    
        // Order opponents: opp1 to column 1 (left), opp2 to middle column
        List<dynamic> reorderedOpponents = [];
        if (opponents.length >= 2) {
          reorderedOpponents = [
            opponents[0], // opp1 goes to column 1 (left)
            opponents[1], // opp2 goes to middle column
            if (opponents.length > 2) ...opponents.sublist(2), // opp3+ goes to right column
          ];
        } else {
          reorderedOpponents = opponents; // If less than 2 opponents, keep original order
        }
        
        // Create a map to find original index from player ID for currentTurnIndex calculation
        final originalIndexMap = <String, int>{};
        for (int i = 0; i < opponents.length; i++) {
          final player = opponents[i] as Map<String, dynamic>;
          final playerId = player['id']?.toString() ?? '';
          if (playerId.isNotEmpty) {
            originalIndexMap[playerId] = i;
          }
        }
    
        // Build list of opponent widgets with equal width columns
        final opponentWidgets = <Widget>[];
        final entries = reorderedOpponents.asMap().entries.toList();
        
        for (int i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final displayIndex = entry.key; // Position in UI (0=left, 1=middle, 2=right)
          final player = entry.value as Map<String, dynamic>;
          final playerId = player['id']?.toString() ?? '';
          // Use original index from opponents list for turn calculation
          final originalIndex = originalIndexMap[playerId] ?? displayIndex;
          final isCurrentTurn = originalIndex == currentTurnIndex;
          final isCurrentPlayer = playerId == currentPlayerId;
          final knownCards = player['known_cards'] as Map<String, dynamic>?;
          
          // Add opponent widget wrapped in Expanded for equal width
          // Add horizontal padding to both sides of each column
          opponentWidgets.add(
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppPadding.mediumPadding.left),
                child: _buildOpponentCard(
                  player, 
                  cardsToPeek, 
                  player['collection_rank_cards'] as List<dynamic>? ?? [],
                  isCurrentTurn, 
                  isGameActive, 
                  isCurrentPlayer, 
                  currentPlayerStatus,
                  knownCards,
                  isInitialPeekPhase,
                  phase, // Pass phase for timer calculation
                  timerConfig, // Pass timerConfig from game_state
                  opponentIndex: displayIndex, // Pass display index for alignment (0=left, 1=middle, 2=right)
                ),
              ),
            ),
          );
        }
        
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Expand columns to fill available height
          children: opponentWidgets,
        );
      },
    );
  }

  Widget _buildOpponentCard(Map<String, dynamic> player, List<dynamic> cardsToPeek, List<dynamic> playerCollectionRankCards, bool isCurrentTurn, bool isGameActive, bool isCurrentPlayer, String currentPlayerStatus, Map<String, dynamic>? knownCards, bool isInitialPeekPhase, String? phase, Map<String, int>? timerConfig, {required int opponentIndex}) {
    // Get player name - prefer full_name, fallback to name, then username, then default
    final fullName = player['full_name']?.toString();
    final playerNameRaw = player['name']?.toString();
    final username = player['username']?.toString();
    final playerName = (fullName != null && fullName.isNotEmpty) 
        ? fullName 
        : (playerNameRaw != null && playerNameRaw.isNotEmpty) 
            ? playerNameRaw 
            : (username != null && username.isNotEmpty) 
                ? username 
                : 'Unknown Player';
    final hand = player['hand'] as List<dynamic>? ?? [];
    final drawnCard = player['drawnCard'] as Map<String, dynamic>?;
    final hasCalledDutch = player['hasCalledDutch'] ?? false;
    final playerStatus = player['status']?.toString() ?? 'unknown';
    
    // For timer calculation, always use playerStatus (opponent's actual status)
    // currentPlayerStatus is the user's status (used for card glow), not the opponent's status
    // For timer, we need the opponent's actual status to get the correct duration
    final statusForTimer = playerStatus;
    
    // Calculate timer from game_state timerConfig (status is more specific than phase)
    int? effectiveTimer;
    
    // Check status first (more specific than phase for player actions)
    if (statusForTimer != null && statusForTimer.isNotEmpty) {
      switch (statusForTimer) {
        case 'initial_peek':
          effectiveTimer = timerConfig?['initial_peek'] ?? 15;
          break;
        case 'drawing_card':
          effectiveTimer = timerConfig?['drawing_card'] ?? 20;
          break;
        case 'playing_card':
          effectiveTimer = timerConfig?['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          effectiveTimer = timerConfig?['same_rank_window'] ?? 10;
          break;
        case 'queen_peek':
          effectiveTimer = timerConfig?['queen_peek'] ?? 15;
          break;
        case 'jack_swap':
          effectiveTimer = timerConfig?['jack_swap'] ?? 20;
          break;
        case 'peeking':
          effectiveTimer = timerConfig?['peeking'] ?? 10;
          break;
        case 'waiting':
          effectiveTimer = timerConfig?['waiting'] ?? 0;
          break;
        default:
          // If status doesn't match, fall through to phase check
          break;
      }
    }
    
    // If status didn't provide a timer (or status was null), check phase
    if (effectiveTimer == null && phase != null && phase.isNotEmpty) {
      switch (phase) {
        case 'initial_peek':
          effectiveTimer = timerConfig?['initial_peek'] ?? 15;
          break;
        case 'player_turn':
        case 'playing':
          // For generic player_turn/playing phase, status should have been checked above
          // But if status wasn't available, use playing_card as default
          effectiveTimer = timerConfig?['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          effectiveTimer = timerConfig?['same_rank_window'] ?? 10;
          break;
        case 'queen_peek_window':
          effectiveTimer = timerConfig?['queen_peek'] ?? 15;
          break;
        case 'special_play_window':
          effectiveTimer = timerConfig?['jack_swap'] ?? 20;
          break;
        default:
          effectiveTimer = timerConfig?['default'] ?? 30;
      }
    }
    
    // Final fallback if neither status nor phase provided a timer
    effectiveTimer ??= 30;
    
    // Ensure effectiveTimer is valid (not 0, not negative, not NaN) to prevent division by zero in timer widget
    if (effectiveTimer <= 0 || !effectiveTimer.isFinite) {
      effectiveTimer = 30; // Safe default
    }
    
    // Show timer when: player has any active status (drawing_card, playing_card, initial_peek, jack_swap, queen_peek, peeking)
    // Note: 'peeking' status occurs after a queen_peek decision is executed, but timer should continue showing
    // Use playerStatus (opponent's actual status) to determine if timer should show
    final shouldShowTimer = playerStatus == 'drawing_card' || 
         playerStatus == 'playing_card' || 
         playerStatus == 'initial_peek' ||
         playerStatus == 'jack_swap' || 
         playerStatus == 'queen_peek' || 
         playerStatus == 'peeking';
    
    // Use status chip color logic for glow (excludes 'waiting' and 'same_rank_window')
    final shouldShowGlow = _shouldHighlightCurrentPlayer(playerStatus);
    final statusChipColor = shouldShowGlow ? _getStatusChipColor(playerStatus) : null;
    
    // For timer color, always get the status chip color (including same_rank_window)
    final timerColor = _getStatusChipColor(playerStatus);
    
    // Background highlight logic (includes same_rank_window for current player)
    final shouldHighlightBackground = _shouldHighlightCurrentPlayer(playerStatus) 
        || (isCurrentPlayer && playerStatus == 'same_rank_window');
    
    // All opponents align left and wrap
    final Alignment cardAlignment = Alignment.centerLeft;
    final MainAxisAlignment nameAlignment = MainAxisAlignment.start;
    final CrossAxisAlignment columnAlignment = CrossAxisAlignment.start;
    
    // Vertical alignment: col 1 (index 0) and col 3+ (index 2+) start at 1/4 from top, col 2 (index 1) top
    final bool shouldStartAtOneFourth = (opponentIndex == 0 || opponentIndex >= 2);
    final MainAxisAlignment columnMainAlignment = MainAxisAlignment.start; // All columns align to start
    
    if (drawnCard != null) {
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate 1/4 of the opponents section height (from top to game board)
        final oneFourthHeight = constraints.maxHeight / 4;
        
        return Column(
          crossAxisAlignment: columnAlignment,
          mainAxisAlignment: columnMainAlignment,
          mainAxisSize: MainAxisSize.max, // Expand to fill available height
          children: [
            // Add spacer at top for columns 1 and 3 to position content at 1/4 from top
            if (shouldStartAtOneFourth) SizedBox(height: oneFourthHeight),
            // Top row: Profile pic and timer, aligned left
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Profile picture (circular, 1.5x status chip height)
                _buildPlayerProfilePicture(
                  player['id']?.toString() ?? '',
                  profilePictureUrl: player['profile_picture']?.toString(),
                ),
                const SizedBox(width: 8),
                if (hasCalledDutch) ...[
                  Icon(
                    Icons.flag,
                    size: 16,
                    color: AppColors.errorColor,
                  ),
                  const SizedBox(width: 4),
                ],
                if (isCurrentTurn && !isCurrentPlayer) ...[
                  Icon(
                    Icons.play_arrow,
                    size: 16,
                    color: AppColors.accentColor2,
                  ),
                  const SizedBox(width: 4),
                ],
                // Show circular timer when shouldShowTimer is true
                if (shouldShowTimer) ...[
                  const SizedBox(width: 6),
                  CircularTimerWidget(
                    key: ValueKey('timer_${player['id']}_${playerStatus}'), // Reset timer when player or status changes
                    durationSeconds: effectiveTimer ?? 30,
                    size: 28.0, // Match profile picture size
                    color: timerColor,
                    backgroundColor: AppColors.surfaceVariant,
                  ),
                ],
              ],
            ),
            
            // Second row: Username
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                // Use username if available, otherwise fallback to name
                // For comp players, name IS the username
                // For human players, name might be "Player_<sessionId>" if username not stored
                (username != null && username.isNotEmpty) 
                    ? username 
                    : (playerNameRaw != null && playerNameRaw.isNotEmpty) 
                        ? playerNameRaw 
                        : 'Unknown',
                style: AppTextStyles.label().copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                  // Add very prominent glow effect using status chip color logic (excludes 'waiting' and 'same_rank_window')
                  shadows: statusChipColor != null
                      ? [
                          Shadow(
                            color: statusChipColor,
                            blurRadius: 16,
                          ),
                          Shadow(
                            color: statusChipColor.withOpacity(0.9),
                            blurRadius: 24,
                          ),
                          Shadow(
                            color: statusChipColor.withOpacity(0.7),
                            blurRadius: 32,
                          ),
                          Shadow(
                            color: statusChipColor.withOpacity(0.5),
                            blurRadius: 40,
                          ),
                          Shadow(
                            color: statusChipColor.withOpacity(0.3),
                            blurRadius: 48,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
            
            // Bottom: Cards aligned left and wrap
            const SizedBox(height: 8),
            Align(
              alignment: cardAlignment,
              child: hand.isNotEmpty
                  ? _buildOpponentsCardsRow(hand, cardsToPeek, playerCollectionRankCards, drawnCard, player['id']?.toString() ?? '', knownCards, isInitialPeekPhase, player, nameAlignment: nameAlignment, currentPlayerStatus: currentPlayerStatus)
                  : _buildEmptyHand(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOpponentsCardsRow(List<dynamic> cards, List<dynamic> cardsToPeek, List<dynamic> playerCollectionRankCards, Map<String, dynamic>? drawnCard, String playerId, Map<String, dynamic>? knownCards, bool isInitialPeekPhase, Map<String, dynamic> player, {MainAxisAlignment? nameAlignment, String? currentPlayerStatus}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use available width (after column padding) for all calculations
        // constraints.maxWidth is already the available space after padding
        final availableWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : (MediaQuery.of(context).size.width > 0 ? MediaQuery.of(context).size.width * 0.5 : 500.0);
        // Ensure availableWidth is valid before calculations
        if (availableWidth <= 0 || !availableWidth.isFinite) {
          return const SizedBox.shrink();
        }
        // All card sizes are relative to available space (after padding), not total column width
        final cardWidth = CardDimensions.clampCardWidth(availableWidth * 0.22); // 22% of available width, clamped to max
        final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
        final cardDimensions = Size(cardWidth, cardHeight);
        final stackOffset = cardHeight * CardDimensions.STACK_OFFSET_PERCENTAGE;
        // Card padding is relative to available width (after column padding)
        final cardPadding = availableWidth * 0.02;
        
        final collectionRankCardIds = playerCollectionRankCards
            .where((c) => c is Map<String, dynamic>)
            .map((c) => (c as Map<String, dynamic>)['cardId']?.toString())
            .where((id) => id != null)
            .toSet();
        
        Map<String, Widget> collectionRankWidgets = {};
        
        for (int i = 0; i < cards.length; i++) {
          final card = cards[i];
          if (card == null) continue;
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          if (cardId == null) continue;
          final drawnCardId = drawnCard?['cardId']?.toString();
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          Map<String, dynamic>? peekedCardData;
          if (cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          Map<String, dynamic>? collectionRankCardData;
          if (playerCollectionRankCards.isNotEmpty) {
            for (var collectionCard in playerCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                break;
              }
            }
          }
          if (collectionRankCardData != null) {
            final cardDataToUse = isDrawnCard && drawnCard != null
                ? drawnCard 
                : (peekedCardData ?? collectionRankCardData);
            final cardKey = _getOrCreateCardKey('${playerId}_$i', 'opponent');
            final cardWidget = _buildOpponentCardWidget(cardDataToUse, isDrawnCard, playerId, false, cardDimensions, cardKey: cardKey);
            collectionRankWidgets[cardId] = cardWidget;
          }
        }
        
        // Build list of card widgets
        List<Widget> cardWidgets = [];
        
        for (int index = 0; index < cards.length; index++) {
          final card = cards[index];
          if (card == null) {
            final blankSlotKey = _getOrCreateCardKey('${playerId}_$index', 'opponent');
            cardWidgets.add(
              Padding(
                padding: EdgeInsets.only(right: cardPadding),
                child: Container(
                  key: blankSlotKey,
                  child: _buildBlankCardSlot(cardDimensions),
                ),
              ),
            );
            continue;
          }
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          final drawnCardId = drawnCard?['cardId']?.toString();
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          Map<String, dynamic>? peekedCardData;
          if (cardId != null && cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          Map<String, dynamic>? collectionRankCardData;
          bool isCollectionRankCard = false;
          if (cardId != null && playerCollectionRankCards.isNotEmpty) {
            for (var collectionCard in playerCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                isCollectionRankCard = true;
                break;
              }
            }
          }
          final cardDataToUse = isDrawnCard && drawnCard != null 
              ? drawnCard 
              : (peekedCardData ?? collectionRankCardData ?? cardMap);
          
          if (isCollectionRankCard && collectionRankWidgets.containsKey(cardId)) {
            bool isFirstCollectionCard = true;
            for (int i = 0; i < index; i++) {
              final prevCard = cards[i];
              if (prevCard != null && prevCard is Map<String, dynamic>) {
                final prevCardId = prevCard['cardId']?.toString();
                if (prevCardId != null && collectionRankCardIds.contains(prevCardId)) {
                  isFirstCollectionCard = false;
                  break;
                }
              }
            }
            if (isFirstCollectionCard) {
              List<Widget> orderedCollectionWidgets = [];
              for (var collectionCard in playerCollectionRankCards) {
                if (collectionCard is Map<String, dynamic>) {
                  final collectionCardId = collectionCard['cardId']?.toString();
                  if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                    orderedCollectionWidgets.add(collectionRankWidgets[collectionCardId]!);
                  }
                }
              }
              final cardWidth = cardDimensions.width;
              final cardHeight = cardDimensions.height;
              final stackHeight = cardHeight + (orderedCollectionWidgets.length - 1) * stackOffset;
              final stackWidget = SizedBox(
                width: cardWidth,
                height: stackHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: orderedCollectionWidgets.asMap().entries.map((entry) {
                    return Positioned(
                      left: 0,
                      top: entry.key * stackOffset,
                      child: entry.value,
                    );
                  }).toList(),
                ),
              );
              cardWidgets.add(
                Padding(
                  padding: EdgeInsets.only(right: cardPadding),
                  child: stackWidget,
                ),
              );
            }
            // Skip non-first collection cards (they're already in the stack)
            continue;
          }
          if (cardId == null) {
            continue;
          }
          final cardKey = _getOrCreateCardKey('${playerId}_$index', 'opponent');
          final cardWidget = _buildOpponentCardWidget(cardDataToUse, isDrawnCard, playerId, false, cardDimensions, cardKey: cardKey, currentPlayerStatus: currentPlayerStatus);
          cardWidgets.add(
            Padding(
              padding: EdgeInsets.only(
                right: cardPadding,
                left: isDrawnCard ? cardPadding * 2 : 0,
              ),
              child: cardWidget,
            ),
          );
        }
        
        // Add extra empty slot at the end with opacity 0 (for animation space)
        final extraSlotIndex = cards.length;
        final extraSlotKey = _getOrCreateCardKey('${playerId}_$extraSlotIndex', 'opponent');
        cardWidgets.add(
          Opacity(
            opacity: 0.0, // Always invisible but still takes up space
            child: Padding(
              padding: EdgeInsets.only(right: cardPadding),
              child: Container(
                key: extraSlotKey,
                child: _buildBlankCardSlot(cardDimensions),
              ),
            ),
          ),
        );
        
        // Use Wrap widget to allow cards to wrap to next line
        final wrapWidget = Wrap(
          spacing: 0, // Spacing is handled by card padding
          runSpacing: cardPadding, // Vertical spacing between wrapped rows
          children: cardWidgets,
        );
        
        // Update opponent card bounds after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Update bounds for ALL indices (including empty slots and extra slot)
          // All indices from 0 to cards.length should have bounds tracked (including extra slot)
          for (int i = 0; i <= cards.length; i++) {
            final keyString = '${playerId}_$i';
            final cardKey = _getOrCreateCardKey(keyString, 'opponent');
            _playScreenFunctions.updateOpponentCardBounds(playerId, i, cardKey, keyString: keyString);
          }
          // Clear bounds only for indices beyond the current list length + extra slot
          // maxIndex is cards.length to include the extra slot
          _playScreenFunctions.clearMissingOpponentCardBounds(
            playerId,
            List.generate(cards.length + 1, (i) => i), // All indices from 0 to length (including extra slot)
            maxIndex: cards.length, // Include extra slot at index cards.length
          );
        });
        
        return wrapWidget;
      },
    );
  }

  Widget _buildOpponentCardWidget(Map<String, dynamic> card, bool isDrawnCard, String playerId, bool isCollectionRankCard, Size cardDimensions, {GlobalKey? cardKey, String? currentPlayerStatus}) {
    final cardModel = CardModel.fromMap(card);
    final cardId = card['cardId']?.toString();
    final isSelected = cardId != null && _clickedCardId == cardId;
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    Widget cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions,
      config: CardDisplayConfig.forOpponent(),
      isSelected: isSelected,
      onTap: () => _handleOpponentCardClick(card, playerId),
    );
    
    // Apply glow effect based on current player status (for jack_swap and queen_peek)
    final glowColor = currentPlayerStatus != null 
        ? _getGlowColorForCards(currentPlayerStatus, false) 
        : null;
    
    if (glowColor != null && _glowAnimation != null) {
      return AnimatedBuilder(
        animation: _glowAnimation!,
        builder: (context, child) {
          final glowOpacity = _glowAnimation!.value;
          final glowDecoration = _buildGlowDecoration(glowColor, glowOpacity);
          return Container(
            decoration: glowDecoration,
            child: cardWidget,
          );
        },
      );
    }
    
    return cardWidget;
  }

  Widget _buildEmptyHand() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 20,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              'No cards',
              style: AppTextStyles.overline().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlankCardSlot([Size? cardDimensions]) {
    final dimensions = cardDimensions ?? CardDimensions.getUnifiedDimensions();
    final cardBackColor = HSLColor.fromColor(AppColors.primaryColor)
        .withSaturation(0.2)
        .toColor();
    // Use dynamic border radius from SSOT to match card widgets
    final borderRadius = CardDimensions.calculateBorderRadius(dimensions);
    return SizedBox(
      width: dimensions.width,
      height: dimensions.height,
      child: Container(
        decoration: BoxDecoration(
          color: cardBackColor,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: AppColors.borderDefault,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
      ),
    );
  }

  String? getClickedCardId() {
    return _clickedCardId;
  }

  void clearClickedCardId() {
    setState(() {
      _clickedCardId = null;
    });
  }

  void _handleOpponentCardClick(Map<String, dynamic> card, String cardOwnerId) async {
    final dutchGameState = _getPrevStateDutchGame();
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final currentPlayerStatus = _getCurrentUserStatus();
    
    if (currentPlayerStatus == 'jack_swap') {
      if (LOGGING_SWITCH) {
        _logger.info('🃏 OpponentsPanelWidget: Status is jack_swap - opponent cards are interactive');
      }
    }
    if (currentPlayerStatus == 'queen_peek' || currentPlayerStatus == 'jack_swap') {
      final cardId = card['cardId']?.toString();
      if (cardId != null) {
        setState(() {
          _clickedCardId = cardId;
        });
        
        if (currentPlayerStatus == 'queen_peek') {
          try {
            final queenPeekAction = PlayerAction.queenPeek(
              gameId: currentGameId,
              cardId: cardId,
              ownerId: cardOwnerId,
            );
            await queenPeekAction.execute();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Peeking at: ${card['rank']} of ${card['suit']}'
                ),
                  backgroundColor: AppColors.accentColor2,
                duration: Duration(seconds: 2),
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to peek at card: $e'),
                backgroundColor: AppColors.errorColor,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (currentPlayerStatus == 'jack_swap') {
          try {
            if (LOGGING_SWITCH) {
              _logger.info('🃏 OpponentsPanelWidget: Card tapped during jack_swap - Card: $cardId, Player: $cardOwnerId, Game: $currentGameId');
            }
            if (LOGGING_SWITCH) {
              _logger.info('🃏 OpponentsPanelWidget: Current jack swap selection count: ${PlayerAction.getJackSwapSelectionCount()}');
            }
            await PlayerAction.selectCardForJackSwap(
              cardId: cardId,
              playerId: cardOwnerId,
              gameId: currentGameId,
            );
            final selectionCount = PlayerAction.getJackSwapSelectionCount();
            if (LOGGING_SWITCH) {
              _logger.info('🃏 OpponentsPanelWidget: After selection, jack swap count: $selectionCount');
            }
            if (selectionCount == 1) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'First card selected: ${card['rank']} of ${card['suit']}. Select another card to swap.'
                  ),
                  backgroundColor: AppColors.warningColor,
                  duration: Duration(seconds: 2),
                ),
              );
            } else if (selectionCount == 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Second card selected: ${card['rank']} of ${card['suit']}. Swapping cards...'
                  ),
                  backgroundColor: AppColors.accentColor,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to select card for Jack swap: $e'),
                backgroundColor: AppColors.errorColor,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error: Card information incomplete'),
            backgroundColor: AppColors.errorColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with cards while status is "$currentPlayerStatus"'
          ),
          backgroundColor: AppColors.warningColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Color _getStatusChipColor(String status) {
    switch (status) {
      case 'waiting':
        return AppColors.statusWaiting;
      case 'ready':
        return AppColors.statusReady;
      case 'drawing_card':
        return AppColors.statusDrawing;
      case 'playing_card':
        return AppColors.statusPlaying;
      case 'same_rank_window':
        return AppColors.statusSameRank;
      case 'queen_peek':
        return AppColors.statusQueenPeek;
      case 'jack_swap':
        return AppColors.statusJackSwap;
      case 'peeking':
        return AppColors.statusPeeking;
      case 'initial_peek':
        return AppColors.statusInitialPeek;
      case 'winner':
        return AppColors.statusWinner;
      case 'finished':
        return AppColors.statusFinished;
      case 'disconnected':
        return AppColors.errorColor;
      default:
        return AppColors.textSecondary;
    }
  }

  /// Reusable glow effect decoration builder
  /// Returns a BoxDecoration with animated glow effect based on status color
  /// [statusColor] The color to use for the glow (from _getStatusChipColor)
  /// [glowOpacity] The current animation opacity value (from _glowAnimation)
  /// Returns null if glow should not be applied
  BoxDecoration? _buildGlowDecoration(Color statusColor, double glowOpacity) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(
          color: statusColor.withValues(alpha: 0.6 * glowOpacity),
          blurRadius: 6,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: statusColor.withValues(alpha: 0.4 * glowOpacity),
          blurRadius: 10,
          spreadRadius: 2,
        ),
        BoxShadow(
          color: statusColor.withValues(alpha: 0.2 * glowOpacity),
          blurRadius: 14,
          spreadRadius: 3,
        ),
      ],
    );
  }

  /// Determine if glow should be applied to cards based on current status
  /// [currentPlayerStatus] The current player's status
  /// [isMyHand] Whether this is for my hand (true) or opponent hand (false)
  /// Returns the status color if glow should be applied, null otherwise
  Color? _getGlowColorForCards(String currentPlayerStatus, bool isMyHand) {
    switch (currentPlayerStatus) {
      case 'playing_card':
        // During playing: apply to all cards in my hand
        return isMyHand ? _getStatusChipColor(currentPlayerStatus) : null;
      case 'jack_swap':
      case 'queen_peek':
        // During jack swap/queen peek: apply to all cards in all hands
        return _getStatusChipColor(currentPlayerStatus);
      case 'initial_peek':
      case 'same_rank_window':
        // During initial peek/same rank: apply to my hand only
        return isMyHand ? _getStatusChipColor(currentPlayerStatus) : null;
      default:
        return null;
    }
  }

  bool _shouldHighlightCurrentPlayer(String status) {
    if (status == 'waiting' || status == 'same_rank_window') {
      return false;
    }
    return true;
  }

  // ========== Game Board Methods ==========

  Widget _buildGameBoard() {
    // Update game board height in state after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateGameBoardHeight();
    });
    
    return Container(
      key: _gameBoardKey,
      padding: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Get the actual width of the gameboard row
          final gameboardRowWidth = constraints.maxWidth;
          
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDrawPile(),
              _buildMatchPot(gameboardRowWidth), // Match pot in the middle
              _buildDiscardPile(),
            ],
          );
        },
      ),
    );
  }
  
  /// Update game board height in StateManager (for overlay positioning)
  void _updateGameBoardHeight() {
    if (_gameBoardKey.currentContext != null) {
      final RenderBox renderBox = _gameBoardKey.currentContext!.findRenderObject() as RenderBox;
      final height = renderBox.size.height;
      final stateManager = StateManager();
      final currentGameBoardHeight = stateManager.getModuleState<Map<String, dynamic>>('dutch_game')?['gameBoardHeight'] as double?;
      
      if (currentGameBoardHeight == null || currentGameBoardHeight != height) {
        stateManager.updateModuleState('dutch_game', {
          'gameBoardHeight': height,
        });
      }
    }
  }

  // ========== Draw Pile Methods ==========

  Widget _buildDrawPile() {
    final dutchGameState = _getPrevStateDutchGame();
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get full draw pile list
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    
    // Check if player is in drawing status (similar to myHand logic)
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    final playerStatus = myHand['playerStatus']?.toString() ?? 'unknown';
    final isDrawingStatus = playerStatus == 'drawing_card';
    final statusChipColor = isDrawingStatus ? _getStatusChipColor(playerStatus) : null;
    
    return Container(
      key: _drawPileKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final cardDimensions = CardDimensions.getUnifiedDimensions();
                
                Widget drawPileContent;
              
              if (drawPile.isEmpty) {
                // Empty draw pile - render placeholder
                final emptyKey = _getOrCreateCardKey('draw_pile_empty', 'draw_pile');
                drawPileContent = CardWidget(
                  key: emptyKey,
                  card: CardModel(
                    cardId: 'draw_pile_empty',
                    rank: '?',
                    suit: '?',
                    points: 0,
                  ),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forDrawPile(),
                  showBack: true,
                  onTap: _handleDrawPileClick,
                );
              } else {
                // Render all cards in draw pile with stacking effect
                // Only the top card is visible and clickable, but all are tracked for animation
                final topCardIndex = drawPile.length - 1;
                final topCardData = drawPile[topCardIndex] as Map<String, dynamic>? ?? {};
                
                // Create stacking effect with 2 additional cards behind
                final stackCards = <Widget>[];
                
                // Add 2 background cards with rotation and offset for stacking effect
                for (int i = 0; i < 2; i++) {
                  // Draw pile: 2° and 4° anticlockwise
                  final rotation = -(i + 1) * 2.0; // -2° and -4° (anticlockwise)
                  final offset = (i + 1) * 1.5; // 1.5px and 3px offset
                  // Add shadow to the last (bottom) card of the stack
                  final isBottomCard = i == 1; // Second card is the bottom one
                  stackCards.add(
                    Positioned.fill(
                      child: Transform.rotate(
                        angle: rotation * 3.14159 / 180, // Convert to radians
                        child: Transform.translate(
                          offset: Offset(offset, -offset),
                          child: isBottomCard
                              ? Container(
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Opacity(
                                    opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                    child: CardWidget(
                                      card: CardModel.fromMap(topCardData),
                                      dimensions: cardDimensions,
                                      config: CardDisplayConfig.forDrawPile(),
                                      showBack: true,
                                      onTap: null, // Background cards not clickable
                                    ),
                                  ),
                                )
                              : Opacity(
                                  opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                  child: CardWidget(
                                    card: CardModel.fromMap(topCardData),
                                    dimensions: cardDimensions,
                                    config: CardDisplayConfig.forDrawPile(),
                                    showBack: true,
                                    onTap: null, // Background cards not clickable
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                }
                
                // Add all actual cards in the pile (for animation tracking)
                // Show top 5 cards (or all if less than 5) with opacity 1.0 for tracking
                final minVisibleCards = 5;
                final visibleCount = drawPile.length < minVisibleCards ? drawPile.length : minVisibleCards;
                final topVisibleIndex = drawPile.length - visibleCount;
                
                for (final entry in drawPile.asMap().entries) {
                  final index = entry.key;
                  final cardData = entry.value as Map<String, dynamic>? ?? {};
                  final cardId = cardData['cardId']?.toString() ?? 'draw_pile_empty';
                  final cardKey = _getOrCreateCardKey(cardId, 'draw_pile');
                  final isTopCard = index == topCardIndex;
                  final isVisible = index >= topVisibleIndex; // Top 5 cards (or all if less than 5)
                  
                  stackCards.add(
                    Positioned.fill(
                      child: Opacity(
                        opacity: isVisible ? 1.0 : 0.0, // Top 5 cards visible for tracking
                        child: CardWidget(
                          key: cardKey,
                          card: CardModel.fromMap(cardData),
                          dimensions: cardDimensions,
                          config: CardDisplayConfig.forDrawPile(),
                          showBack: true,
                          onTap: isTopCard ? _handleDrawPileClick : null, // Only top card clickable
                        ),
                      ),
                    ),
                  );
                }
                
                drawPileContent = SizedBox(
                  width: cardDimensions.width,
                  height: cardDimensions.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: stackCards,
                  ),
                );
              }
              
              // Wrap with animated glow effect when in drawing status
              if (isDrawingStatus && statusChipColor != null && _glowAnimation != null) {
                return AnimatedBuilder(
                  animation: _glowAnimation!,
                  builder: (context, child) {
                    final glowOpacity = _glowAnimation!.value;
                    final glowDecoration = _buildGlowDecoration(statusChipColor, glowOpacity);
                    return Container(
                      decoration: glowDecoration,
                      child: drawPileContent,
                    );
                  },
                );
              }
              
              return drawPileContent;
            },
          ),
        ],
      ),
      ),
    );
  }

  String? getClickedPileType() {
    return _clickedPileType;
  }

  void clearClickedPileType() {
    setState(() {
      _clickedPileType = null;
    });
  }

  void _handleDrawPileClick() async {
    final dutchGameState = _getPrevStateDutchGame();
    final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = centerBoard['playerStatus']?.toString() ?? 'unknown';
    
    if (currentPlayerStatus == 'drawing_card') {
      try {
        final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
        if (currentGameId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Error: No active game found'),
              backgroundColor: AppColors.errorColor,
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }
        final drawAction = PlayerAction.playerDraw(
          pileType: 'draw_pile',
          gameId: currentGameId,
        );
        await drawAction.execute();
        setState(() {
          _clickedPileType = 'draw_pile';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Card drawn from draw pile'),
            backgroundColor: AppColors.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to draw card: $e'),
            backgroundColor: AppColors.errorColor,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with draw pile while status is "$currentPlayerStatus"'
          ),
          backgroundColor: AppColors.warningColor,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // ========== Discard Pile Methods ==========

  Widget _buildDiscardPile() {
    final dutchGameState = _getPrevStateDutchGame();
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    
    // Get full discard pile list
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    final hasCards = discardPile.isNotEmpty;
    
    return Container(
      key: _discardPileKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final cardDimensions = CardDimensions.getUnifiedDimensions();
                
                if (!hasCards) {
                // Empty discard pile
                final emptyKey = _getOrCreateCardKey('discard_pile_empty', 'discard_pile');
                return CardWidget(
                  key: emptyKey,
                  card: CardModel(
                    cardId: 'discard_pile_empty',
                    rank: '?',
                    suit: '?',
                    points: 0,
                  ),
                  dimensions: cardDimensions,
                  config: CardDisplayConfig.forDiscardPile(),
                  showBack: true,
                  onTap: _handleDiscardPileClick,
                );
              }
              
              // Render all cards in discard pile with stacking effect
              // Only the top card is visible and clickable, but all are tracked for animation
              final topCardIndex = discardPile.length - 1;
              final topCardData = discardPile[topCardIndex] as Map<String, dynamic>? ?? {};
              
              // Create stacking effect with 2 additional cards behind
              final stackCards = <Widget>[];
              
              // Add 2 background cards with rotation and offset for stacking effect
              for (int i = 0; i < 2; i++) {
                // Discard pile: 2° and 4° clockwise
                final rotation = (i + 1) * 2.0; // 2° and 4° (clockwise)
                final offset = (i + 1) * 1.5; // 1.5px and 3px offset
                // Add shadow to the last (bottom) card of the stack
                final isBottomCard = i == 1; // Second card is the bottom one
                stackCards.add(
                  Positioned.fill(
                    child: Transform.rotate(
                      angle: rotation * 3.14159 / 180, // Convert to radians
                      child: Transform.translate(
                        offset: Offset(-offset, -offset), // Negative X for discard pile
                        child: isBottomCard
                            ? Container(
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Opacity(
                                  opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                  child: CardWidget(
                                    card: CardModel.fromMap(topCardData),
                                    dimensions: cardDimensions,
                                    config: CardDisplayConfig.forDiscardPile(),
                                    onTap: null, // Background cards not clickable
                                  ),
                                ),
                              )
                            : Opacity(
                                opacity: 0.6 - (i * 0.2), // Fade effect: 0.6, 0.4
                                child: CardWidget(
                                  card: CardModel.fromMap(topCardData),
                                  dimensions: cardDimensions,
                                  config: CardDisplayConfig.forDiscardPile(),
                                  onTap: null, // Background cards not clickable
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              }
              
              // Add all actual cards in the pile (for animation tracking)
              // Show top 5 cards (or all if less than 5) with opacity 1.0 for tracking
              final minVisibleCards = 5;
              final visibleCount = discardPile.length < minVisibleCards ? discardPile.length : minVisibleCards;
              final topVisibleIndex = discardPile.length - visibleCount;
              
              for (final entry in discardPile.asMap().entries) {
                final index = entry.key;
                final cardData = entry.value as Map<String, dynamic>? ?? {};
                final cardId = cardData['cardId']?.toString() ?? 'discard_pile_empty';
                final cardKey = _getOrCreateCardKey(cardId, 'discard_pile');
                final isTopCard = index == topCardIndex;
                final isVisible = index >= topVisibleIndex; // Top 5 cards (or all if less than 5)
                
                stackCards.add(
                  Positioned.fill(
                    child: Opacity(
                      opacity: isVisible ? 1.0 : 0.0, // Top 5 cards visible for tracking
                      child: CardWidget(
                        key: cardKey,
                        card: CardModel.fromMap(cardData),
                        dimensions: cardDimensions,
                        config: CardDisplayConfig.forDiscardPile(),
                        onTap: isTopCard ? _handleDiscardPileClick : null, // Only top card clickable
                      ),
                    ),
                  ),
                );
              }
              
              return SizedBox(
                width: cardDimensions.width,
                height: cardDimensions.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: stackCards,
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }

  void _handleDiscardPileClick() async {
    final dutchGameState = _getPrevStateDutchGame();
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'unknown';
    final gameState = dutchGameState['gameState'] as Map<String, dynamic>? ?? {};
    final isClearAndCollect = gameState['isClearAndCollect'] as bool? ?? true; // Default to true for backward compatibility
    
    // Block during same_rank_window and initial_peek phases - but only if collection mode is enabled
    if ((gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') && isClearAndCollect) {
      String reason = gamePhase == 'same_rank_window' 
        ? 'Cannot collect cards during same rank window'
        : 'Cannot collect cards during initial peek phase';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: AppColors.warningColor,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // If collection is disabled (isClearAndCollect: false), silently ignore clicks during same_rank_window
    if ((gamePhase == 'same_rank_window' || gamePhase == 'initial_peek') && !isClearAndCollect) {
      return; // Silently ignore - collection is disabled in this game mode
    }
    
    try {
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      if (currentGameId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error: No active game found'),
            backgroundColor: AppColors.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      final collectAction = PlayerAction.collectFromDiscard(gameId: currentGameId);
      await collectAction.execute();
      setState(() {
        _clickedPileType = 'discard_pile';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to collect card: $e'),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ========== Match Pot Methods ==========

  Widget _buildMatchPot(double gameboardRowWidth) {
    final dutchGameState = _getPrevStateDutchGame();
    final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final matchPot = centerBoard['matchPot'] as int? ?? 0;
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'waiting';
    final isGameActive = dutchGameState['isGameActive'] ?? false;
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    
    // Check if this is a practice game (practice games start with 'practice_room_')
    final isPracticeGame = currentGameId.startsWith('practice_room_');
    
    // Only show match pot if not a practice game
    if (isPracticeGame) {
      return const SizedBox.shrink();
    }
    
    final shouldShowPot = isGameActive && gamePhase != 'waiting';
    
    // Calculate width: 20% of gameboard row width
    final calculatedWidth = gameboardRowWidth * 0.2;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Win',
            style: AppTextStyles.headingSmall().copyWith(
              color: shouldShowPot 
                  ? AppColors.primaryColor
                  : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/images/coins.png',
                width: calculatedWidth,
                fit: BoxFit.contain,
              ),
              Text(
                shouldShowPot ? matchPot.toString() : '—',
                style: AppTextStyles.headingLarge().copyWith(
                  color: AppColors.black,
                  shadows: [
                    Shadow(
                      offset: Offset.zero,
                      blurRadius: 4.0,
                      color: AppColors.white,
                    ),
                    Shadow(
                      offset: Offset.zero,
                      blurRadius: 8.0,
                      color: AppColors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========== My Hand Methods ==========

  /// Protect cardsToPeek data for 5 seconds (My Hand)
  void _protectMyHandCardsToPeek(List<dynamic> cardsToPeek) {
    _myHandCardsToPeekProtectionTimer?.cancel();
    _isMyHandCardsToPeekProtected = true;
    _protectedMyHandCardsToPeek = List<dynamic>.from(cardsToPeek);
    _myHandCardsToPeekProtectionTimer = Timer(Duration(seconds: 5), () {
      _clearMyHandCardsToPeekProtection();
    });
  }

  /// Clear cardsToPeek protection (My Hand)
  void _clearMyHandCardsToPeekProtection() {
    _isMyHandCardsToPeekProtected = false;
    _protectedMyHandCardsToPeek = null;
    _myHandCardsToPeekProtectionTimer?.cancel();
    _myHandCardsToPeekProtectionTimer = null;
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildMyHand() {
    final dutchGameState = _getPrevStateDutchGame();
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    final cards = myHand['cards'] as List<dynamic>? ?? [];
    final selectedIndex = myHand['selectedIndex'] ?? -1;
    final cardsToPeekFromState = dutchGameState['myCardsToPeek'] as List<dynamic>? ?? [];
    final protectedCardsToPeek = dutchGameState['protectedCardsToPeek'] as List<dynamic>?;
    
    // CRITICAL: Also check games map directly (SSOT) for cardsToPeek
    // This ensures we catch the cleared state even if myCardsToPeek hasn't updated yet
    final currentGameIdForPeek = dutchGameState['currentGameId']?.toString() ?? '';
    final gamesForPeek = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGameForPeek = gamesForPeek[currentGameIdForPeek] as Map<String, dynamic>? ?? {};
    final gameDataForPeek = currentGameForPeek['gameData'] as Map<String, dynamic>? ?? {};
    final gameStateForPeek = gameDataForPeek['game_state'] as Map<String, dynamic>? ?? {};
    final playersForPeek = gameStateForPeek['players'] as List<dynamic>? ?? [];
    
    // Get current user ID
    final loginStateForPeek = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserIdForPeek = loginStateForPeek['userId']?.toString() ?? '';
    
    // Find current user's player data in game state (SSOT)
    final myPlayerInGameState = playersForPeek.firstWhere(
      (p) => p is Map<String, dynamic> && p['id']?.toString() == currentUserIdForPeek,
      orElse: () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    
    final cardsToPeekFromGameState = myPlayerInGameState['cardsToPeek'] as List<dynamic>? ?? [];
    
    // CRITICAL: Clear protection if EITHER myCardsToPeek OR game state cardsToPeek is empty
    // This ensures cards don't remain visible after the 8-second timer clears them
    // Must defer setState() until after build completes
    final isCardsToPeekEmpty = cardsToPeekFromState.isEmpty && cardsToPeekFromGameState.isEmpty;
    if (isCardsToPeekEmpty && _isMyHandCardsToPeekProtected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Re-check state in callback to avoid race conditions
        final updatedState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final updatedCardsToPeek = updatedState['myCardsToPeek'] as List<dynamic>? ?? [];
        if (mounted && updatedCardsToPeek.isEmpty && _isMyHandCardsToPeekProtected) {
          _clearMyHandCardsToPeekProtection();
        }
      });
    }
    
    // Use widget-level timer instead of timestamp from state
    // When protectedCardsToPeek is set, start the 5-second protection timer
    if (protectedCardsToPeek != null && !_isMyHandCardsToPeekProtected) {
      _protectMyHandCardsToPeek(protectedCardsToPeek);
    }
    
    // Only protect if cardsToPeek is not empty (check both sources)
    if (!isCardsToPeekEmpty && !_isMyHandCardsToPeekProtected) {
      final cardsToCheck = cardsToPeekFromState.isNotEmpty ? cardsToPeekFromState : cardsToPeekFromGameState;
      final hasFullCardData = cardsToCheck.any((card) {
        if (card is Map<String, dynamic>) {
          final hasSuit = card.containsKey('suit') && card['suit'] != '?' && card['suit'] != null;
          final hasRank = card.containsKey('rank') && card['rank'] != '?' && card['rank'] != null;
          return hasSuit || hasRank;
        }
        return false;
      });
      if (hasFullCardData) {
        _protectMyHandCardsToPeek(cardsToCheck);
      }
    }
    
    // Use protected cards if available, otherwise use state (prioritize state over game state)
    final cardsToPeek = _isMyHandCardsToPeekProtected && _protectedMyHandCardsToPeek != null
        ? _protectedMyHandCardsToPeek!
        : (cardsToPeekFromState.isNotEmpty ? cardsToPeekFromState : cardsToPeekFromGameState);
    
    final isGameActive = dutchGameState['isGameActive'] ?? false;
    final isMyTurn = dutchGameState['isMyTurn'] ?? false;
    final playerStatus = _getCurrentUserStatus(); // Use same source as status chip
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final finalRoundActive = gameState['finalRoundActive'] as bool? ?? false;
    final finalRoundCalledBy = gameState['finalRoundCalledBy']?.toString();
    // Get timer from game_state timerConfig (added during game initialization)
    // Safely convert Map<String, dynamic> to Map<String, int>
    final timerConfigRaw = gameState['timerConfig'] as Map<String, dynamic>?;
    final timerConfig = timerConfigRaw?.map((key, value) => MapEntry(key, value is int ? value : (value as num?)?.toInt() ?? 30)) ?? <String, int>{};
    final phase = gameState['phase'] as String?;
    // Calculate timer based on phase or status using timerConfig from game_state
    // Priority: Status is more specific than phase, so check status first
    int? turnTimeLimit;
    
    // Check status first (more specific than phase for player actions)
    if (playerStatus != null && playerStatus.isNotEmpty) {
      switch (playerStatus) {
        case 'initial_peek':
          turnTimeLimit = timerConfig['initial_peek'] ?? 15;
          break;
        case 'drawing_card':
          turnTimeLimit = timerConfig['drawing_card'] ?? 20;
          break;
        case 'playing_card':
          turnTimeLimit = timerConfig['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          turnTimeLimit = timerConfig['same_rank_window'] ?? 10;
          break;
        case 'queen_peek':
          turnTimeLimit = timerConfig['queen_peek'] ?? 15;
          break;
        case 'jack_swap':
          turnTimeLimit = timerConfig['jack_swap'] ?? 20;
          break;
        case 'peeking':
          turnTimeLimit = timerConfig['peeking'] ?? 10;
          break;
        case 'waiting':
          turnTimeLimit = timerConfig['waiting'] ?? 0;
          break;
        default:
          // If status doesn't match, fall through to phase check
          break;
      }
    }
    
    // If status didn't provide a timer (or status was null), check phase
    if (turnTimeLimit == null && phase != null && phase.isNotEmpty) {
      switch (phase) {
        case 'initial_peek':
          turnTimeLimit = timerConfig['initial_peek'] ?? 15;
          break;
        case 'player_turn':
        case 'playing':
          // For generic player_turn/playing phase, status should have been checked above
          // But if status wasn't available, use playing_card as default
          turnTimeLimit = timerConfig['playing_card'] ?? 30;
          break;
        case 'same_rank_window':
          turnTimeLimit = timerConfig['same_rank_window'] ?? 10;
          break;
        case 'queen_peek_window':
          turnTimeLimit = timerConfig['queen_peek'] ?? 15;
          break;
        case 'special_play_window':
          turnTimeLimit = timerConfig['jack_swap'] ?? 20;
          break;
        default:
          turnTimeLimit = timerConfig['default'] ?? 30;
      }
    }
    
    // Final fallback if neither status nor phase provided a timer
    turnTimeLimit ??= 30;
    
    // Ensure turnTimeLimit is valid (not 0, not negative, not NaN) to prevent division by zero in timer widget
    if (turnTimeLimit <= 0 || !turnTimeLimit.isFinite) {
      turnTimeLimit = 30; // Safe default
    }
    
    // Use DutchEventHandlerCallbacks.getCurrentUserId() to get sessionId (not userId)
    // This matches how players are identified in game_state (by sessionId)
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
    
    // Get current user's player data from game_state to retrieve profile picture
    // Profile picture is fetched when player joins and stored in player['profile_picture']
    final players = gameState['players'] as List<dynamic>? ?? [];
    Map<String, dynamic>? currentUserPlayer;
    try {
      currentUserPlayer = players.cast<Map<String, dynamic>>().firstWhere(
        (p) => p['id']?.toString() == currentUserId,
      );
    } catch (e) {
      // Player not found, will use fallback to StateManager
      currentUserPlayer = null;
    }
    final currentUserProfilePicture = currentUserPlayer?['profile_picture']?.toString();
    
    final hasPlayerCalledFinalRound = gameState['players'] != null
        ? (gameState['players'] as List<dynamic>?)
            ?.any((p) => p is Map<String, dynamic> && 
                p['id']?.toString() == currentUserId && 
                p['hasCalledFinalRound'] == true) ?? false
        : false;
    
    final actionError = dutchGameState['actionError'] as Map<String, dynamic>?;
    if (actionError != null) {
      final message = actionError['message']?.toString() ?? 'Action failed';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.warningColor,
            duration: const Duration(seconds: 3),
          ),
        );
        final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        StateManager().updateModuleState('dutch_game', {
          ...currentState,
          'actionError': null,
        });
      });
    }
    
    // Reset selectedIndex when status changes from jack_swap to waiting (timer expired)
    if (_previousPlayerStatus == 'jack_swap' && playerStatus == 'waiting') {
      if (LOGGING_SWITCH) {
        _logger.info('🃏 UnifiedGameBoardWidget: Status changed from jack_swap to waiting - resetting selectedIndex');
      }
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGames = Map<String, dynamic>.from(currentState['games'] as Map<String, dynamic>? ?? {});
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      if (currentGameId.isNotEmpty && currentGames.containsKey(currentGameId)) {
        final currentGame = Map<String, dynamic>.from(currentGames[currentGameId]);
        currentGame['selectedCardIndex'] = -1;
        currentGames[currentGameId] = currentGame;
        // Also reset in myHand slice
        final myHand = Map<String, dynamic>.from(currentState['myHand'] as Map<String, dynamic>? ?? {});
        myHand['selectedIndex'] = -1;
        // Update both in a single state update
        StateManager().updateModuleState('dutch_game', {
          ...currentState,
          'games': currentGames,
          'myHand': myHand,
        });
      }
      // Also clear jack swap selections in PlayerAction
      PlayerAction.resetJackSwapSelections();
    }
    
    // Update previous status for next check
    _previousPlayerStatus = playerStatus;
    
    if (playerStatus != 'initial_peek' && _initialPeekSelectionCount > 0) {
      _initialPeekSelectionCount = 0;
      _initialPeekSelectedCardIds.clear();
    }
    
    // For timer color, always get the status chip color (including same_rank_window)
    final timerColor = _getStatusChipColor(playerStatus);
    
    // Note: My hand height tracking removed - now tracking individual cards
    
    return Container(
      child: Padding(
        padding: const EdgeInsets.all(1.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Profile picture (circular, 1.5x status chip height)
                // Get profile picture from game_state player data first, then fallback to StateManager
                _buildPlayerProfilePicture(
                  _getCurrentUserId(),
                  profilePictureUrl: currentUserProfilePicture,
                ),
                const SizedBox(width: 8),
                Text(
                  'You',
                  style: AppTextStyles.headingSmall(),
                ),
                const Spacer(),
                if (isGameActive && isMyTurn && playerStatus == 'playing_card' && !finalRoundActive && !hasPlayerCalledFinalRound) ...[
                  GestureDetector(
                    onTap: () => _handleCallFinalRound(context, currentGameId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warningColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag,
                            size: 12,
                            color: AppColors.textOnAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Call Final Round',
                            style: AppTextStyles.bodySmall().copyWith(
                              color: AppColors.textOnAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (finalRoundActive) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warningColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          finalRoundCalledBy == _getCurrentUserId() 
                              ? Icons.flag 
                              : Icons.flag_outlined,
                          size: 12,
                          color: AppColors.textOnAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          finalRoundCalledBy == _getCurrentUserId()
                              ? 'You Called Final Round'
                              : 'Final Round Active',
                          style: AppTextStyles.bodySmall().copyWith(
                            color: AppColors.textOnAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (playerStatus != 'unknown')
                  PlayerStatusChip(
                    playerId: _getCurrentUserId(),
                    size: PlayerStatusChipSize.small,
                  ),
                // Show circular timer next to status chip (right side) when status is not 'waiting'
                // Note: 'jack_swap' and 'queen_peek' can occur out of turn and should show timer
                // Also show timer during 'same_rank_window' for my hand section
                if (playerStatus != 'waiting') ...[
                  const SizedBox(width: 6),
                  CircularTimerWidget(
                    key: ValueKey('timer_myhand_${playerStatus}'), // Reset timer when status changes
                    durationSeconds: turnTimeLimit,
                    size: 28.0, // Match profile picture size
                    color: timerColor,
                    backgroundColor: AppColors.surfaceVariant,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (cards.isEmpty)
              _buildMyHandEmptyHand()
            else
              _buildMyHandCardsGrid(cards, cardsToPeek, selectedIndex),
          ],
        ),
      ),
    );
  }

  Widget _buildMyHandEmptyHand() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style,
              size: 32,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              'No cards in hand',
              style: AppTextStyles.label().copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyHandCardsGrid(List<dynamic> cards, List<dynamic> cardsToPeek, int selectedIndex) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final containerWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : (MediaQuery.of(context).size.width > 0 ? MediaQuery.of(context).size.width * 0.5 : 500.0);
            // Ensure containerWidth is valid before calculations
            if (containerWidth <= 0 || !containerWidth.isFinite) {
              return const SizedBox.shrink();
            }
            
            final dutchGameState = _getPrevStateDutchGame();
            final currentPlayerStatus = _getCurrentUserStatus();
            final drawnCard = dutchGameState['myDrawnCard'] as Map<String, dynamic>?;
            final drawnCardId = drawnCard?['cardId']?.toString();
            final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
            final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
            final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
            final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
            final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
            final players = gameState['players'] as List<dynamic>? ?? [];
            final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
            
            List<dynamic> myCollectionRankCards = [];
            for (var player in players) {
              if (player is Map<String, dynamic> && player['id']?.toString() == currentUserId) {
                myCollectionRankCards = player['collection_rank_cards'] as List<dynamic>? ?? [];
                break;
              }
            }
            
            final collectionRankCardIds = myCollectionRankCards
                .where((c) => c is Map<String, dynamic>)
                .map((c) => (c as Map<String, dynamic>)['cardId']?.toString())
                .where((id) => id != null)
                .toSet();
            
            Map<String, Widget> collectionRankWidgets = {};
            
            // Calculate card dimensions as 12% of container width, clamped to max
            final cardWidth = CardDimensions.clampCardWidth(containerWidth * 0.12); // 12% of container width, clamped to max
            final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
            final cardDimensions = Size(cardWidth, cardHeight);
            final stackOffset = cardHeight * CardDimensions.STACK_OFFSET_PERCENTAGE;
            final cardPadding = containerWidth * 0.02;
            const drawnCardExtraPadding = 16.0; // Extra left padding for drawn card
            
            for (int i = 0; i < cards.length; i++) {
              final card = cards[i];
              if (card == null) continue;
              final cardMap = card as Map<String, dynamic>;
              final cardId = cardMap['cardId']?.toString();
              if (cardId == null) continue;
              final isSelected = i == selectedIndex;
              final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
              Map<String, dynamic>? peekedCardData;
              if (cardsToPeek.isNotEmpty) {
                for (var peekedCard in cardsToPeek) {
                  if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                    peekedCardData = peekedCard;
                    break;
                  }
                }
              }
              Map<String, dynamic>? collectionRankCardData;
              if (myCollectionRankCards.isNotEmpty) {
                for (var collectionCard in myCollectionRankCards) {
                  if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                    collectionRankCardData = collectionCard;
                    break;
                  }
                }
              }
              if (collectionRankCardData != null) {
                final cardDataToUse = isDrawnCard && drawnCard != null
                    ? drawnCard 
                    : (peekedCardData ?? collectionRankCardData);
                // Use calculated dimensions from LayoutBuilder
                final playerId = _getCurrentUserId();
                final cardKey = _getOrCreateCardKey('${playerId}_$i', 'my_hand');
                final cardWidget = _buildMyHandCardWidget(cardDataToUse, isSelected, isDrawnCard, false, i, cardMap, cardKey, cardDimensions, currentPlayerStatus: currentPlayerStatus);
                collectionRankWidgets[cardId] = cardWidget;
              }
            }
        
        // Get current player status for glow effect (using same source as status chip)
        final currentPlayerStatusForGlow = _getCurrentUserStatus();
        
        // Build all card widgets with fixed dimensions
        List<Widget> cardWidgets = [];
        for (int index = 0; index < cards.length; index++) {
          final card = cards[index];
          
          // Handle null cards (blank slots from same-rank plays)
          if (card == null) {
            final playerId = _getCurrentUserId();
            final blankSlotKey = _getOrCreateCardKey('${playerId}_$index', 'my_hand');
            cardWidgets.add(
              Padding(
                padding: EdgeInsets.only(right: cardPadding),
                child: Container(
                  key: blankSlotKey,
                  child: _buildMyHandBlankCardSlot(cardDimensions),
                ),
              ),
            );
            continue;
          }
          
          final cardMap = card as Map<String, dynamic>;
          final cardId = cardMap['cardId']?.toString();
          final isSelected = index == selectedIndex;
          final isDrawnCard = drawnCardId != null && cardId == drawnCardId;
          
          // Check if this card is in cardsToPeek (peeked cards have full data)
          Map<String, dynamic>? peekedCardData;
          if (cardId != null && cardsToPeek.isNotEmpty) {
            for (var peekedCard in cardsToPeek) {
              if (peekedCard is Map<String, dynamic> && peekedCard['cardId']?.toString() == cardId) {
                peekedCardData = peekedCard;
                break;
              }
            }
          }
          
          // Check if this card is in player's collection_rank_cards
          Map<String, dynamic>? collectionRankCardData;
          bool isCollectionRankCard = false;
          if (cardId != null && myCollectionRankCards.isNotEmpty) {
            for (var collectionCard in myCollectionRankCards) {
              if (collectionCard is Map<String, dynamic> && collectionCard['cardId']?.toString() == cardId) {
                collectionRankCardData = collectionCard;
                isCollectionRankCard = true;
                break;
              }
            }
          }
          
          // Determine which data to use (priority: drawn card > peeked card > collection rank card > ID-only hand card)
          // For drawn cards, ensure we have full data (rank and suit not '?')
          Map<String, dynamic> cardDataToUse;
          if (isDrawnCard && drawnCard != null) {
            // Validate drawn card has full data
            final hasFullData = drawnCard.containsKey('rank') && 
                               drawnCard['rank'] != null && 
                               drawnCard['rank'] != '?' &&
                               drawnCard.containsKey('suit') && 
                               drawnCard['suit'] != null && 
                               drawnCard['suit'] != '?';
            if (hasFullData) {
              cardDataToUse = drawnCard;
            } else {
              // Drawn card data is incomplete, fall back to other sources
              cardDataToUse = peekedCardData ?? collectionRankCardData ?? cardMap;
            }
          } else {
            cardDataToUse = peekedCardData ?? collectionRankCardData ?? cardMap;
          }
          
          // If this is a collection rank card, render the stack (only once, at the first collection card)
          if (isCollectionRankCard && collectionRankWidgets.containsKey(cardId)) {
            // Check if this is the first collection card in the hand
            bool isFirstCollectionCard = true;
            for (int i = 0; i < index; i++) {
              final prevCard = cards[i];
              if (prevCard != null && prevCard is Map<String, dynamic>) {
                final prevCardId = prevCard['cardId']?.toString();
                if (prevCardId != null && collectionRankCardIds.contains(prevCardId)) {
                  isFirstCollectionCard = false;
                  break;
                }
              }
            }
            
            if (isFirstCollectionCard) {
              // This is the first collection card, render the entire stack
              // Get all collection rank widgets in order
              List<Widget> orderedCollectionWidgets = [];
              for (var collectionCard in myCollectionRankCards) {
                if (collectionCard is Map<String, dynamic>) {
                  final collectionCardId = collectionCard['cardId']?.toString();
                  if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                    // Rebuild collection widgets with fixed dimensions
                    final playerId = _getCurrentUserId();
                    final collectionCardKey = _getOrCreateCardKey('${playerId}_$index', 'my_hand');
                    final collectionCardWidget = _buildMyHandCardWidget(
                      collectionCard, 
                      false, 
                      false, 
                      false, 
                      index, 
                      collectionCard, 
                      collectionCardKey,
                      cardDimensions,
                      currentPlayerStatus: currentPlayerStatusForGlow,
                    );
                    orderedCollectionWidgets.add(collectionCardWidget);
                  }
                }
              }
              
              // Stack needs size constraint to render
              final cardWidth = cardDimensions.width;
              final stackHeight = cardHeight + (orderedCollectionWidgets.length - 1) * stackOffset;
              
              final stackWidget = SizedBox(
                width: cardWidth,
                height: stackHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: orderedCollectionWidgets.asMap().entries.map((entry) {
                    // Stack cards perfectly on top of each other with offset
                    return Positioned(
                      left: 0,
                      top: entry.key * stackOffset,
                      child: entry.value,
                    );
                  }).toList(),
                ),
              );
              
              cardWidgets.add(
                Padding(
                  padding: EdgeInsets.only(
                    right: cardPadding,
                    left: isDrawnCard ? drawnCardExtraPadding : 0,
                  ),
                  child: stackWidget,
                ),
              );
            }
            // Skip non-first collection cards (they're already in the stack)
          } else {
            // Normal card rendering (non-collection rank)
            if (cardId == null) {
              continue;
            }
            final playerId = _getCurrentUserId();
            final cardKey = _getOrCreateCardKey('${playerId}_$index', 'my_hand');
            final cardWidget = _buildMyHandCardWidget(
              cardDataToUse, 
              isSelected, 
              isDrawnCard, 
              false, 
              index, 
              cardMap, 
              cardKey,
              cardDimensions,
              currentPlayerStatus: currentPlayerStatusForGlow,
            );
            
              cardWidgets.add(
                Padding(
                  padding: EdgeInsets.only(
                    right: cardPadding,
                    left: isDrawnCard ? drawnCardExtraPadding : 0,
                  ),
                  child: cardWidget,
                ),
              );
            }
          }
          
          // Add extra empty slot at the end with opacity 0 (for animation space)
          final extraSlotIndex = cards.length;
          final playerId = _getCurrentUserId();
          final extraSlotKey = _getOrCreateCardKey('${playerId}_$extraSlotIndex', 'my_hand');
          cardWidgets.add(
            Opacity(
              opacity: 0.0, // Always invisible but still takes up space
              child: Padding(
                padding: EdgeInsets.only(right: cardPadding),
                child: Container(
                  key: extraSlotKey,
                  child: _buildMyHandBlankCardSlot(cardDimensions),
                ),
              ),
            ),
          );
          
          // Use Wrap widget to allow cards to wrap to next line
          final wrapWidget = Wrap(
            spacing: 0, // Spacing is handled by card padding
            runSpacing: cardPadding, // Vertical spacing between wrapped rows
            alignment: WrapAlignment.start, // Align cards to the left
            children: cardWidgets,
          );
          
          // Update card bounds after build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final playerId = _getCurrentUserId();
            // Update bounds for ALL indices (including empty slots and extra slot)
            // All indices from 0 to cards.length should have bounds tracked (including extra slot)
            for (int i = 0; i <= cards.length; i++) {
              final keyString = '${playerId}_$i';
              final cardKey = _getOrCreateCardKey(keyString, 'my_hand');
              _playScreenFunctions.updateMyHandCardBounds(i, cardKey, keyString: keyString);
            }
            // Clear bounds only for indices beyond the current list length + extra slot
            // maxIndex is cards.length to include the extra slot
            _playScreenFunctions.clearMissingMyHandCardBounds(
              List.generate(cards.length + 1, (i) => i), // All indices from 0 to length (including extra slot)
              maxIndex: cards.length, // Include extra slot at index cards.length
            );
          });
          
          return wrapWidget;
        },
      );
      },
    );
  }

  String _getCurrentUserId() {
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    return loginState['userId']?.toString() ?? '';
  }

  /// Get current user's status from the same source as PlayerStatusChip
  /// This ensures consistency between status chip and card lighting
  String _getCurrentUserStatus() {
    final dutchGameState = _getPrevStateDutchGame();
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    return myHand['playerStatus']?.toString() ?? 'unknown';
  }

  /// Update myhand section height in state (for overlay positioning)
  /// NOTE: This method is no longer used - individual cards are tracked instead
  @Deprecated('Individual cards are now tracked instead of the whole myHand section')
  void _updateMyHandHeight() {
    if (!mounted) return;
    
    // Method deprecated - individual cards are tracked via updateMyHandCardBounds
    // Keeping method stub to avoid breaking any external references
    // No-op since we now track individual cards
  }

  Future<void> _handleCallFinalRound(BuildContext context, String gameId) async {
    if (LOGGING_SWITCH) {
      _logger.info('🎯 MyHandWidget - _handleCallFinalRound called with gameId: $gameId');
    }
    if (_isProcessingAction) {
      if (LOGGING_SWITCH) {
        _logger.info('🚫 MyHandWidget - Action already in progress, ignoring call final round');
      }
      return;
    }
    if (gameId.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('⚠️ MyHandWidget - gameId is empty');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error: No active game found'),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    try {
      setState(() {
        _isProcessingAction = true;
      });
      if (LOGGING_SWITCH) {
        _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true (call final round)');
      }
      if (LOGGING_SWITCH) {
        _logger.info('🎯 MyHandWidget - Creating PlayerAction.callFinalRound with gameId: $gameId');
      }
      final callFinalRoundAction = PlayerAction.callFinalRound(gameId: gameId);
      if (LOGGING_SWITCH) {
        _logger.info('🎯 MyHandWidget - Executing callFinalRoundAction...');
      }
      await callFinalRoundAction.execute();
      if (LOGGING_SWITCH) {
        _logger.info('✅ MyHandWidget - callFinalRoundAction.execute() completed');
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isProcessingAction = false;
          });
          if (LOGGING_SWITCH) {
            _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (call final round)');
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Final Round Called! All players will get one last turn.'),
          backgroundColor: AppColors.warningColor,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingAction = false;
        });
        if (LOGGING_SWITCH) {
          _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (call final round error)');
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to call final round: $e'),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleMyHandCardSelection(BuildContext context, int index, Map<String, dynamic> card) async {
    if (_isProcessingAction) {
      if (LOGGING_SWITCH) {
        _logger.info('🚫 MyHandWidget - Action already in progress, ignoring card selection');
      }
      return;
    }
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentMyHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
    final currentPlayerStatus = _getCurrentUserStatus();
    if (LOGGING_SWITCH) {
      _logger.info('🎯 MyHandWidget - Card tapped: ${card['cardId']}, Status: $currentPlayerStatus');
    }
      
    if (currentPlayerStatus == 'jack_swap') {
      if (LOGGING_SWITCH) {
        _logger.info('🃏 MyHandWidget: Status is jack_swap - cards are interactive');
      }
    }
    if (currentPlayerStatus == 'playing_card' || 
        currentPlayerStatus == 'jack_swap' || 
        currentPlayerStatus == 'queen_peek' ||
        currentPlayerStatus == 'same_rank_window' ||
        currentPlayerStatus == 'initial_peek') {
      if (LOGGING_SWITCH) {
        _logger.info('🎮 MyHandWidget - Status matches allowed statuses: $currentPlayerStatus');
      }
      final updatedMyHand = {
        ...currentMyHand,
        'selectedIndex': index,
        'selectedCard': card,
      };
      StateManager().updateModuleState('dutch_game', {
        ...currentState,
        'myHand': updatedMyHand,
      });
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      if (LOGGING_SWITCH) {
        _logger.info('🎮 MyHandWidget - currentGameId: $currentGameId');
      }
      if (currentGameId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error: No active game found'),
            backgroundColor: AppColors.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      try {
        if (LOGGING_SWITCH) {
          _logger.info('🎮 MyHandWidget - Inside try block, checking status: $currentPlayerStatus');
        }
        if (currentPlayerStatus == 'same_rank_window') {
          if (LOGGING_SWITCH) {
            _logger.info('🎮 MyHandWidget - Status is same_rank_window');
          }
          final sameRankAction = PlayerAction.sameRankPlay(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
          await sameRankAction.execute();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Same Rank Play: ${card['rank']} of ${card['suit']}'
              ),
              backgroundColor: AppColors.infoColor,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (currentPlayerStatus == 'jack_swap') {
          final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
          if (LOGGING_SWITCH) {
            _logger.info('🃏 MyHandWidget: Card tapped during jack_swap - Card: ${card['cardId']}, Player: $currentUserId, Game: $currentGameId');
          }
          if (LOGGING_SWITCH) {
            _logger.info('🃏 MyHandWidget: Current jack swap selection count: ${PlayerAction.getJackSwapSelectionCount()}');
          }
          await PlayerAction.selectCardForJackSwap(
            cardId: card['cardId']?.toString() ?? '',
            playerId: currentUserId,
            gameId: currentGameId,
          );
          final selectionCount = PlayerAction.getJackSwapSelectionCount();
          if (LOGGING_SWITCH) {
            _logger.info('🃏 MyHandWidget: After selection, jack swap count: $selectionCount');
          }
          if (selectionCount == 1) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'First card selected: ${card['rank']} of ${card['suit']}. Select another card to swap.'
                ),
                backgroundColor: AppColors.warningColor,
                duration: Duration(seconds: 2),
              ),
            );
          } else if (selectionCount == 2) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Second card selected: ${card['rank']} of ${card['suit']}. Swapping cards...'
                ),
                backgroundColor: AppColors.accentColor,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else if (currentPlayerStatus == 'queen_peek') {
          final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
          final queenPeekAction = PlayerAction.queenPeek(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
            ownerId: currentUserId,
          );
          await queenPeekAction.execute();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Peeking at: ${card['rank']} of ${card['suit']}'
              ),
              backgroundColor: AppColors.accentColor2,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (currentPlayerStatus == 'initial_peek') {
          final cardId = card['cardId']?.toString() ?? '';
          if (cardId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Invalid card data'),
                backgroundColor: AppColors.errorColor,
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }

          // Check if we're in demo mode
          final games = currentState['games'] as Map<String, dynamic>? ?? {};
          final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
          final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
          final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
          final gameType = gameState['gameType']?.toString() ?? 'normal';
          final isDemoMode = gameType == 'demo';

          if (isDemoMode) {
            // Demo mode: use DemoFunctionality to show card details
            if (LOGGING_SWITCH) {
              _logger.info('🎮 MyHandWidget: Demo mode - adding card to initial peek via DemoFunctionality');
            }
            
            // Check if already selected (using DemoFunctionality's tracking)
            final demoSelectedIds = DemoFunctionality.instance.getInitialPeekSelectedCardIds();
            if (demoSelectedIds.contains(cardId)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Card already selected'),
                  backgroundColor: AppColors.warningColor,
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }

            // Add card to initial peek (this will update myCardsToPeek in state)
            final selectedCount = await DemoFunctionality.instance.addCardToInitialPeek(cardId);
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Card $selectedCount/2 selected'
                ),
                backgroundColor: AppColors.infoColor,
                duration: Duration(seconds: 2),
              ),
            );

            // If 2 cards selected, complete the initial peek
            if (selectedCount == 2) {
              await Future.delayed(Duration(milliseconds: 500));
              final completedInitialPeekAction = PlayerAction.completedInitialPeek(
                gameId: currentGameId,
                cardIds: DemoFunctionality.instance.getInitialPeekSelectedCardIds(),
              );
              await completedInitialPeekAction.execute();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Initial peek completed! You have looked at 2 cards.'
                  ),
                  backgroundColor: AppColors.successColor,
                  duration: Duration(seconds: 3),
                ),
              );
              // Note: DemoFunctionality._handleCompletedInitialPeek already clears the tracking set
              // Cards remain visible in myCardsToPeek so user can see both cards they peeked at
            }
          } else {
            // Normal mode: use existing logic
          if (_initialPeekSelectedCardIds.contains(cardId)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Card already selected'),
                backgroundColor: AppColors.warningColor,
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
          if (_initialPeekSelectionCount < 2) {
            _initialPeekSelectedCardIds.add(cardId);
            _initialPeekSelectionCount++;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Card ${_initialPeekSelectionCount}/2 selected'
                ),
                backgroundColor: AppColors.infoColor,
                duration: Duration(seconds: 2),
              ),
            );
            if (_initialPeekSelectionCount == 2) {
              await Future.delayed(Duration(milliseconds: 500));
              final completedInitialPeekAction = PlayerAction.completedInitialPeek(
                gameId: currentGameId,
                cardIds: _initialPeekSelectedCardIds,
              );
              await completedInitialPeekAction.execute();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Initial peek completed! You have looked at 2 cards.'
                  ),
                  backgroundColor: AppColors.successColor,
                  duration: Duration(seconds: 3),
                ),
              );
              _initialPeekSelectionCount = 0;
              _initialPeekSelectedCardIds.clear();
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'You have already peeked at 2 cards. Initial peek is complete.'
                ),
                backgroundColor: AppColors.warningColor,
                duration: Duration(seconds: 2),
              ),
            );
            }
          }
        } else {
          if (LOGGING_SWITCH) {
            _logger.info('🎮 MyHandWidget - Entering else block for playing_card status');
          }
          setState(() {
            _isProcessingAction = true;
          });
          if (LOGGING_SWITCH) {
            _logger.info('🔒 MyHandWidget - Set _isProcessingAction = true');
          }
          if (LOGGING_SWITCH) {
            _logger.info('🎮 MyHandWidget - About to execute playerPlayCard: cardId=${card['cardId']}, gameId=$currentGameId');
          }
          try {
          final playAction = PlayerAction.playerPlayCard(
            gameId: currentGameId,
            cardId: card['cardId']?.toString() ?? '',
          );
            if (LOGGING_SWITCH) {
              _logger.info('🎮 MyHandWidget - Calling playAction.execute()');
            }
          await playAction.execute();
          } catch (e, stackTrace) {
            if (LOGGING_SWITCH) {
              _logger.error('❌ MyHandWidget - Error executing playAction: $e');
            }
            if (LOGGING_SWITCH) {
              _logger.error('❌ MyHandWidget - Stack trace: $stackTrace');
            }
            rethrow;
          }
          if (LOGGING_SWITCH) {
            _logger.info('🎮 MyHandWidget - playAction.execute() completed');
          }
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isProcessingAction = false;
              });
              if (LOGGING_SWITCH) {
                _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false');
              }
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isProcessingAction = false;
          });
          if (LOGGING_SWITCH) {
            _logger.info('🔓 MyHandWidget - Reset _isProcessingAction = false (error case)');
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to execute action: $e'),
            backgroundColor: AppColors.errorColor,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid action: Cannot interact with hand cards while status is "$currentPlayerStatus"'
          ),
          backgroundColor: AppColors.warningColor,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildMyHandBlankCardSlot([Size? cardDimensions]) {
    final dimensions = cardDimensions ?? CardDimensions.getUnifiedDimensions();
    final cardBackColor = HSLColor.fromColor(AppColors.primaryColor)
        .withSaturation(0.2)
        .toColor();
    // Use dynamic border radius from SSOT to match card widgets
    final borderRadius = CardDimensions.calculateBorderRadius(dimensions);
    return SizedBox(
      width: dimensions.width,
      height: dimensions.height,
      child: Container(
        decoration: BoxDecoration(
          color: cardBackColor,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: AppColors.borderDefault,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
      ),
    );
  }

  Widget _buildMyHandCardWidget(Map<String, dynamic> card, bool isSelected, bool isDrawnCard, bool isCollectionRankCard, int index, Map<String, dynamic> cardMap, GlobalKey cardKey, Size cardDimensions, {String? currentPlayerStatus}) {
    // For drawn cards in user's hand, always show face up
    // Ensure card has full data - if not, try to get it from the cardMap or myDrawnCard in state
    Map<String, dynamic> cardDataToUse = card;
    if (isDrawnCard) {
      // For drawn cards, we MUST have full data (rank, suit, points)
      // Check if current card data is incomplete
      final hasIncompleteData = !card.containsKey('rank') || 
                                card['rank'] == null || 
                                card['rank'] == '?' ||
                                !card.containsKey('suit') || 
                                card['suit'] == null || 
                                card['suit'] == '?';
      
      if (hasIncompleteData) {
        // Try to get full data from cardMap first
        if (cardMap.containsKey('rank') && 
            cardMap['rank'] != null && 
            cardMap['rank'] != '?' &&
            cardMap.containsKey('suit') && 
            cardMap['suit'] != null && 
            cardMap['suit'] != '?') {
          cardDataToUse = cardMap;
        } else {
          // Last resort: try to get from myDrawnCard in state
          final dutchGameState = _getPrevStateDutchGame();
          final myDrawnCard = dutchGameState['myDrawnCard'] as Map<String, dynamic>?;
          if (myDrawnCard != null && 
              myDrawnCard.containsKey('rank') && 
              myDrawnCard['rank'] != null && 
              myDrawnCard['rank'] != '?' &&
              myDrawnCard.containsKey('suit') && 
              myDrawnCard['suit'] != null && 
              myDrawnCard['suit'] != '?') {
            cardDataToUse = myDrawnCard;
          }
        }
      }
    }
    
    final cardModel = CardModel.fromMap(cardDataToUse);
    final updatedCardModel = cardModel.copyWith(isSelected: isSelected);
    
    // For drawn cards in user's hand, show face up ONLY if we have complete data
    // If data is still incomplete after all fallbacks, show back to avoid blank white card
    // For other cards, show back if face down or missing full data
    final hasCompleteData = cardModel.hasFullData && 
                           cardModel.rank != '?' && 
                           cardModel.suit != '?';
    final shouldShowBack = isDrawnCard 
        ? !hasCompleteData  // Show back if data is incomplete
        : (cardModel.isFaceDown || !cardModel.hasFullData);
    
    // Use provided cardDimensions (may be rescaled to fit container)
    Widget cardWidget = CardWidget(
      key: cardKey,
      card: updatedCardModel,
      dimensions: cardDimensions,
      config: CardDisplayConfig.forMyHand(),
      showBack: shouldShowBack,
      isSelected: isSelected,
      onTap: () => _handleMyHandCardSelection(context, index, cardMap),
    );
    
    if (isDrawnCard) {
      cardWidget = SizedBox(
        width: cardDimensions.width,
        height: cardDimensions.height,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFBC02D).withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: cardWidget,
        ),
      );
    }
    
    // Apply glow effect based on current player status
    final glowColor = currentPlayerStatus != null 
        ? _getGlowColorForCards(currentPlayerStatus, true) 
        : null;
    
    if (glowColor != null && _glowAnimation != null) {
      return AnimatedBuilder(
        animation: _glowAnimation!,
        builder: (context, child) {
          final glowOpacity = _glowAnimation!.value;
          final glowDecoration = _buildGlowDecoration(glowColor, glowOpacity);
          return Container(
            decoration: glowDecoration,
            child: cardWidget,
          );
        },
      );
    }
    
    return cardWidget;
  }

  bool _shouldHighlightStatus(String status) {
    if (status == 'waiting' || status == 'same_rank_window') {
      return false;
    }
    return true;
  }

  /// Build circular profile picture widget
  /// Size is 1.5x the status chip height (small size)
  /// Shows user's profile picture if available, otherwise shows default icon
  /// [playerId] The player's session ID
  /// [profilePictureUrl] Optional profile picture URL (for opponents from player data)
  Widget _buildPlayerProfilePicture(String playerId, {String? profilePictureUrl}) {
    // Status chip small size: padding (2*2=4px) + icon (12px) + text (~10px) ≈ 18-20px
    // 1.5x = ~27-30px, using 28px for a nice round number
    const double profilePictureSize = 28.0;
    
    // Get profile picture URL from game_state (SSOT) if not provided
    if (profilePictureUrl == null || profilePictureUrl.isEmpty) {
      final dutchGameState = _getPrevStateDutchGame();
      final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
      final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
      final gameData = games[currentGameId] as Map<String, dynamic>?;
      final gameDataInner = gameData?['gameData'] as Map<String, dynamic>?;
      final gameState = gameDataInner?['game_state'] as Map<String, dynamic>?;
      final players = gameState?['players'] as List<dynamic>? ?? [];
      
      // Find player in game_state by playerId
      try {
        final player = players.cast<Map<String, dynamic>>().firstWhere(
          (p) => p['id']?.toString() == playerId,
        );
        profilePictureUrl = player['profile_picture']?.toString();
      } catch (e) {
        // Player not found in game_state, profilePictureUrl remains null
      }
    }
    
    // If we have a profile picture URL, show it
    if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      return Container(
        width: profilePictureSize,
        height: profilePictureSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceVariant,
          border: Border.all(
            color: AppColors.borderDefault,
            width: 1.5,
          ),
        ),
        child: ClipOval(
          child: Image.network(
            profilePictureUrl,
            width: profilePictureSize,
            height: profilePictureSize,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to icon if image fails to load
              return Icon(
                Icons.person,
                size: profilePictureSize * 0.6,
                color: AppColors.textSecondary,
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              // Show loading indicator while image loads
              return Center(
                child: SizedBox(
                  width: profilePictureSize * 0.4,
                  height: profilePictureSize * 0.4,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    
    // Fallback to default icon
    return Container(
      width: profilePictureSize,
      height: profilePictureSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceVariant,
        border: Border.all(
          color: AppColors.borderDefault,
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.person,
        size: profilePictureSize * 0.6, // Icon is 60% of container size
        color: AppColors.textSecondary,
      ),
    );
  }
}
