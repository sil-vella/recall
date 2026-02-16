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
import '../../../../../utils/widgets/felt_texture_widget.dart';
import '../../demo/demo_functionality.dart';
import '../functionality/playscreenfunctions.dart';
import '../functionality/animations.dart';

const bool LOGGING_SWITCH = false; // Enabled for testing and debugging

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
  /// True immediately when user taps "Call Final Round"; shows "Final Round Active" until state catches up.
  bool _callFinalRoundTappedPending = false;
  bool _isMyHandCardsToPeekProtected = false;
  List<dynamic>? _protectedMyHandCardsToPeek;
  Timer? _myHandCardsToPeekProtectionTimer;
  String? _previousPlayerStatus; // Track previous status to detect transitions
  /// Effective width used for my hand card sizing; updates 2s after layout change to avoid jitter on resize.
  double? _myHandEffectiveWidth;
  Timer? _myHandResizeDelayTimer;

  /// Timer to clear selected-card overlays (opponent highlight + my hand selection) after 3 seconds.
  Timer? _selectedCardOverlayTimer;
  
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
  
  /// Deep copy for state merge (maps and lists only; primitives as-is)
  static dynamic _deepCopyState(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _deepCopyState(val)));
    }
    if (v is List) {
      return v.map((e) => _deepCopyState(e)).toList();
    }
    return v;
  }

  /// Get state for widgets: current state for statuses/timer/phase; cache for hands, discard, and the slices that display them.
  /// Widgets read from slices (myHand, opponentsPanel, centerBoard) and from games[].game_state; we overlay cache only for hands + discard and sync the slices.
  Map<String, dynamic> _getPrevStateDutchGame() {
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    if (_prevStateCache.isEmpty) {
      _initializePrevStateCache();
    }
    // Deep copy current state so we don't mutate StateManager when we overwrite from cache
    final result = _deepCopyState(currentState) as Map<String, dynamic>;
    final currentGameId = currentState['currentGameId']?.toString() ?? '';
    if (currentGameId.isEmpty) return result;

    final cacheGames = _prevStateCache['games'] as Map<String, dynamic>?;
    final cacheGame = cacheGames?[currentGameId] as Map<String, dynamic>?;
    final cacheGameData = cacheGame?['gameData'] as Map<String, dynamic>?;
    final cacheGameState = cacheGameData?['game_state'] as Map<String, dynamic>?;
    if (cacheGameState == null) return result;

    final resultGames = result['games'] as Map<String, dynamic>?;
    final resultGame = resultGames?[currentGameId] as Map<String, dynamic>?;
    final resultGameData = resultGame?['gameData'] as Map<String, dynamic>?;
    final resultGameState = resultGameData?['game_state'] as Map<String, dynamic>?;
    if (resultGameState == null) return result;

    // 1) Overlay player hands in game_state (SSOT for hands)
    final cachePlayers = cacheGameState['players'] as List<dynamic>? ?? [];
    final resultPlayers = resultGameState['players'] as List<dynamic>? ?? [];
    for (int i = 0; i < resultPlayers.length && i < cachePlayers.length; i++) {
      final rp = resultPlayers[i];
      final cp = cachePlayers[i];
      if (rp is Map<String, dynamic> && cp is Map<String, dynamic> && cp.containsKey('hand')) {
        rp['hand'] = _deepCopyState(cp['hand']);
      }
    }
    // 2) My hand cards in games (current user)
    if (cacheGame != null && cacheGame.containsKey('myHandCards') && resultGame != null) {
      resultGame['myHandCards'] = _deepCopyState(cacheGame['myHandCards']);
    }
    // 3) Discard pile (and draw pile for consistency) in game_state
    if (cacheGameState.containsKey('discardPile')) {
      resultGameState['discardPile'] = _deepCopyState(cacheGameState['discardPile']);
    }
    if (cacheGameState.containsKey('drawPile')) {
      resultGameState['drawPile'] = _deepCopyState(cacheGameState['drawPile']);
    }

    // 4) Recomputed slices: myHand and opponentsPanel read from these, so overwrite with cache so cards show cached
    final cacheMyHand = _prevStateCache['myHand'] as Map<String, dynamic>?;
    if (cacheMyHand != null && cacheMyHand.containsKey('cards') && result['myHand'] is Map<String, dynamic>) {
      (result['myHand'] as Map<String, dynamic>)['cards'] = _deepCopyState(cacheMyHand['cards']);
    }
    final cacheOpp = _prevStateCache['opponentsPanel'] as Map<String, dynamic>?;
    if (cacheOpp != null && cacheOpp.containsKey('opponents') && result['opponentsPanel'] is Map<String, dynamic>) {
      (result['opponentsPanel'] as Map<String, dynamic>)['opponents'] = _deepCopyState(cacheOpp['opponents']);
    }
    // 5) centerBoard slice: topDiscard and drawPileCount so discard-pile display uses cached discard
    final cacheCenter = _prevStateCache['centerBoard'] as Map<String, dynamic>?;
    if (cacheCenter != null && result['centerBoard'] is Map<String, dynamic>) {
      final rb = result['centerBoard'] as Map<String, dynamic>;
      if (cacheCenter.containsKey('topDiscard')) rb['topDiscard'] = _deepCopyState(cacheCenter['topDiscard']);
      if (cacheCenter.containsKey('drawPileCount')) rb['drawPileCount'] = cacheCenter['drawPileCount'];
    }

    // 6) Status always from current: game_state.players[].status is SSOT. Re-apply onto slices so no cached status leaks.
    final resultOpponents = (result['opponentsPanel'] as Map<String, dynamic>?)?['opponents'] as List<dynamic>? ?? [];
    for (final opp in resultOpponents) {
      if (opp is! Map<String, dynamic>) continue;
      final oppId = opp['id']?.toString();
      if (oppId == null) continue;
      for (final p in resultPlayers) {
        if (p is Map<String, dynamic> && p['id']?.toString() == oppId && p.containsKey('status')) {
          opp['status'] = p['status'];
          break;
        }
      }
    }
    // myHand.playerStatus = current user's status from game_state.players
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
    if (currentUserId.isNotEmpty && result['myHand'] is Map<String, dynamic>) {
      for (final p in resultPlayers) {
        if (p is Map<String, dynamic> && p['id']?.toString() == currentUserId && p.containsKey('status')) {
          (result['myHand'] as Map<String, dynamic>)['playerStatus'] = p['status']?.toString();
          break;
        }
      }
    }

    return result;
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
      
      // Collect all actions from all players first
      List<Map<String, dynamic>> allActions = [];
      
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _processStateUpdate: Checking ${players.length} players for actions');
      }
      
      for (var player in players) {
        if (player is! Map<String, dynamic>) continue;
        
        final playerId = player['id']?.toString();
        final actionValue = player['action'];
        
        // Handle both list format (queue) and legacy single action format
        List<Map<String, dynamic>> actionQueue = [];
        
        if (actionValue is List) {
          // New queue format: list of {'name': 'action_name_id', 'data': {...}}
          for (var actionItem in actionValue) {
            if (actionItem is Map<String, dynamic>) {
              final actionName = actionItem['name']?.toString();
              final actionData = actionItem['data'] as Map<String, dynamic>?;
              if (actionName != null && actionData != null) {
                actionQueue.add({'name': actionName, 'data': actionData, 'playerId': playerId});
              }
            }
          }
          if (LOGGING_SWITCH && actionQueue.isNotEmpty) {
            _logger.info('🎬 _processStateUpdate: Player $playerId - Found ${actionQueue.length} action(s) in queue');
          }
        } else if (actionValue != null) {
          // Legacy format: single action string with separate actionData
          final actionName = actionValue.toString();
          final actionData = player['actionData'] as Map<String, dynamic>?;
          if (actionData != null) {
            actionQueue.add({'name': actionName, 'data': actionData, 'playerId': playerId});
          }
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _processStateUpdate: Player $playerId - Found legacy single action format: $actionName');
          }
        }
        
        allActions.addAll(actionQueue);
      }
      
      // Expand jack_swap into two sequential anims: 1st moveWithEmptySlot (card1→slot2), 2nd moveCard (card2→slot1)
      final expandedActions = <Map<String, dynamic>>[];
      for (final actionItem in allActions) {
        final name = actionItem['name']?.toString() ?? '';
        final baseName = Animations.extractBaseActionName(name);
        if (baseName == 'jack_swap') {
          final data = actionItem['data'] as Map<String, dynamic>?;
          final card1Data = data?['card1Data'] as Map<String, dynamic>?;
          final card2Data = data?['card2Data'] as Map<String, dynamic>?;
          if (card1Data != null && card2Data != null) {
            final lastUnderscore = name.lastIndexOf('_');
            final suffix = lastUnderscore >= 0 && lastUnderscore < name.length - 1
                ? name.substring(lastUnderscore + 1)
                : '';
            final id = suffix.length == 6 ? int.tryParse(suffix) : null;
            final baseId = id ?? 0;
            // Flash overlay on both card indexes first, then the two move anims
            expandedActions.add({
              'name': 'jack_swap_flash_$suffix',
              'data': {'card1Data': card1Data, 'card2Data': card2Data},
              'playerId': actionItem['playerId'],
            });
            expandedActions.add({
              'name': 'jack_swap_1_${baseId + 1}',
              'data': {'card1Data': card1Data, 'card2Data': card2Data},
              'playerId': actionItem['playerId'],
            });
            expandedActions.add({
              'name': 'jack_swap_2_${baseId + 2}',
              'data': {'card1Data': card2Data, 'card2Data': card1Data},
              'playerId': actionItem['playerId'],
            });
            Animations.markActionAsProcessed(name);
            if (LOGGING_SWITCH) {
              _logger.info('🎬 _processStateUpdate: Expanded jack_swap into jack_swap_flash + jack_swap_1 (moveWithEmptySlot) + jack_swap_2 (moveCard)');
            }
          } else {
            expandedActions.add(actionItem);
          }
        } else {
          expandedActions.add(actionItem);
        }
      }
      allActions = expandedActions;
      
      // Set up 4-second timeout to bypass animation wait if needed
      bool timeoutTriggered = false;
      if (allActions.isNotEmpty) {
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
        
        // Process actions sequentially - await each animation before starting the next
        try {
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _processStateUpdate: Processing ${allActions.length} action(s) sequentially...');
          }
          
          for (var actionItem in allActions) {
            final action = actionItem['name']?.toString();
            final actionData = actionItem['data'] as Map<String, dynamic>?;
            final actionPlayerId = actionItem['playerId']?.toString();
            
            if (action == null || actionData == null) continue;
            
            if (LOGGING_SWITCH) {
              _logger.info('🎬 _processStateUpdate: Player $actionPlayerId - Processing action: $action');
              _logger.info('🎬 _processStateUpdate: Action $action requiresAnimation: ${Animations.requiresAnimation(action)}');
            }
            
            if (Animations.requiresAnimation(action)) {
              if (LOGGING_SWITCH) {
                _logger.info('🎬 _processStateUpdate: Action $action requires animation');
              }
              
              // Validate action data
              if (Animations.validateActionData(action, actionData)) {
                if (LOGGING_SWITCH) {
                  _logger.info('🎬 _processStateUpdate: Action data validated successfully');
                }
                
                // Check if already in active animations or already processed
                if (_activeAnimations.containsKey(action)) {
                  if (LOGGING_SWITCH) {
                    _logger.info('🎬 _processStateUpdate: Action $action already in active animations, skipping');
                  }
                  continue;
                } else if (Animations.isActionProcessed(action)) {
                  if (LOGGING_SWITCH) {
                    _logger.info('🎬 _processStateUpdate: Action $action already processed, skipping');
                  }
                  continue;
                } else {
                  if (LOGGING_SWITCH) {
                    _logger.info('🎬 _processStateUpdate: Triggering animation for action: $action');
                  }
                  // Trigger animation and await its completion before processing next action
                  final future = _triggerAnimation(action, actionData);
                  if (future != null) {
                    // Restart 4s timeout so each animation in the sequence gets a full 4s (e.g. penalty drawn_card after same_rank_reject)
                    _animationTimeoutTimer?.cancel();
                    _animationTimeoutTimer = Timer(const Duration(seconds: 4), () {
                      if (mounted && !timeoutTriggered) {
                        timeoutTriggered = true;
                        if (LOGGING_SWITCH) {
                          _logger.warning('🎬 _processStateUpdate: Animation timeout (4s) - clearing animations and continuing');
                        }
                        for (final animData in _activeAnimations.values) {
                          final controller = animData['controller'] as AnimationController?;
                          controller?.dispose();
                        }
                        _activeAnimations.clear();
                        if (mounted) setState(() {});
                        _completeStateUpdate();
                      }
                    });
                    if (LOGGING_SWITCH) {
                      _logger.info('🎬 _processStateUpdate: Waiting for animation $action to complete...');
                    }
                    await future;
                    if (LOGGING_SWITCH) {
                      _logger.info('🎬 _processStateUpdate: Animation $action completed, proceeding to next action');
                    }
                  }
                }
              } else {
                if (LOGGING_SWITCH) {
                  _logger.warning('🎬 _processStateUpdate: Action data validation failed for action: $action');
                }
              }
            }
          }
          
          // Cancel timeout since all animations completed
          _animationTimeoutTimer?.cancel();
          _animationTimeoutTimer = null;
          
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _processStateUpdate: All animations completed sequentially, now updating prev_state');
          }
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.error('🎬 _processStateUpdate: Animation error: $e');
          }
          // Cancel timeout on error
          _animationTimeoutTimer?.cancel();
          _animationTimeoutTimer = null;
        }
      } else {
        if (LOGGING_SWITCH) {
          _logger.info('🎬 _processStateUpdate: No animations to process, updating prev_state immediately');
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
    _myHandResizeDelayTimer?.cancel();
    _selectedCardOverlayTimer?.cancel();
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
                if (LOGGING_SWITCH) {
                  _logger.info('[GameBoard overflow] build: root constraints maxW=${constraints.maxWidth} maxH=${constraints.maxHeight} minW=${constraints.minWidth} minH=${constraints.minHeight}');
                }
                // Layout: Opponents section takes all space (3 cols); game board in middle col at bottom; My Hand below
                return Column(
                  children: [
                    // Opponents Panel Section (3 columns; game board lives in middle column, aligned to bottom)
                    Expanded(
                      child: _buildOpponentsPanel(),
                    ),
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
    
    // Separate flashCard animations from other animations
    List<Widget> flashCardBorders = [];
    List<Widget> otherAnimations = [];
    
    for (final animData in _activeAnimations.values) {
      final animationType = animData['animationType'] as AnimationType?;
      if (animationType == AnimationType.flashCard) {
        // Build flash borders for flashCard animation
        final borders = _buildFlashCardBorders(animData, stackGlobalOffset);
        flashCardBorders.addAll(borders);
      } else {
        // Build regular animated card
        otherAnimations.add(_buildAnimatedCard(animData, stackGlobalOffset));
      }
    }
    
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ...otherAnimations,
          ...flashCardBorders,
        ],
      ),
    );
  }
  
  /// Build flash overlays for flashCard animation - renders filled overlays on all peeked cards (color by action: queen_peek, initial_peek, jack_swap_flash)
  List<Widget> _buildFlashCardBorders(Map<String, dynamic> animData, Offset stackGlobalOffset) {
    final animationController = animData['controller'] as AnimationController?;
    final animation = animData['animation'] as Animation<double>?;
    final cardBoundsList = animData['cardBoundsList'] as List<dynamic>?;
    
    if (animationController == null || animation == null || cardBoundsList == null) {
      return [];
    }
    
    // Overlay color by action type (theme: statusQueenPeek, statusInitialPeek, statusJackSwap, statusPeeking)
    final baseActionName = Animations.extractBaseActionName(animData['actionName']?.toString() ?? '');
    final Color overlayBaseColor;
    switch (baseActionName) {
      case 'jack_swap_flash':
        overlayBaseColor = AppColors.statusJackSwap;
        break;
      case 'queen_peek':
        overlayBaseColor = AppColors.statusQueenPeek;
        break;
      case 'initial_peek':
        overlayBaseColor = AppColors.statusInitialPeek;
        break;
      default:
        overlayBaseColor = AppColors.statusPeeking;
    }
    final overlayColor = overlayBaseColor.withOpacity(0.5);
    
    // Create 3 flashes: flash at 0.0-0.33, 0.33-0.66, 0.66-1.0
    // Each flash: fade in (0-0.1), stay visible (0.1-0.4), fade out (0.4-0.5)
    return cardBoundsList.map((cardBounds) {
      if (cardBounds is! Map<String, dynamic>) return const SizedBox.shrink();
      
      final position = cardBounds['position'] as Offset?;
      final size = cardBounds['size'] as Size?;
      
      if (position == null || size == null) return const SizedBox.shrink();
      
      final localPosition = position - stackGlobalOffset;
      // Use same border radius as cards (CardDimensions) so overlay matches card shape
      final overlayBorderRadius = CardDimensions.calculateBorderRadius(size);
      
      return AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          // Calculate opacity for 3 flashes
          double opacity = 0.0;
          final value = animation.value;
          
          // Flash 1: 0.0 - 0.33
          if (value >= 0.0 && value < 0.33) {
            final flashValue = value / 0.33;
            if (flashValue < 0.2) {
              // Fade in
              opacity = flashValue / 0.2;
            } else if (flashValue < 0.8) {
              // Stay visible
              opacity = 1.0;
            } else {
              // Fade out
              opacity = 1.0 - ((flashValue - 0.8) / 0.2);
            }
          }
          // Flash 2: 0.33 - 0.66
          else if (value >= 0.33 && value < 0.66) {
            final flashValue = (value - 0.33) / 0.33;
            if (flashValue < 0.2) {
              // Fade in
              opacity = flashValue / 0.2;
            } else if (flashValue < 0.8) {
              // Stay visible
              opacity = 1.0;
            } else {
              // Fade out
              opacity = 1.0 - ((flashValue - 0.8) / 0.2);
            }
          }
          // Flash 3: 0.66 - 1.0
          else if (value >= 0.66 && value <= 1.0) {
            final flashValue = (value - 0.66) / 0.34;
            if (flashValue < 0.2) {
              // Fade in
              opacity = flashValue / 0.2;
            } else if (flashValue < 0.8) {
              // Stay visible
              opacity = 1.0;
            } else {
              // Fade out
              opacity = 1.0 - ((flashValue - 0.8) / 0.2);
            }
          }
          
          return Positioned(
            left: localPosition.dx,
            top: localPosition.dy,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: size.width,
                height: size.height,
                decoration: BoxDecoration(
                  color: overlayColor,
                  borderRadius: BorderRadius.circular(overlayBorderRadius),
                ),
              ),
            ),
          );
        },
      );
    }).toList();
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
    
    // Special handling for flashCard animations (initial_peek, queen_peek, etc.) - dynamically handles any number of players and cards
    if (animationType == AnimationType.flashCard) {
      return _triggerFlashCardAnimation(actionName, actionData);
    }
    
    // Compound: same_rank_reject (hand to discard, then discard to hand, continuous)
    if (animationType == AnimationType.compoundSameRankReject) {
      return _triggerSameRankRejectAnimation(actionName, actionData);
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
        
        // For moveCard, determine source and destination based on action type
        if (animationType == AnimationType.moveCard) {
          final baseActionName = Animations.extractBaseActionName(actionName);
          if (baseActionName == 'drawn_card') {
            // Drawn card: source is draw pile, destination is hand
            sourceBounds = _playScreenFunctions.getCachedDrawPileBounds();
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
            if (LOGGING_SWITCH) {
              _logger.info('🎬 _triggerAnimation: Draw pile bounds (source): $sourceBounds');
            }
          } else if (baseActionName == 'collect_from_discard') {
            // Collect from discard: source is discard pile, destination is hand (same data shape as drawn_card)
            sourceBounds = _playScreenFunctions.getCachedDiscardPileBounds();
            if (isMyHand) {
              destBounds = _playScreenFunctions.getCachedMyHandCardBounds(cardIndex);
            } else {
              destBounds = _playScreenFunctions.getCachedOpponentCardBounds(playerId, cardIndex);
            }
            if (LOGGING_SWITCH) {
              _logger.info('🎬 _triggerAnimation: collect_from_discard - Discard pile bounds (source): $sourceBounds');
              _logger.info('🎬 _triggerAnimation: collect_from_discard - Hand bounds (dest): $destBounds');
            }
          } else if (baseActionName == 'jack_swap') {
            // Original jack_swap only seen before expansion; jack_swap_1/jack_swap_2 handled in moveWithEmptySlot
          }
        } else if (animationType == AnimationType.moveWithEmptySlot) {
          final baseActionName = Animations.extractBaseActionName(actionName);
          if (baseActionName == 'play_card' || baseActionName == 'same_rank') {
            // play_card / same_rank: source is hand, destination is discard pile
            sourceBounds = isMyHand 
                ? _playScreenFunctions.getCachedMyHandCardBounds(cardIndex)
                : _playScreenFunctions.getCachedOpponentCardBounds(playerId, cardIndex);
            destBounds = _playScreenFunctions.getCachedDiscardPileBounds();
            if (LOGGING_SWITCH) {
              _logger.info('🎬 _triggerAnimation: moveWithEmptySlot ($baseActionName) - Hand card bounds (source): $sourceBounds');
              _logger.info('🎬 _triggerAnimation: moveWithEmptySlot ($baseActionName) - Discard pile bounds (destination): $destBounds');
            }
          } else if (baseActionName == 'draw_reposition' || baseActionName == 'jack_swap' || baseActionName == 'jack_swap_1' || baseActionName == 'jack_swap_2') {
            // draw_reposition / jack_swap_1 (empty at source) / jack_swap_2 (empty at dest): source = card1Index, dest = card2Index (both in hand)
            final card2Data = actionData['card2Data'] as Map<String, dynamic>?;
            final card2Index = card2Data?['cardIndex'] as int?;
            final card2PlayerId = card2Data?['playerId']?.toString();
            
            if (card2Index != null) {
              // Source: card1Index
              if (isMyHand) {
                sourceBounds = _playScreenFunctions.getCachedMyHandCardBounds(cardIndex);
              } else {
                sourceBounds = _playScreenFunctions.getCachedOpponentCardBounds(playerId, cardIndex);
              }
              
              // Destination: card2Index
              final isCard2MyHand = card2PlayerId != null && card2PlayerId == DutchEventHandlerCallbacks.getCurrentUserId();
              if (isCard2MyHand) {
                destBounds = _playScreenFunctions.getCachedMyHandCardBounds(card2Index);
              } else if (card2PlayerId != null) {
                destBounds = _playScreenFunctions.getCachedOpponentCardBounds(card2PlayerId, card2Index);
              } else {
                if (isMyHand) {
                  destBounds = _playScreenFunctions.getCachedMyHandCardBounds(card2Index);
                } else {
                  destBounds = _playScreenFunctions.getCachedOpponentCardBounds(playerId, card2Index);
                }
              }
              
              if (LOGGING_SWITCH) {
                _logger.info('🎬 _triggerAnimation: moveWithEmptySlot ($baseActionName) - Source (card1Index $cardIndex, playerId $playerId): $sourceBounds');
                _logger.info('🎬 _triggerAnimation: moveWithEmptySlot ($baseActionName) - Destination (card2Index $card2Index, playerId $card2PlayerId): $destBounds');
              }
            } else {
              if (LOGGING_SWITCH) {
                _logger.warning('🎬 _triggerAnimation: Missing card2Index in card2Data for $baseActionName');
              }
            }
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
    
    // Mark action as processed immediately to prevent duplicate animations
    // This prevents the same action from being processed again from cached state
    Animations.markActionAsProcessed(actionName);
    
    // Create animation controller
    final controller = AnimationController(
      duration: duration,
      vsync: this,
    );
    
    final animation = CurvedAnimation(
      parent: controller,
      curve: curve,
    );
    
    // Get card data for the animation (use optional card1FullData for play_card and collect_from_discard)
    Map<String, dynamic>? cardData;
    final baseActionNameForCard = Animations.extractBaseActionName(actionName);
    if ((baseActionNameForCard == 'play_card' || baseActionNameForCard == 'same_rank' || baseActionNameForCard == 'collect_from_discard') &&
        actionData.containsKey('card1FullData')) {
      final full = actionData['card1FullData'];
      if (full is Map<String, dynamic>) cardData = full;
    }
    if (cardData == null && card1Data != null) {
      final playerId = card1Data['playerId']?.toString();
      final cardIndex = card1Data['cardIndex'] as int?;
      
      if (playerId != null && cardIndex != null) {
        // Get card data from game state (fallback when card1FullData not provided)
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
      'actionName': actionName, // Store action name to identify action type
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
      
      if (mounted) {
        // For play_card/same_rank: update prev_state so discard shows the new card
        // in the same frame the overlay is removed (avoids brief flash of old discard)
        final baseName = Animations.extractBaseActionName(actionName);
        if (baseName == 'play_card' || baseName == 'same_rank') {
          _updatePrevStateCache();
        }
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
  
  /// Compound animation for wrong same-rank attempt: card to discard, then back to hand (continuous).
  Future<void>? _triggerSameRankRejectAnimation(String actionName, Map<String, dynamic> actionData) async {
    Animations.markActionAsProcessed(actionName);
    final card1Data = actionData['card1Data'] as Map<String, dynamic>?;
    if (card1Data == null) return null;
    final playerId = card1Data['playerId']?.toString();
    final cardIndex = card1Data['cardIndex'] as int?;
    if (playerId == null || cardIndex == null) return null;
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
    final isMyHand = playerId == currentUserId;

    // Resolve cardData: use optional card1FullData from backend so overlay can show card face
    Map<String, dynamic>? cardData;
    if (actionData.containsKey('card1FullData')) {
      final full = actionData['card1FullData'];
      if (full is Map<String, dynamic>) cardData = full;
    }
    if (cardData == null) {
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final games = currentState['games'] as Map<String, dynamic>? ?? {};
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      if (currentGameId.isNotEmpty && games.containsKey(currentGameId)) {
        final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
        final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
        final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
        final players = gameState['players'] as List<dynamic>? ?? [];
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

    const phaseDuration = Duration(milliseconds: 1000);
    final curve = Curves.easeInOutCubic;

    // Phase 1: hand to discard (moveWithEmptySlot)
    Map<String, dynamic>? sourceBounds = isMyHand
        ? _playScreenFunctions.getCachedMyHandCardBounds(cardIndex)
        : _playScreenFunctions.getCachedOpponentCardBounds(playerId, cardIndex);
    Map<String, dynamic>? destBounds = _playScreenFunctions.getCachedDiscardPileBounds();
    if (sourceBounds == null || destBounds == null) return null;

    final outKey = '${actionName}_out';
    final controller1 = AnimationController(duration: phaseDuration, vsync: this);
    final animation1 = CurvedAnimation(parent: controller1, curve: curve);
    _activeAnimations[outKey] = {
      'actionName': outKey,
      'animationType': AnimationType.moveWithEmptySlot,
      'sourceBounds': sourceBounds,
      'destBounds': destBounds,
      'controller': controller1,
      'animation': animation1,
      'cardData': cardData,
    };
    if (mounted) setState(() {});
    await controller1.forward();
    if (mounted) {
      _activeAnimations.remove(outKey);
      controller1.dispose();
      setState(() {});
    }

    // Phase 2: discard to hand (moveCard) - no delay for continuous animation
    sourceBounds = _playScreenFunctions.getCachedDiscardPileBounds();
    destBounds = isMyHand
        ? _playScreenFunctions.getCachedMyHandCardBounds(cardIndex)
        : _playScreenFunctions.getCachedOpponentCardBounds(playerId, cardIndex);
    if (sourceBounds == null || destBounds == null) return null;

    final backKey = '${actionName}_back';
    final controller2 = AnimationController(duration: phaseDuration, vsync: this);
    final animation2 = CurvedAnimation(parent: controller2, curve: curve);
    _activeAnimations[backKey] = {
      'actionName': backKey,
      'animationType': AnimationType.moveCard,
      'sourceBounds': sourceBounds,
      'destBounds': destBounds,
      'controller': controller2,
      'animation': animation2,
      'cardData': cardData,
    };
    if (mounted) setState(() {});
    await controller2.forward();
    if (mounted) {
      _activeAnimations.remove(backKey);
      controller2.dispose();
      setState(() {});
    }
    return null;
  }
  
  /// Trigger flashCard animation - dynamically handles any number of players and cards
  /// Supports actions like initial_peek (multiple players, 2 cards each) and queen_peek (1 player, 1 card)
  Future<void>? _triggerFlashCardAnimation(String actionName, Map<String, dynamic> actionData) {
    final baseActionName = Animations.extractBaseActionName(actionName);
    
    // Check if we've already started a flashCard animation for this action type
    // For initial_peek: only process the first action (all players flash together)
    // For queen_peek: each action is independent
    if (baseActionName == 'initial_peek') {
      // Check if any flashCard animation is already active
      for (final animData in _activeAnimations.values) {
        if (animData['animationType'] == AnimationType.flashCard) {
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _triggerFlashCardAnimation: FlashCard animation already active, skipping duplicate action: $actionName');
          }
          // Mark this action as processed but don't create a new animation
          Animations.markActionAsProcessed(actionName);
          return null;
        }
      }
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _triggerFlashCardAnimation: Starting flashCard animation for $actionName');
    }
    
    // Collect all players' peeked cards from game state
    final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final games = currentState['games'] as Map<String, dynamic>? ?? {};
    final currentGameId = currentState['currentGameId']?.toString() ?? '';
    
    if (currentGameId.isEmpty || !games.containsKey(currentGameId)) {
      if (LOGGING_SWITCH) {
        _logger.warning('🎬 _triggerFlashCardAnimation: Missing game state');
      }
      return null;
    }
    
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
    final players = gameState['players'] as List<dynamic>? ?? [];
    final currentUserId = DutchEventHandlerCallbacks.getCurrentUserId();
    
    // Extract playerId from the actionData that triggered this animation
    // Try to find any cardData to get the playerId
    String? triggerPlayerId;
    for (var key in actionData.keys) {
      if (key.endsWith('Data') && actionData[key] is Map<String, dynamic>) {
        final cardData = actionData[key] as Map<String, dynamic>;
        triggerPlayerId = cardData['playerId']?.toString();
        if (triggerPlayerId != null) break;
      }
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _triggerFlashCardAnimation: Trigger actionData: $actionData');
      _logger.info('🎬 _triggerFlashCardAnimation: Trigger playerId: $triggerPlayerId, baseActionName: $baseActionName');
    }
    
    // Collect all peeked card bounds
    List<Map<String, dynamic>> cardBoundsList = [];
    
    // Determine which players to process based on action type
    List<Map<String, dynamic>> playersToProcess = [];
    
    if (baseActionName == 'jack_swap_flash') {
      // jack_swap_flash: use only card1Data and card2Data from actionData (two affected indexes)
      final card1Data = actionData['card1Data'] as Map<String, dynamic>?;
      final card2Data = actionData['card2Data'] as Map<String, dynamic>?;
      if (card1Data != null && card2Data != null) {
        for (final cardData in [card1Data, card2Data]) {
          final cardIndex = cardData['cardIndex'] as int?;
          final targetPlayerId = cardData['playerId']?.toString();
          if (cardIndex == null || targetPlayerId == null) continue;
          final isTargetMyHand = targetPlayerId == currentUserId;
          Map<String, dynamic>? cardBounds;
          if (isTargetMyHand) {
            cardBounds = _playScreenFunctions.getCachedMyHandCardBounds(cardIndex);
          } else {
            cardBounds = _playScreenFunctions.getCachedOpponentCardBounds(targetPlayerId, cardIndex);
          }
          if (cardBounds != null) cardBoundsList.add(cardBounds);
        }
      }
    }
    
    if (baseActionName == 'initial_peek') {
      // initial_peek: process all players (multi-player action)
      playersToProcess = players.whereType<Map<String, dynamic>>().toList();
    } else if (baseActionName == 'queen_peek') {
      // queen_peek: process only the triggering player (single-player action)
      if (triggerPlayerId != null) {
        final triggerPlayer = players.firstWhere(
          (p) => p is Map<String, dynamic> && p['id']?.toString() == triggerPlayerId,
          orElse: () => <String, dynamic>{},
        );
        if (triggerPlayer is Map<String, dynamic> && triggerPlayer.isNotEmpty) {
          playersToProcess = [triggerPlayer];
        }
      }
    } else if (baseActionName != 'jack_swap_flash') {
      // Default: process all players (for future extensibility)
      playersToProcess = players.whereType<Map<String, dynamic>>().toList();
    }
    
    for (var player in playersToProcess) {
      final playerId = player['id']?.toString();
      if (playerId == null) continue;
      
      // Get player's action queue to find matching action
      final actionValue = player['action'];
      Map<String, dynamic>? playerActionData;
      
      // For the triggering player, use the actionData passed in (more reliable)
      if (playerId == triggerPlayerId) {
        playerActionData = actionData;
        if (LOGGING_SWITCH) {
          _logger.info('🎬 _triggerFlashCardAnimation: Using passed-in actionData for trigger player $playerId');
        }
      } else {
        // For other players, read from their action queue
        if (actionValue is List) {
          for (var actionItem in actionValue) {
            if (actionItem is Map<String, dynamic>) {
              final actionNameItem = actionItem['name']?.toString();
              if (actionNameItem != null && Animations.extractBaseActionName(actionNameItem) == baseActionName) {
                playerActionData = actionItem['data'] as Map<String, dynamic>?;
                break;
              }
            }
          }
        }
      }
      
      if (playerActionData == null) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎬 _triggerFlashCardAnimation: No $baseActionName action data found for player $playerId');
        }
        continue;
      }
      
      // Dynamically extract all card data (card1Data, card2Data, card3Data, etc.)
      final cardDataList = <Map<String, dynamic>>[];
      int cardIndex = 1;
      while (true) {
        final cardDataKey = 'card${cardIndex}Data';
        final cardData = playerActionData[cardDataKey] as Map<String, dynamic>?;
        if (cardData == null) break;
        cardDataList.add(cardData);
        cardIndex++;
      }
      
      if (cardDataList.isEmpty) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎬 _triggerFlashCardAnimation: No card data found in actionData for player $playerId');
        }
        continue;
      }
      
      final isMyHand = playerId == currentUserId;
      final hand = player['hand'] as List<dynamic>? ?? [];
      
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _triggerFlashCardAnimation: Player $playerId (isMyHand: $isMyHand) - Found ${cardDataList.length} card(s) to flash');
        _logger.info('🎬 _triggerFlashCardAnimation: Hand length: ${hand.length}, actionData: $playerActionData');
      }
      
      // Process each card dynamically
      for (int i = 0; i < cardDataList.length; i++) {
        final cardData = cardDataList[i];
        final cardIndex = cardData['cardIndex'] as int?;
        final cardPlayerId = cardData['playerId']?.toString();
        
        if (cardIndex == null) continue;
        
        // For queen_peek, the card might be in a different player's hand
        final targetPlayerId = cardPlayerId ?? playerId;
        final isTargetMyHand = targetPlayerId == currentUserId;
        
        // Get the target player's hand for verification
        final targetPlayer = players.firstWhere(
          (p) => p is Map<String, dynamic> && p['id']?.toString() == targetPlayerId,
          orElse: () => <String, dynamic>{},
        );
        final targetHand = (targetPlayer is Map<String, dynamic> ? targetPlayer['hand'] : null) as List<dynamic>? ?? [];
        
        // Log card ID at this index to verify it matches
        String? cardIdAtIndex;
        if (cardIndex >= 0 && cardIndex < targetHand.length) {
          final card = targetHand[cardIndex];
          if (card is Map<String, dynamic>) {
            cardIdAtIndex = card['cardId']?.toString();
          } else if (card is String) {
            cardIdAtIndex = card;
          }
        }
        
        if (LOGGING_SWITCH) {
          _logger.info('🎬 _triggerFlashCardAnimation: Card ${i + 1} - index: $cardIndex (cardId: $cardIdAtIndex), targetPlayerId: $targetPlayerId');
        }
        
        // Get bounds for this card
        Map<String, dynamic>? cardBounds;
        if (isTargetMyHand) {
          cardBounds = _playScreenFunctions.getCachedMyHandCardBounds(cardIndex);
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _triggerFlashCardAnimation: My hand card${i + 1} bounds for index $cardIndex: $cardBounds');
          }
        } else {
          cardBounds = _playScreenFunctions.getCachedOpponentCardBounds(targetPlayerId, cardIndex);
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _triggerFlashCardAnimation: Opponent $targetPlayerId card${i + 1} bounds for index $cardIndex: $cardBounds');
          }
        }
        
        // For initial_peek, skip flashing our own cards - we select them ourselves, no overlay needed on my hand
        if (baseActionName == 'initial_peek' && isTargetMyHand) {
          if (LOGGING_SWITCH) {
            _logger.info('🎬 _triggerFlashCardAnimation: Skipping initial_peek flash on my hand card (index $cardIndex)');
          }
        } else if (cardBounds != null) {
          cardBoundsList.add(cardBounds);
        }
      }
    }
    
    if (cardBoundsList.isEmpty) {
      if (LOGGING_SWITCH) {
        _logger.warning('🎬 _triggerFlashCardAnimation: No card bounds found for flashCard animation');
      }
      return null;
    }
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _triggerFlashCardAnimation: Found ${cardBoundsList.length} cards to flash');
    }
    
    // Mark action as processed
    Animations.markActionAsProcessed(actionName);
    
    // Create animation controller for 3 flashes (1500ms total: 500ms per flash)
    final duration = Animations.getAnimationDuration(AnimationType.flashCard);
    final curve = Animations.getAnimationCurve(AnimationType.flashCard);
    
    final controller = AnimationController(
      duration: duration,
      vsync: this,
    );
    
    final animation = CurvedAnimation(
      parent: controller,
      curve: curve,
    );
    
    // Store animation data with all card bounds (actionName used for overlay color per theme)
    _activeAnimations[actionName] = {
      'animationType': AnimationType.flashCard,
      'actionName': actionName,
      'cardBoundsList': cardBoundsList, // List of all card bounds to flash
      'controller': controller,
      'animation': animation,
    };
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 _triggerFlashCardAnimation: FlashCard animation stored, starting animation controller');
    }
    
    // Trigger rebuild to show animation
    if (mounted) {
      setState(() {});
    }
    
    // Start animation and return future that completes when animation finishes
    return controller.forward().then((_) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 _triggerFlashCardAnimation: FlashCard animation completed for $actionName');
      }
      
      // Animation complete - remove from active animations
      if (mounted) {
        _activeAnimations.remove(actionName);
        controller.dispose();
        setState(() {}); // Remove animation from overlay
      }
    }).catchError((error) {
      if (LOGGING_SWITCH) {
        _logger.error('🎬 _triggerFlashCardAnimation: Animation error for $actionName: $error');
      }
      if (mounted) {
        _activeAnimations.remove(actionName);
        controller.dispose();
      }
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
    final actionName = animData['actionName'] as String?;
    
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
    
    // For moveWithEmptySlot, we need to render empty slot(s) and the moving card
    if (animationType == AnimationType.moveWithEmptySlot) {
      final baseActionName = actionName != null ? Animations.extractBaseActionName(actionName) : null;
      final isReposition = baseActionName == 'draw_reposition';
      final isEmptyAtDestOnly = baseActionName == 'jack_swap_2'; // Second jack anim: empty at destination only
      
      List<Widget> stackChildren = [];
      // Empty slot at source (unless jack_swap_2: empty at dest only)
      if (!isEmptyAtDestOnly) {
        Widget emptySlotWidget = _buildBlankCardSlot(sourceSize);
        stackChildren.add(
          Positioned(
            left: localSourcePosition.dx,
            top: localSourcePosition.dy,
            child: emptySlotWidget,
          ),
        );
      }
      // Empty slot at destination: draw_reposition (both), or jack_swap_2 (dest only)
      if ((isReposition || isEmptyAtDestOnly) && localDestPosition != null && destSize != null) {
        Widget destEmptySlotWidget = _buildBlankCardSlot(destSize);
        stackChildren.add(
          Positioned(
            left: localDestPosition.dx,
            top: localDestPosition.dy,
            child: destEmptySlotWidget,
          ),
        );
      }
      
      // Add moving card animation
      stackChildren.add(
        // Moving card (animates from source to destination)
        AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              // Interpolate position from source to destination
              Offset cardPosition = localSourcePosition;
              Size cardSize = sourceSize;
              
              if (localDestPosition != null) {
                // Interpolate position
                cardPosition = Offset.lerp(localSourcePosition, localDestPosition, animation.value) ?? localSourcePosition;
                
                // Interpolate size if destination size is available
                if (destSize != null) {
                  cardSize = Size.lerp(sourceSize, destSize, animation.value) ?? sourceSize;
                }
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
              
              return Positioned(
                left: cardPosition.dx,
                top: cardPosition.dy,
                child: Opacity(
                  opacity: 1.0, // Fully visible during movement
                  child: cardWidget,
                ),
              );
            },
          ),
      );
      
      return Stack(
        clipBehavior: Clip.none,
        children: stackChildren,
      );
    }
    
    // Build card widget using actual CardWidget (for other animation types)
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // For moveCard animation, interpolate between source and destination positions
        // For other animations, just use source position
        Offset cardPosition = localSourcePosition;
        Size cardSize = sourceSize;
        
        if (animationType == AnimationType.moveCard && localDestPosition != null) {
          // Interpolate position
          cardPosition = Offset.lerp(localSourcePosition, localDestPosition, animation.value) ?? localSourcePosition;
          
          // Interpolate size if destination size is available
          if (destSize != null) {
            cardSize = Size.lerp(sourceSize, destSize, animation.value) ?? sourceSize;
          }
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
          
          // Opponent columns keep their padding; game board lives in middle column
          final opponentContent = Padding(
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
              phase,
              timerConfig,
              opponentIndex: displayIndex,
            ),
          );

          // Game board in middle column (index 1), or in the only column when there is a single opponent.
          // Game board height is intrinsic (as much as children require); pile widths stay within parent column.
          final bool isColumnWithGameBoard = displayIndex == 1 || entries.length == 1;
          if (isColumnWithGameBoard) {
            opponentWidgets.add(
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: opponentContent),
                    _buildGameBoard(),
                  ],
                ),
              ),
            );
          } else {
            opponentWidgets.add(
              Expanded(
                child: opponentContent,
              ),
            );
          }
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
        // Size so 4 cards fit in one row; 5th item (extra animation slot) wraps. Each child has Padding(right: cardPadding), so 4 cards use 4*cardWidth + 4*cardPadding.
        final cardPadding = availableWidth * 0.02;
        final cardWidth = CardDimensions.clampCardWidth((availableWidth - 4 * cardPadding) / 4);
        final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
        final cardDimensions = Size(cardWidth, cardHeight);
        final stackOffset = cardHeight * CardDimensions.STACK_OFFSET_PERCENTAGE;
        
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
              final stackWidget = Container(
                width: cardWidth,
                height: stackHeight,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
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
          // Collection stack: one key for the stack; all indices in that stack use same bounds (stack position)
          final collectionIndices = <int>{};
          for (int i = 0; i < cards.length; i++) {
            final c = cards[i];
            if (c != null && c is Map<String, dynamic>) {
              final cid = c['cardId']?.toString();
              if (cid != null && collectionRankCardIds.contains(cid)) {
                collectionIndices.add(i);
              }
            }
          }
          final firstCollectionIndex = collectionIndices.isEmpty ? null : collectionIndices.reduce((a, b) => a < b ? a : b);
          final keyForStack = firstCollectionIndex != null ? _getOrCreateCardKey('${playerId}_$firstCollectionIndex', 'opponent') : null;
          for (int i = 0; i <= cards.length; i++) {
            final keyString = '${playerId}_$i';
            final cardKey = (collectionIndices.contains(i) && keyForStack != null)
                ? keyForStack
                : _getOrCreateCardKey(keyString, 'opponent');
            _playScreenFunctions.updateOpponentCardBounds(playerId, i, cardKey, keyString: keyString);
          }
          _playScreenFunctions.clearMissingOpponentCardBounds(
            playerId,
            List.generate(cards.length + 1, (i) => i),
            maxIndex: cards.length,
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
    // Use dynamic border radius from SSOT to match card widgets
    final borderRadius = CardDimensions.calculateBorderRadius(dimensions);
    return SizedBox(
      width: dimensions.width,
      height: dimensions.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            // Background — same color as border
            Positioned.fill(
              child: Container(
                color: AppColors.accentColor,
              ),
            ),
            // Border overlay — use theme accent (green in Dutch/green preset) per THEME_SYSTEM.md
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: AppColors.accentColor,
                  width: 1,
                  style: BorderStyle.solid,
                ),
              ),
            ),
          ],
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

  /// Schedules removal of all selected-card overlays (opponent highlight + my hand selection) after 3 seconds.
  /// Cancels any existing schedule when called again.
  void _startSelectedOverlayClearTimer() {
    _selectedCardOverlayTimer?.cancel();
    _selectedCardOverlayTimer = Timer(const Duration(seconds: 3), () {
      _selectedCardOverlayTimer = null;
      if (!mounted) return;
      setState(() {
        _clickedCardId = null;
      });
      final currentState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final currentGameId = currentState['currentGameId']?.toString() ?? '';
      final games = currentState['games'] as Map<String, dynamic>? ?? {};
      final myHand = currentState['myHand'] as Map<String, dynamic>? ?? {};
      if (currentGameId.isNotEmpty && games.containsKey(currentGameId)) {
        final currentGame = Map<String, dynamic>.from(games[currentGameId]);
        currentGame['selectedCardIndex'] = -1;
        final updatedGames = Map<String, dynamic>.from(games);
        updatedGames[currentGameId] = currentGame;
        final updatedMyHand = Map<String, dynamic>.from(myHand);
        updatedMyHand['selectedIndex'] = -1;
        updatedMyHand['selectedCard'] = null;
        StateManager().updateModuleState('dutch_game', {
          ...currentState,
          'games': updatedGames,
          'myHand': updatedMyHand,
        });
      } else {
        final updatedMyHand = Map<String, dynamic>.from(myHand);
        updatedMyHand['selectedIndex'] = -1;
        updatedMyHand['selectedCard'] = null;
        StateManager().updateModuleState('dutch_game', {
          ...currentState,
          'myHand': updatedMyHand,
        });
      }
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
        _startSelectedOverlayClearTimer();

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

  /// Horizontal padding used by draw/discard pile (Padding.all(2) => 2 left + 2 right).
  static const double _gameBoardPileHorizontalPadding = 4;

  /// Card dimensions for game board piles: use full column width minus padding, clamped to max.
  static Size _gameBoardPileCardDimensions(double columnWidth) {
    final cardWidth = CardDimensions.clampCardWidth(columnWidth - _gameBoardPileHorizontalPadding);
    final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
    return Size(cardWidth, cardHeight);
  }

  Widget _buildGameBoard() {
    // Update game board height in state after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateGameBoardHeight();
    });
    
    return Container(
      key: _gameBoardKey,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Top row: match pot (full width). Bottom row: 2 cols — draw (left), discard (right).
          final gameboardRowWidth = constraints.maxWidth;
          final gameboardMaxHeight = constraints.maxHeight;
          if (LOGGING_SWITCH) {
            _logger.info('[GameBoard overflow] _buildGameBoard: constraints maxW=$gameboardRowWidth maxH=$gameboardMaxHeight');
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top: winning pot row (same conditions: practice hidden, tier/phase)
              _buildMatchPotRow(gameboardRowWidth),
              const SizedBox(height: 8),
              // Bottom: 2 columns — draw pile (left), discard pile (right)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => _buildDrawPile(availableWidth: c.maxWidth),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => _buildDiscardPile(availableWidth: c.maxWidth),
                    ),
                  ),
                ],
              ),
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

  /// Draw pile card size: scales with [availableWidth] (like opponent hand cards), clamped to [CardDimensions.MAX_CARD_WIDTH].
  Widget _buildDrawPile({double? availableWidth}) {
    if (LOGGING_SWITCH) {
      _logger.info('[GameBoard overflow] _buildDrawPile: availableWidth=$availableWidth');
    }
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
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final Size cardDimensions = availableWidth != null && availableWidth > 0
                    ? _gameBoardPileCardDimensions(availableWidth)
                    : CardDimensions.getUnifiedDimensions();
                if (LOGGING_SWITCH) {
                  _logger.info('[GameBoard overflow] _buildDrawPile: cardDimensions=${cardDimensions.width}x${cardDimensions.height} (with padding 2 total 4)');
                }
                Widget drawPileContent;
              
              if (drawPile.isEmpty) {
                // Empty draw pile - render placeholder. Key on card-sized SizedBox so animation bounds match card size.
                final emptyKey = _getOrCreateCardKey('draw_pile_empty', 'draw_pile');
                drawPileContent = SizedBox(
                  key: _drawPileKey,
                  width: cardDimensions.width,
                  height: cardDimensions.height,
                  child: CardWidget(
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
                  ),
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
                  key: _drawPileKey,
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

  /// Discard pile card size: scales with [availableWidth] (like opponent hand cards), clamped to [CardDimensions.MAX_CARD_WIDTH].
  Widget _buildDiscardPile({double? availableWidth}) {
    if (LOGGING_SWITCH) {
      _logger.info('[GameBoard overflow] _buildDiscardPile: availableWidth=$availableWidth');
    }
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
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) {
                final Size cardDimensions = availableWidth != null && availableWidth > 0
                    ? _gameBoardPileCardDimensions(availableWidth)
                    : CardDimensions.getUnifiedDimensions();
                
                if (!hasCards) {
                // Empty discard pile. Key on card-sized SizedBox so animation bounds match card size.
                final emptyKey = _getOrCreateCardKey('discard_pile_empty', 'discard_pile');
                return SizedBox(
                  key: _discardPileKey,
                  width: cardDimensions.width,
                  height: cardDimensions.height,
                  child: CardWidget(
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
                  ),
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
                key: _discardPileKey,
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

  /// Full-width row on top of the game board: "Winning pot: {amount} [icon]".
  /// Shown only when: not a practice game and user is not promotional tier.
  /// Amount vs '—' by isGameActive and gamePhase when shown.
  /// [rowWidth] is the full game board width (used to scale font/icon).
  Widget _buildMatchPotRow(double rowWidth) {
    final dutchGameState = _getPrevStateDutchGame();
    final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final matchPot = centerBoard['matchPot'] as int? ?? 0;
    final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'waiting';
    final isGameActive = dutchGameState['isGameActive'] ?? false;
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';

    // Only show match pot if not a practice game
    final isPracticeGame = currentGameId.startsWith('practice_room_');
    if (isPracticeGame) {
      return const SizedBox.shrink();
    }

    // Hide match pot row for promotional tier (free play - no coins involved)
    final userStats = dutchGameState['userStats'] as Map<String, dynamic>?;
    final subscriptionTier = userStats?['subscription_tier']?.toString() ?? 'promotional';
    if (subscriptionTier == 'promotional') {
      return const SizedBox.shrink();
    }

    final shouldShowPot = isGameActive && gamePhase != 'waiting';

    // Winning pot row: 2x size for text/icon; use theme gold (accentColor2)
    final fontSize = (rowWidth * 0.05).clamp(20.0, 40.0);
    final iconSize = (rowWidth * 0.05).clamp(25.0, 58.0);
    if (LOGGING_SWITCH) {
      _logger.info('[GameBoard overflow] _buildMatchPotRow: rowWidth=$rowWidth fontSize=$fontSize iconSize=$iconSize');
    }

    // Dedicated gold so it is not overridden by theme (e.g. Dutch theme accentColor2 is green)
    const potColor = AppColors.matchPotGold;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: rowWidth),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          spacing: 4,
          children: [
            Text(
              'Winning pot: ',
              style: AppTextStyles.headingLarge().copyWith(
                color: shouldShowPot ? potColor : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '${shouldShowPot ? matchPot.toString() : '—'} ',
                  style: AppTextStyles.headingLarge().copyWith(
                    color: shouldShowPot ? potColor : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: fontSize,
                  ),
                ),
                Icon(
                  Icons.monetization_on,
                  size: iconSize,
                  color: potColor,
                ),
              ],
            ),
          ],
        ),
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
    
    // My hand section: column with (1) header row = You + status chip (+ optional timer/buttons), (2) full-width row = cards only
    return Container(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppPadding.mediumPadding.left),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: You (avatar + label) and status chip (and optional Call Final Round, timer)
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
                if (isGameActive && isMyTurn && (playerStatus == 'same_rank_window') && !finalRoundActive && !hasPlayerCalledFinalRound && !_callFinalRoundTappedPending) ...[
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
                ] else if (finalRoundActive || _callFinalRoundTappedPending) ...[
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
                          (finalRoundActive && finalRoundCalledBy == _getCurrentUserId())
                              ? Icons.flag
                              : Icons.flag_outlined,
                          size: 12,
                          color: AppColors.textOnAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          (finalRoundActive && finalRoundCalledBy == _getCurrentUserId())
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
            // Row 2: cards only, taking all available horizontal space
            if (cards.isEmpty)
              _buildMyHandEmptyHand()
            else
              SizedBox(
                width: double.infinity,
                child: _buildMyHandCardsGrid(cards, cardsToPeek, selectedIndex),
              ),
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
            // Use effective width for card sizing; update 2s after layout change to avoid jitter on resize
            final widthForSizing = _myHandEffectiveWidth ?? containerWidth;
            if (_myHandEffectiveWidth == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _myHandEffectiveWidth == null) {
                  setState(() => _myHandEffectiveWidth = containerWidth);
                }
              });
            } else if ((_myHandEffectiveWidth! - containerWidth).abs() > 0.5) {
              _myHandResizeDelayTimer?.cancel();
              final newWidth = containerWidth;
              _myHandResizeDelayTimer = Timer(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() {
                    _myHandEffectiveWidth = newWidth;
                    _myHandResizeDelayTimer = null;
                  });
                }
              });
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
            
            // Size cards so all slots fit in one row (no wrapping). Total slots = cards + extra invisible + leading spacer.
            const double kMinCardWidth = 28.0;
            final int totalSlotCount = cards.length + 2;
            final cardPadding = widthForSizing * 0.02;
            final slotWidth = widthForSizing / totalSlotCount;
            final rawCardWidth = slotWidth - cardPadding;
            final cardWidth = rawCardWidth.clamp(kMinCardWidth, CardDimensions.MAX_CARD_WIDTH);
            final cardHeight = cardWidth / CardDimensions.CARD_ASPECT_RATIO;
            final cardDimensions = Size(cardWidth, cardHeight);
            final stackOffset = cardHeight * CardDimensions.STACK_OFFSET_PERCENTAGE;
            
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
                  child: _buildBlankCardSlot(cardDimensions),
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
              // One key for the whole stack (on the container) so bounds = stack position for all collection indices
              List<Widget> orderedCollectionWidgets = [];
              for (var collectionCard in myCollectionRankCards) {
                if (collectionCard is Map<String, dynamic>) {
                  final collectionCardId = collectionCard['cardId']?.toString();
                  if (collectionCardId != null && collectionRankWidgets.containsKey(collectionCardId)) {
                    // No key on inner cards; stack container holds the key for bounds
                    final collectionCardWidget = _buildMyHandCardWidget(
                      collectionCard,
                      false,
                      false,
                      false,
                      index,
                      collectionCard,
                      null, // no key - stack container has the key for bounds
                      cardDimensions,
                      currentPlayerStatus: currentPlayerStatusForGlow,
                    );
                    orderedCollectionWidgets.add(collectionCardWidget);
                  }
                }
              }
              
              final cardWidth = cardDimensions.width;
              final stackHeight = cardHeight + (orderedCollectionWidgets.length - 1) * stackOffset;
              final stackKey = _getOrCreateCardKey('${_getCurrentUserId()}_$index', 'my_hand');
              
              final stackWidget = Container(
                key: stackKey,
                width: cardWidth,
                height: stackHeight,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
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
                  padding: EdgeInsets.only(
                    right: cardPadding,
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
                  child: _buildBlankCardSlot(cardDimensions),
                ),
              ),
            ),
          );
          
          // Leading spacer: one card width + margin (same as each card slot) so it stays in sync with card sizing
          final leadingSlotWidth = cardDimensions.width + cardPadding;
          final totalRowWidth = totalSlotCount * (cardDimensions.width + cardPadding);
          // Use at least container width so Center can center the row when it's narrower (e.g. after resize)
          final rowContainerWidth = totalRowWidth < containerWidth ? containerWidth : totalRowWidth;
          final rowWidget = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: rowContainerWidth,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: leadingSlotWidth),
                    ...cardWidgets,
                  ],
                ),
              ),
            ),
          );
          
          // Update card bounds after build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final playerId = _getCurrentUserId();
            // Collection stack: one key for the stack; all indices in that stack use same bounds (stack position)
            final collectionIndices = <int>{};
            for (int i = 0; i < cards.length; i++) {
              final c = cards[i];
              if (c != null && c is Map<String, dynamic>) {
                final cid = c['cardId']?.toString();
                if (cid != null && collectionRankCardIds.contains(cid)) {
                  collectionIndices.add(i);
                }
              }
            }
            final firstCollectionIndex = collectionIndices.isEmpty ? null : collectionIndices.reduce((a, b) => a < b ? a : b);
            final keyForStack = firstCollectionIndex != null ? _getOrCreateCardKey('${playerId}_$firstCollectionIndex', 'my_hand') : null;
            for (int i = 0; i <= cards.length; i++) {
              final keyString = '${playerId}_$i';
              final cardKey = (collectionIndices.contains(i) && keyForStack != null)
                  ? keyForStack
                  : _getOrCreateCardKey(keyString, 'my_hand');
              _playScreenFunctions.updateMyHandCardBounds(i, cardKey, keyString: keyString);
            }
            _playScreenFunctions.clearMissingMyHandCardBounds(
              List.generate(cards.length + 1, (i) => i),
              maxIndex: cards.length,
            );
          });
          
          return rowWidget;
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
        _callFinalRoundTappedPending = true; // Show "Final Round Active" immediately
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
          _callFinalRoundTappedPending = false; // Restore button on failure
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
      _startSelectedOverlayClearTimer();
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


  Widget _buildMyHandCardWidget(Map<String, dynamic> card, bool isSelected, bool isDrawnCard, bool isCollectionRankCard, int index, Map<String, dynamic> cardMap, GlobalKey? cardKey, Size cardDimensions, {String? currentPlayerStatus}) {
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
