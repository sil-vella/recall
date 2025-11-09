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

    // Load cards from my hand
    final myHand = recallGameState['myHand'] as Map<String, dynamic>? ?? {};
    final myHandCards = myHand['cards'] as List<dynamic>? ?? [];
    for (final card in myHandCards) {
      if (card != null && card is Map<String, dynamic>) {
        final cardId = card['cardId']?.toString();
        if (cardId != null) {
          _cardModels[cardId] = CardModel.fromMap(card);
        }
      }
    }

    // Load cards from opponents
    final opponentsPanel =
        recallGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    for (final opponent in opponents) {
      if (opponent is Map<String, dynamic>) {
        final hand = opponent['hand'] as List<dynamic>? ?? [];
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

    // Load card from discard pile
    final centerBoard =
        recallGameState['centerBoard'] as Map<String, dynamic>? ?? {};
    final topDiscard = centerBoard['topDiscard'] as Map<String, dynamic>?;
    if (topDiscard != null) {
      final cardId = topDiscard['cardId']?.toString();
      if (cardId != null) {
        _cardModels[cardId] = CardModel.fromMap(topDiscard);
      }
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

  /// Detect card movements and start animations
  void _detectAndAnimate() {
    _logger.info('🎬 CardAnimationLayer: Detecting movements (second frame)', isOn: LOGGING_SWITCH);
    
    // Note: Previous positions were already saved in the first postFrameCallback
    final currentCount = _animationManager.positionTracker.positionCount;
    _logger.info('🎬 CardAnimationLayer: Current positions: $currentCount', isOn: LOGGING_SWITCH);

    // Load updated card models
    _loadCardModels();

    // Detect movements and create animations
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
      animation.controller.addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          _logger.info('🎬 CardAnimationLayer: Animation completed for card ${animation.cardId}', isOn: LOGGING_SWITCH);
          _animationManager.completeAnimation(animation.cardId);
          _updateAnimationState();
        }
      });
    }

    if (animationsToStart.isNotEmpty) {
      _updateAnimationState();
    }
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
        // Detect movements after state update
        // Use double postFrameCallback to ensure all widget positions are registered first
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // First frame: save current positions as previous, then wait for next frame
          if (!_isDetecting) {
            _isDetecting = true;
            _animationManager.saveCurrentAsPrevious();
            final previousCount = _animationManager.positionTracker.positionCount;
            _logger.info('🎬 CardAnimationLayer: Saved ${previousCount} previous positions (first frame)', isOn: LOGGING_SWITCH);
            
            // Second frame: detect movements after all positions are registered
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _detectAndAnimate();
              _isDetecting = false;
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

