import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../managers/card_animation_manager.dart';
import '../../../models/card_model.dart';
import '../../../widgets/card_widget.dart';
import '../../../models/card_display_config.dart';
import '../../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = true;

/// Overlay widget that handles card movement animations
/// 
/// This widget sits above the game content and animates cards
/// when they move between locations (hands, discard pile, draw pile, etc.)
class CardAnimationLayer extends StatefulWidget {
  const CardAnimationLayer({Key? key}) : super(key: key);

  @override
  State<CardAnimationLayer> createState() => _CardAnimationLayerState();
}

class _CardAnimationLayerState extends State<CardAnimationLayer>
    with TickerProviderStateMixin {
  final Logger _logger = Logger();
  final CardAnimationManager _animationManager = CardAnimationManager();
  final Map<String, CardModel> _cardModels = {};
  bool _hasActiveAnimations = false;
  bool _isDetecting = false; // Flag to prevent multiple simultaneous detections
  final GlobalKey _stackKey = GlobalKey(); // Key to get Stack's RenderBox for coordinate conversion

  @override
  void initState() {
    super.initState();
    _loadCardModels();
  }

  @override
  void dispose() {
    _animationManager.clearAllAnimations();
    super.dispose();
  }

  /// Load card models from current game state
  void _loadCardModels() {
    final recallGameState =
        StateManager().getModuleState<Map<String, dynamic>>('recall_game') ??
            {};

    _logger.info('🎬 CardAnimationLayer: Loading card models', isOn: LOGGING_SWITCH);
    _cardModels.clear();

    // Get current game ID and games map
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    final games = recallGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};

    // Load cards from my hand
    final myHandCards = currentGame['myHandCards'] as List<dynamic>? ?? [];
    for (final card in myHandCards) {
      if (card != null && card is Map<String, dynamic>) {
        final cardId = card['cardId']?.toString();
        if (cardId != null) {
          _cardModels[cardId] = CardModel.fromMap(card);
        }
      }
    }

    // Load cards from opponents
    final allPlayers = gameState['players'] as List<dynamic>? ?? [];
    final loginState = StateManager().getModuleState<Map<String, dynamic>>('login') ?? {};
    final currentUserId = loginState['userId']?.toString() ?? '';
    
    for (final player in allPlayers) {
      if (player is Map<String, dynamic> && player['id']?.toString() != currentUserId) {
        final hand = player['hand'] as List<dynamic>? ?? [];
        for (final card in hand) {
          if (card != null && card is Map<String, dynamic>) {
            final cardId = card['cardId']?.toString();
            if (cardId != null) {
              _cardModels[cardId] = CardModel.fromMap(card);
            }
          }
        }
      }
    }

    // Load card from discard pile (last card)
    final discardPile = gameState['discardPile'] as List<dynamic>? ?? [];
    if (discardPile.isNotEmpty) {
      final topDiscard = discardPile.last;
      if (topDiscard != null && topDiscard is Map<String, dynamic>) {
        final cardId = topDiscard['cardId']?.toString();
        if (cardId != null) {
          _cardModels[cardId] = CardModel.fromMap(topDiscard);
        }
      }
    }

    // Load card from draw pile (top card - last card in draw pile)
    // NOTE: drawPile contains ID-only cards (maps with {'cardId': 'xxx', 'suit': '?', 'rank': '?', 'points': 0})
    final drawPile = gameState['drawPile'] as List<dynamic>? ?? [];
    final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];
    final drawPileCardIds = drawPile.map((c) {
      if (c is Map<String, dynamic>) return c['cardId']?.toString() ?? 'unknown';
      return c.toString();
    }).toList();
    _logger.info('🎬 CardAnimationLayer: _loadCardModels - DrawPile has ${drawPile.length} cards, IDs: $drawPileCardIds', isOn: LOGGING_SWITCH);
    
    if (drawPile.isNotEmpty) {
      final topDrawCard = drawPile.last;
      if (topDrawCard != null) {
        // Extract cardId from the ID-only card map
        String? topDrawCardId;
        if (topDrawCard is Map<String, dynamic>) {
          topDrawCardId = topDrawCard['cardId']?.toString();
        } else if (topDrawCard is String) {
          // Fallback: if it's a string, use it directly
          topDrawCardId = topDrawCard;
        }
        
        if (topDrawCardId != null) {
          // Find full card data in original deck
          for (var card in originalDeck) {
            if (card is Map<String, dynamic> && card['cardId']?.toString() == topDrawCardId) {
              final cardId = card['cardId']?.toString();
              if (cardId != null) {
                _cardModels[cardId] = CardModel.fromMap(card);
                _logger.info('🎬 CardAnimationLayer: Loaded draw pile card model: $cardId', isOn: LOGGING_SWITCH);
              }
              break;
            }
          }
        }
      }
    } else {
      _logger.info('🎬 CardAnimationLayer: DrawPile is empty, no card to load', isOn: LOGGING_SWITCH);
    }

    // Load cards from cardsToPeek (peeked cards have full data)
    final cardsToPeek = recallGameState['myCardsToPeek'] as List<dynamic>? ?? [];
    for (final card in cardsToPeek) {
      if (card is Map<String, dynamic>) {
        final cardId = card['cardId']?.toString();
        if (cardId != null) {
          _cardModels[cardId] = CardModel.fromMap(card);
        }
      }
    }
    
    _logger.info('🎬 CardAnimationLayer: Loaded ${_cardModels.length} card models', isOn: LOGGING_SWITCH);
  }

  /// Validate and clean up positions based on current game state
  /// Removes positions for cards that are no longer in hands (they were played)
  /// Also ensures cards that should be in hands are properly tracked for animation detection
  void _validateAndCleanupPositions() {
    final recallGameState =
        StateManager().getModuleState<Map<String, dynamic>>('recall_game') ??
            {};

    // Get current game ID and games map
    final currentGameId = recallGameState['currentGameId']?.toString() ?? '';
    final games = recallGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};

    // Collect all card IDs that are actually in hands, organized by location
    final cardsInMyHand = <String>{};
    final cardsInOpponentHands = <String>{};

    // Get my hand cards
    final myHandCards = currentGame['myHandCards'] as List<dynamic>? ?? [];
    for (final card in myHandCards) {
      if (card != null && card is Map<String, dynamic>) {
        final cardId = card['cardId']?.toString();
        if (cardId != null) {
          cardsInMyHand.add(cardId);
        }
      }
    }

    // Get opponent hand cards
    final allPlayers = gameState['players'] as List<dynamic>? ?? [];
    for (final player in allPlayers) {
      final hand = player['hand'] as List<dynamic>? ?? [];
      for (final card in hand) {
        if (card != null && card is Map<String, dynamic>) {
          final cardId = card['cardId']?.toString();
          if (cardId != null) {
            cardsInOpponentHands.add(cardId);
          }
        }
      }
    }

    final allCardsInHands = cardsInMyHand.union(cardsInOpponentHands);

    // Remove positions for cards that are no longer in hands
    final currentPositions = _animationManager.positionTracker.getAllPositions();
    for (final entry in currentPositions.entries) {
      final cardId = entry.key;
      final position = entry.value;

      // If card is registered at a hand location but not actually in any hand, remove it
      if ((position.location == 'my_hand' || position.location == 'opponent_hand') &&
          !allCardsInHands.contains(cardId)) {
        _logger.info('🎬 CardAnimationLayer: Removing position for card $cardId at ${position.location} (card no longer in hand)', isOn: LOGGING_SWITCH);
        _animationManager.positionTracker.removeCardPosition(cardId);
      }
    }

    // Check for cards that are in hands but not yet registered
    // These are likely newly drawn cards that haven't been registered by widgets yet
    // We'll let the detection logic handle them when they appear
    final previousPositions = _animationManager.positionTracker.getAllPreviousPositions();
    for (final cardId in allCardsInHands) {
      if (!currentPositions.containsKey(cardId) && !previousPositions.containsKey(cardId)) {
        // Card is in hand but not in previous or current positions
        // This means it was just drawn and hasn't been registered yet
        // The detection logic will handle it when it appears in current positions
        _logger.info('🎬 CardAnimationLayer: Card $cardId is in hand but not yet registered (will be detected when widget registers it)', isOn: LOGGING_SWITCH);
      }
    }
  }

  /// Detect card movements and start animations
  /// 
  /// This method:
  /// - Only tracks hand positions (my_hand, opponent_hand) - these are registered by widgets
  /// - Uses cached static positions for draw_pile and discard_pile (cached once at match start)
  /// - Detects movements by comparing previous hand positions with current hand positions
  /// - For cards that appeared in hands: uses cached draw_pile position as source
  /// - For cards that disappeared from hands: uses cached discard_pile position as destination
  void _detectAndAnimate() {
    _logger.info('🎬 CardAnimationLayer: Detecting movements', isOn: LOGGING_SWITCH);
    
    // NOTE: Previous positions were saved by RecallGameStateUpdater (SSOT) BEFORE the state update
    // Only hand positions are saved (static positions remain cached)
    // We only need to detect movements after widgets have registered their new positions
    final currentCount = _animationManager.positionTracker.positionCount;
    _logger.info('🎬 CardAnimationLayer: Current positions: $currentCount (hand positions only, static positions are cached)', isOn: LOGGING_SWITCH);
    
    // Log previous positions for debugging
    final previousPositions = _animationManager.positionTracker.getAllPreviousPositions();
    _logger.info('🎬 CardAnimationLayer: Previous positions count: ${previousPositions.length} (hand positions only)', isOn: LOGGING_SWITCH);
    for (final entry in previousPositions.entries) {
      _logger.info('🎬 CardAnimationLayer:   Previous: ${entry.key} at ${entry.value.location}', isOn: LOGGING_SWITCH);
    }

    // Load updated card models
    _loadCardModels();

    // CRITICAL: Validate and clean up positions before detecting movements
    // Remove positions for cards that are no longer in hands (they were played)
    // This ensures they are correctly detected as "disappeared from hand" and animate to discard_pile
    _validateAndCleanupPositions();

    // Detect movements and create animations
    // detectMovements() will use cached static positions for draw_pile and discard_pile
    final animationsToStart =
        _animationManager.detectAndCreateAnimations(this, _cardModels);
    
    _logger.info('🎬 CardAnimationLayer: Detected ${animationsToStart.length} movements to animate', isOn: LOGGING_SWITCH);

        // Start all animations
        for (final animation in animationsToStart) {
          _logger.info('🎬 CardAnimationLayer: Starting animation for card ${animation.cardId}', isOn: LOGGING_SWITCH);
          _logger.info('🎬 CardAnimationLayer:   From: ${animation.startPosition}', isOn: LOGGING_SWITCH);
          _logger.info('🎬 CardAnimationLayer:   To: ${animation.endPosition}', isOn: LOGGING_SWITCH);
          
          _animationManager.startAnimation(animation);

          // Set up completion listener
          _setupAnimationCompletionListener(animation);
        }

    if (animationsToStart.isNotEmpty) {
      _updateAnimationState();
    }
  }

      /// Set up completion listener for an animation
      void _setupAnimationCompletionListener(CardAnimation animation) {
        animation.controller.addStatusListener((status) {
          if (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) {
            _logger.info('🎬 CardAnimationLayer: Animation completed for card ${animation.cardId}', isOn: LOGGING_SWITCH);
            _animationManager.completeAnimation(animation.cardId);
            _updateAnimationState();
          }
        });
      }

      /// Update animation state and trigger rebuild
      void _updateAnimationState() {
        final activeAnimations = _animationManager.getActiveAnimations();
        final hasActive = activeAnimations.isNotEmpty;

        if (hasActive != _hasActiveAnimations) {
          setState(() {
            _hasActiveAnimations = hasActive;
          });
        } else if (hasActive) {
          // Force rebuild to update animation values
          setState(() {});
        }
      }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // CRITICAL: Do NOT save positions here - the SSOT (RecallGameStateUpdater) 
        // saves positions BEFORE state updates. We only need to detect movements
        // after widgets have registered their new positions.
        // Use multiple postFrameCallbacks to ensure all widget positions are registered first
        // Widgets like MyHandWidget and OpponentsPanelWidget also use addPostFrameCallback 
        // to register positions, so we need to wait multiple frames to ensure all 
        // registrations complete, especially for opponent cards which may take longer
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDetecting) {
            _isDetecting = true;
            
            // Wait multiple frames to ensure ALL widgets have registered their positions
            // Frame 1: State update propagates, widgets start rebuilding
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Frame 2: Widgets finish building, position registrations scheduled
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // Frame 3: Most position registrations complete
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  // Frame 4: All position registrations should be complete now
                  // This extra frame helps ensure opponent cards are registered
                  _detectAndAnimate();
                  _isDetecting = false;
                });
              });
            });
          }
        });

        // Get active animations
        final activeAnimations = _animationManager.getActiveAnimations();

        // If no active animations, return empty widget that doesn't block interactions
        if (activeAnimations.isEmpty) {
          return const SizedBox.shrink();
        }

        // Render animated cards in overlay
        // Use Positioned.fill to ensure Stack fills the entire screen
        return Positioned.fill(
          child: IgnorePointer(
            // Allow interactions to pass through when not animating
            ignoring: false, // We want to block interactions during animation
            child: Stack(
              key: _stackKey,
              children: activeAnimations.values.map((animation) {
                return AnimatedBuilder(
                  animation: animation.controller,
                  builder: (context, child) {
                    // Get the RenderBox of the Stack to convert global to local coordinates
                    final stackRenderBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
                    if (stackRenderBox == null) {
                      // Stack not yet rendered, return empty widget
                      return const SizedBox.shrink();
                    }
                    
                    // Convert global coordinates to local coordinates relative to Stack
                    final globalPosition = animation.positionAnimation.value;
                    final localPosition = stackRenderBox.globalToLocal(globalPosition);
                    
                    _logger.info('🎬 CardAnimationLayer: Rendering animation for ${animation.cardId} at global (${globalPosition.dx.toStringAsFixed(1)}, ${globalPosition.dy.toStringAsFixed(1)}) -> local (${localPosition.dx.toStringAsFixed(1)}, ${localPosition.dy.toStringAsFixed(1)}), opacity: ${animation.opacityAnimation.value.toStringAsFixed(2)}', isOn: LOGGING_SWITCH);
                    
                    return Positioned(
                      left: localPosition.dx,
                      top: localPosition.dy,
                      child: Opacity(
                        opacity: animation.opacityAnimation.value,
                        child: SizedBox(
                          width: animation.widthAnimation.value,
                          height: animation.heightAnimation.value,
                          child: RepaintBoundary(
                            child: CardWidget(
                              card: animation.card,
                              dimensions: Size(
                                animation.widthAnimation.value,
                                animation.heightAnimation.value,
                              ),
                              config: CardDisplayConfig.forDiscardPile(),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

