import 'dart:async';
import 'package:flutter/material.dart';
import '../../../utils/card_animation_detector.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../widgets/card_widget.dart';
import '../../../utils/card_dimensions.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';

const bool LOGGING_SWITCH = true; // Enabled for testing and debugging

/// Full-screen overlay widget that renders animated cards
class CardAnimationLayer extends StatefulWidget {
  final GlobalKey? stackKey; // Optional key to the parent Stack for exact positioning
  
  const CardAnimationLayer({Key? key, this.stackKey}) : super(key: key);

  @override
  State<CardAnimationLayer> createState() => CardAnimationLayerState();
}

class CardAnimationLayerState extends State<CardAnimationLayer> with TickerProviderStateMixin {
  final Logger _logger = Logger();
  
  /// Map of cardId -> AnimationController for active animations
  final Map<String, AnimationController> _animationControllers = {};
  
  /// Map of cardId -> Animation<Offset> for position animations
  final Map<String, Animation<Offset>> _positionAnimations = {};
  
  /// Map of cardId -> Animation<Size> for size animations (optional)
  final Map<String, Animation<Size>> _sizeAnimations = {};
  
  /// Map of cardId -> CardAnimation for active animations
  final Map<String, CardAnimation> _activeAnimations = {};
  
  /// CardAnimationDetector instance to listen for animation triggers
  final CardAnimationDetector _animationDetector = CardAnimationDetector();

  @override
  void initState() {
    super.initState();
    // Listen to animation triggers from detector
    _animationDetector.animationTriggers.addListener(_onAnimationTriggersChanged);
  }

  @override
  void dispose() {
    // Remove listener
    _animationDetector.animationTriggers.removeListener(_onAnimationTriggersChanged);
    
    // Dispose all animation controllers
    for (final controller in _animationControllers.values) {
      controller.dispose();
    }
    _animationControllers.clear();
    _positionAnimations.clear();
    _sizeAnimations.clear();
    _activeAnimations.clear();
    super.dispose();
  }

  /// Handle animation triggers from detector
  void _onAnimationTriggersChanged() {
    final animations = _animationDetector.animationTriggers.value;
    if (animations == null || animations.isEmpty) return;
    
    _logger.info('🎬 CardAnimationLayer: Received ${animations.length} animations', isOn: LOGGING_SWITCH);
    
    // Start all animations
    for (final animation in animations) {
      _startAnimation(animation);
    }
  }
  
  /// Public method to add animations (for direct calls if needed)
  void addAnimations(List<CardAnimation> animations) {
    if (animations.isEmpty) return;
    
    _logger.info('🎬 CardAnimationLayer: Adding ${animations.length} animations directly', isOn: LOGGING_SWITCH);
    
    for (final animation in animations) {
      _startAnimation(animation);
    }
  }

  /// Start a new animation
  void _startAnimation(CardAnimation animation) {
    // Skip if animation already active for this cardId
    if (_activeAnimations.containsKey(animation.cardId)) {
      _logger.info('🎬 CardAnimationLayer: Animation already active for ${animation.cardId}, skipping', isOn: LOGGING_SWITCH);
      return;
    }
    
    _logger.info('🎬 CardAnimationLayer: Starting animation for ${animation.cardId}: ${animation.type}', isOn: LOGGING_SWITCH);
    
    // Create animation controller
    final controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    // Create position animation
    final positionTween = Tween<Offset>(
      begin: _convertToStackCoordinates(animation.startPosition.position),
      end: _convertToStackCoordinates(animation.endPosition.position),
    );
    
    final positionAnimation = positionTween.animate(
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
      ),
    );
    
    // Create size animation (optional - animate if sizes differ)
    Animation<Size>? sizeAnimation;
    if (animation.startPosition.size != animation.endPosition.size) {
      final sizeTween = Tween<Size>(
        begin: animation.startPosition.size,
        end: animation.endPosition.size,
      );
      sizeAnimation = sizeTween.animate(
        CurvedAnimation(
          parent: controller,
          curve: Curves.easeOutCubic,
        ),
      );
    }
    
    // Store animations
    _animationControllers[animation.cardId] = controller;
    _positionAnimations[animation.cardId] = positionAnimation;
    if (sizeAnimation != null) {
      _sizeAnimations[animation.cardId] = sizeAnimation;
    }
    _activeAnimations[animation.cardId] = animation;
    
    // Trigger rebuild to show animated card
    if (mounted) {
      setState(() {
        _logger.info('🎬 CardAnimationLayer: setState called for ${animation.cardId}, active animations: ${_activeAnimations.length}', isOn: LOGGING_SWITCH);
      });
    }
    
    // Listen for animation completion
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _completeAnimation(animation.cardId);
      }
    });
    
    // Start animation
    controller.forward();
  }

  /// Convert global coordinates to Stack-relative coordinates
  /// Cards report positions in global screen coordinates (relative to entire screen)
  /// We need to convert to Stack-relative coordinates (relative to Stack widget)
  Offset _convertToStackCoordinates(Offset globalPosition) {
    RenderBox? stackRenderBox;
    
    // Try to use the provided Stack key first (most accurate - exact screen position)
    if (widget.stackKey != null) {
      final stackContext = widget.stackKey!.currentContext;
      if (stackContext != null) {
        stackRenderBox = stackContext.findRenderObject() as RenderBox?;
        if (stackRenderBox != null) {
          _logger.info('🎬 CardAnimationLayer: Using Stack key for coordinate conversion', isOn: LOGGING_SWITCH);
        }
      }
    }
    
    // Fallback: use this widget's RenderBox (should be the Stack since we return Stack directly)
    if (stackRenderBox == null) {
      stackRenderBox = context.findRenderObject() as RenderBox?;
      if (stackRenderBox != null) {
        _logger.info('🎬 CardAnimationLayer: Using widget RenderBox for coordinate conversion', isOn: LOGGING_SWITCH);
      }
    }
    
    if (stackRenderBox == null) {
      _logger.info('🎬 CardAnimationLayer: Cannot convert coordinates - stackRenderBox is null, using global position', isOn: LOGGING_SWITCH);
      return globalPosition;
    }
    
    // Get the Stack's exact position in global screen coordinates
    // This tells us where the Stack is positioned on the screen
    final stackGlobalPosition = stackRenderBox.localToGlobal(Offset.zero);
    final stackSize = stackRenderBox.size;
    
    // Convert global position to Stack-relative position
    // Subtract the Stack's global position from the card's global position
    final converted = Offset(
      globalPosition.dx - stackGlobalPosition.dx,
      globalPosition.dy - stackGlobalPosition.dy,
    );
    
    _logger.info('🎬 CardAnimationLayer: Coordinate conversion - card global: (${globalPosition.dx.toStringAsFixed(1)}, ${globalPosition.dy.toStringAsFixed(1)}), stack global: (${stackGlobalPosition.dx.toStringAsFixed(1)}, ${stackGlobalPosition.dy.toStringAsFixed(1)}), stack size: (${stackSize.width.toStringAsFixed(1)}, ${stackSize.height.toStringAsFixed(1)}), stack-relative: (${converted.dx.toStringAsFixed(1)}, ${converted.dy.toStringAsFixed(1)})', isOn: LOGGING_SWITCH);
    
    return converted;
  }

  /// Handle animation completion
  void _completeAnimation(String cardId) {
    _logger.info('🎬 CardAnimationLayer: Animation completed for $cardId', isOn: LOGGING_SWITCH);
    
    // Cleanup after a short delay to allow final frame to render
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _cleanupAnimation(cardId);
      }
    });
  }

  /// Cleanup completed animation
  void _cleanupAnimation(String cardId) {
    final controller = _animationControllers.remove(cardId);
    _positionAnimations.remove(cardId);
    _sizeAnimations.remove(cardId);
    _activeAnimations.remove(cardId);
    
    controller?.dispose();
    
    _logger.info('🎬 CardAnimationLayer: Cleaned up animation for $cardId', isOn: LOGGING_SWITCH);
    
    if (mounted) {
      setState(() {});
    }
  }

  /// Build empty slot widget (matches unified_game_board_widget style)
  Widget _buildEmptySlot(Size dimensions) {
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

  /// Get card data for animation
  CardModel _getCardData(String cardId, bool showFaceUp) {
    // Try to get full card data from game state
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    
    // Check in originalDeck or games map
    final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
    final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
    final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
    final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
    final originalDeck = gameData['original_deck'] as Map<String, dynamic>? ?? {};
    
    // Try to find card in original deck
    if (originalDeck.containsKey(cardId)) {
      final cardData = originalDeck[cardId] as Map<String, dynamic>?;
      if (cardData != null) {
        return CardModel.fromMap(cardData);
      }
    }
    
    // If not found or showFaceUp is false, create minimal card (shows back)
    if (!showFaceUp) {
      return CardModel(
        cardId: cardId,
        rank: '?',
        suit: '?',
        points: 0,
        isFaceDown: true,
      );
    }
    
    // Try to find in myHand or opponentsPanel
    final myHand = dutchGameState['myHand'] as Map<String, dynamic>? ?? {};
    final myHandCards = myHand['cards'] as List<dynamic>? ?? [];
    for (final card in myHandCards) {
      if (card is Map<String, dynamic> && card['cardId']?.toString() == cardId) {
        return CardModel.fromMap(card);
      }
    }
    
    final opponentsPanel = dutchGameState['opponentsPanel'] as Map<String, dynamic>? ?? {};
    final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
    for (final opponent in opponents) {
      if (opponent is Map<String, dynamic>) {
        final hand = opponent['hand'] as List<dynamic>? ?? [];
        for (final card in hand) {
          if (card is Map<String, dynamic> && card['cardId']?.toString() == cardId) {
            return CardModel.fromMap(card);
          }
        }
      }
    }
    
    // Fallback: create minimal card
    return CardModel(
      cardId: cardId,
      rank: '?',
      suit: '?',
      points: 0,
      isFaceDown: !showFaceUp,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_activeAnimations.isEmpty) {
      return const SizedBox.shrink();
    }
    
    _logger.info('🎬 CardAnimationLayer: Building with ${_activeAnimations.length} active animations', isOn: LOGGING_SWITCH);
    
    // Get screen size to ensure full coverage
    final screenSize = MediaQuery.of(context).size;
    _logger.info('🎬 CardAnimationLayer: Screen size: ${screenSize.width}x${screenSize.height}', isOn: LOGGING_SWITCH);
    
    // Use Positioned.fill to fill the entire Stack area
    // This works regardless of Stack constraints (even with unbounded height)
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true, // Ignore pointer events so they pass through to widgets below
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Debug: Add semi-transparent overlay to verify layer is visible (uncomment to test)
            // Positioned.fill(
            //   child: Container(
            //     color: Colors.red.withOpacity(0.1),
            //     child: Center(
            //       child: Text(
            //         'Animation Layer: ${_activeAnimations.length} animations',
            //         style: TextStyle(color: Colors.red, fontSize: 20),
            //       ),
            //     ),
            //   ),
            // ),
            // Render empty slots based on animation type
            ..._activeAnimations.entries.expand((entry) {
              final animation = entry.value;
              final emptySlots = <Widget>[];
              
              // Convert positions to stack coordinates
              final startPos = _convertToStackCoordinates(animation.startPosition.position);
              final endPos = _convertToStackCoordinates(animation.endPosition.position);
              
              switch (animation.type) {
                case AnimationType.draw:
                  // Draw: empty slot at end only (state already shows card in hand)
                  emptySlots.add(
                    Positioned(
                      left: endPos.dx,
                      top: endPos.dy,
                      width: animation.endPosition.size.width,
                      height: animation.endPosition.size.height,
                      child: _buildEmptySlot(animation.endPosition.size),
                    ),
                  );
                  break;
                  
                case AnimationType.play:
                case AnimationType.sameRankPlay:
                  // Play/SameRank: empty slot at start (card leaving hand)
                  // End position shows previous discard pile card (handled by state)
                  emptySlots.add(
                    Positioned(
                      left: startPos.dx,
                      top: startPos.dy,
                      width: animation.startPosition.size.width,
                      height: animation.startPosition.size.height,
                      child: _buildEmptySlot(animation.startPosition.size),
                    ),
                  );
                  break;
                  
                case AnimationType.reposition:
                  // Reposition: empty slot at start AND end
                  emptySlots.add(
                    Positioned(
                      left: startPos.dx,
                      top: startPos.dy,
                      width: animation.startPosition.size.width,
                      height: animation.startPosition.size.height,
                      child: _buildEmptySlot(animation.startPosition.size),
                    ),
                  );
                  emptySlots.add(
                    Positioned(
                      left: endPos.dx,
                      top: endPos.dy,
                      width: animation.endPosition.size.width,
                      height: animation.endPosition.size.height,
                      child: _buildEmptySlot(animation.endPosition.size),
                    ),
                  );
                  break;
                  
                case AnimationType.jackSwap:
                  // JackSwap: empty slot at start
                  emptySlots.add(
                    Positioned(
                      left: startPos.dx,
                      top: startPos.dy,
                      width: animation.startPosition.size.width,
                      height: animation.startPosition.size.height,
                      child: _buildEmptySlot(animation.startPosition.size),
                    ),
                  );
                  break;
                  
                case AnimationType.collect:
                  // Collect: empty slot at start (discard pile) and end (hand)
                  emptySlots.add(
                    Positioned(
                      left: startPos.dx,
                      top: startPos.dy,
                      width: animation.startPosition.size.width,
                      height: animation.startPosition.size.height,
                      child: _buildEmptySlot(animation.startPosition.size),
                    ),
                  );
                  emptySlots.add(
                    Positioned(
                      left: endPos.dx,
                      top: endPos.dy,
                      width: animation.endPosition.size.width,
                      height: animation.endPosition.size.height,
                      child: _buildEmptySlot(animation.endPosition.size),
                    ),
                  );
                  break;
              }
              
              return emptySlots;
            }),
            // Render animated cards
            ..._activeAnimations.entries.map((entry) {
            final cardId = entry.key;
            final animation = entry.value;
            final positionAnimation = _positionAnimations[cardId]!;
            final sizeAnimation = _sizeAnimations[cardId];
            
            return AnimatedBuilder(
              animation: Listenable.merge([
                positionAnimation,
                if (sizeAnimation != null) sizeAnimation,
              ]),
              builder: (context, child) {
                final currentPosition = positionAnimation.value;
                final currentSize = sizeAnimation?.value ?? animation.endPosition.size;
                
                // Get card data
                final cardData = _getCardData(cardId, animation.showFaceUp);
                
                // Log rendering on first frame and periodically
                if (positionAnimation.status == AnimationStatus.forward) {
                  final frameCount = (positionAnimation.value.dx * 10).toInt();
                  if (frameCount == 0 || frameCount % 5 == 0) {
                    _logger.info('🎬 CardAnimationLayer: Rendering $cardId at (${currentPosition.dx.toStringAsFixed(1)}, ${currentPosition.dy.toStringAsFixed(1)}) with size ${currentSize.width.toStringAsFixed(1)}x${currentSize.height.toStringAsFixed(1)}, animation status: ${positionAnimation.status}', isOn: LOGGING_SWITCH);
                  }
                }
                
                return Positioned(
                  left: currentPosition.dx,
                  top: currentPosition.dy,
                  width: currentSize.width,
                  height: currentSize.height,
                  child: CardWidget(
                    card: cardData,
                    dimensions: currentSize,
                    config: CardDisplayConfig.forMyHand(),
                    showBack: !animation.showFaceUp,
                  ),
                );
              },
            );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
