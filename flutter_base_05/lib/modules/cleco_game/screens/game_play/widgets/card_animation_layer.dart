import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../models/card_model.dart';
import '../../../models/card_display_config.dart';
import '../../../widgets/card_widget.dart';
import '../card_position_tracker.dart';
import '../../../../../utils/consts/theme_consts.dart';

const bool LOGGING_SWITCH = false; // Enabled for animation debugging

/// Active animation data structure
class ActiveAnimation {
  final String animationId;
  final String cardId;
  final CardModel card;
  final Offset startPosition;
  final Offset endPosition;
  final Size startSize;
  final Size endSize;
  final AnimationController controller;
  final Animation<Offset> positionAnimation;
  final Animation<Size> sizeAnimation;
  final String? playerId;
  final bool showBack; // Whether to show card back (for privacy)

  ActiveAnimation({
    required this.animationId,
    required this.cardId,
    required this.card,
    required this.startPosition,
    required this.endPosition,
    required this.startSize,
    required this.endSize,
    required this.controller,
    required this.positionAnimation,
    required this.sizeAnimation,
    this.playerId,
    required this.showBack,
  });
}

/// Empty slot data structure for play/reposition animations
class EmptySlotData {
  final String slotId;
  final Offset position;
  final Size size;
  final String? playerId;

  EmptySlotData({
    required this.slotId,
    required this.position,
    required this.size,
    this.playerId,
  });
}

/// Full-screen overlay widget for card animations
/// 
/// This widget displays animated card movements on top of the game screen.
/// It listens to animation triggers from CardPositionTracker and animates
/// cards using the existing CardWidget system.
class CardAnimationLayer extends StatefulWidget {
  const CardAnimationLayer({Key? key}) : super(key: key);

  @override
  State<CardAnimationLayer> createState() => _CardAnimationLayerState();
}

class _CardAnimationLayerState extends State<CardAnimationLayer> with TickerProviderStateMixin {
  final Logger _logger = Logger();
  final Map<String, ActiveAnimation> _activeAnimations = {};
  final Map<String, EmptySlotData> _emptySlots = {}; // Track empty slots during play/reposition animations
  int _animationCounter = 0;

  @override
  void initState() {
    super.initState();
    _logger.info(
      'CardAnimationLayer.initState() - Initializing animation layer',
      isOn: LOGGING_SWITCH,
    );
    _listenToAnimationTriggers();
  }

  /// Listen to animation triggers from CardPositionTracker
  void _listenToAnimationTriggers() {
    final tracker = CardPositionTracker.instance();
    tracker.cardAnimationTrigger.addListener(_onAnimationTriggered);
    _logger.info(
      'CardAnimationLayer._listenToAnimationTriggers() - Listener registered on cardAnimationTrigger',
      isOn: LOGGING_SWITCH,
    );
  }

  @override
  void dispose() {
    final tracker = CardPositionTracker.instance();
    tracker.cardAnimationTrigger.removeListener(_onAnimationTriggered);
    
    // Dispose all animation controllers
    for (final animation in _activeAnimations.values) {
      animation.controller.dispose();
    }
    _activeAnimations.clear();
    
    super.dispose();
  }

  /// Handle animation trigger from tracker
  void _onAnimationTriggered() {
    _logger.info(
      'CardAnimationLayer._onAnimationTriggered() - Listener callback triggered',
      isOn: LOGGING_SWITCH,
    );
    
    final tracker = CardPositionTracker.instance();
    final trigger = tracker.cardAnimationTrigger.value;
    
    _logger.info(
      'CardAnimationLayer._onAnimationTriggered() - Trigger value: ${trigger != null ? "NOT NULL" : "NULL"}',
      isOn: LOGGING_SWITCH,
    );
    
    if (trigger != null) {
      final animationTypeName = trigger.animationType.toString().split('.').last;
      _logger.info(
        'CardAnimationLayer._onAnimationTriggered() - Received $animationTypeName animation trigger for cardId: ${trigger.cardId}',
        isOn: LOGGING_SWITCH,
      );

      // Determine if we need full card data based on animation type
      // Only play and collect animations show full card details
      final needsFullCardData = trigger.animationType == AnimationType.play || 
                                trigger.animationType == AnimationType.collect;
      
      CardModel cardModel;
      if (needsFullCardData) {
        // Get full card data from game state for play/collect animations
        final cardData = _getCardDataFromState(trigger.cardId);
        if (cardData != null) {
          cardModel = CardModel.fromMap(cardData);
        } else {
          _logger.warning(
            'CardAnimationLayer._onAnimationTriggered() - Could not find card data for cardId: ${trigger.cardId}, using back card model',
            isOn: LOGGING_SWITCH,
          );
          // Fallback to back card if data not found
          cardModel = _createBackCardModel(trigger.cardId);
        }
      } else {
        // For draw/reposition animations, create minimal card model (card back only)
        cardModel = _createBackCardModel(trigger.cardId);
      }

      _startCardAnimation(trigger, cardModel);

      // Clear the trigger after processing
      WidgetsBinding.instance.addPostFrameCallback((_) {
        tracker.cardAnimationTrigger.value = null;
      });
    } else {
      _logger.info(
        'CardAnimationLayer._onAnimationTriggered() - Trigger is null, ignoring',
        isOn: LOGGING_SWITCH,
      );
    }
  }

  /// Create a minimal CardModel for card back display
  /// 
  /// This creates a CardModel with only cardId, which triggers card back display
  /// because hasFullData will be false (rank='?', suit='?', points=0)
  CardModel _createBackCardModel(String cardId) {
    return CardModel(
      cardId: cardId,
      rank: '?',
      suit: '?',
      points: 0,
    );
  }

  /// Get card data from game state
  Map<String, dynamic>? _getCardDataFromState(String cardId) {
    try {
      final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
      
      if (currentGameId.isEmpty) {
        _logger.warning(
          'CardAnimationLayer._getCardDataFromState() - No current game ID found',
          isOn: LOGGING_SWITCH,
        );
        return null;
      }

      final games = clecoGameState['games'] as Map<String, dynamic>? ?? {};
      final currentGame = games[currentGameId] as Map<String, dynamic>? ?? {};
      final gameData = currentGame['gameData'] as Map<String, dynamic>? ?? {};
      final gameState = gameData['game_state'] as Map<String, dynamic>? ?? {};
      final originalDeck = gameState['originalDeck'] as List<dynamic>? ?? [];

      // Search for card in original deck
      for (final card in originalDeck) {
        if (card is Map<String, dynamic>) {
          final cardIdInDeck = card['cardId']?.toString() ?? '';
          if (cardIdInDeck == cardId) {
            _logger.info(
              'CardAnimationLayer._getCardDataFromState() - Found card data for cardId: $cardId',
              isOn: LOGGING_SWITCH,
            );
            return card;
          }
        }
      }

      _logger.warning(
        'CardAnimationLayer._getCardDataFromState() - Card not found in originalDeck: $cardId',
        isOn: LOGGING_SWITCH,
      );
      return null;
    } catch (e) {
      _logger.error(
        'CardAnimationLayer._getCardDataFromState() - Error getting card data: $e',
        isOn: LOGGING_SWITCH,
      );
      return null;
    }
  }

  /// Start a card animation
  void _startCardAnimation(CardAnimationTrigger trigger, CardModel cardModel) {
    final animationTypeName = trigger.animationType.toString().split('.').last;
    final animationId = '${animationTypeName}_${trigger.cardId}_${_animationCounter++}';
    
    // Determine if card back should be shown based on animation type
    // Only play and collect animations show full card details
    final showBack = trigger.animationType == AnimationType.draw || 
                     trigger.animationType == AnimationType.reposition;

    // Create animation controller
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // 600ms animation duration
    );

    // Create position animation
    final positionAnimation = Tween<Offset>(
      begin: trigger.startPosition,
      end: trigger.endPosition,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    ));

    // Create size animation
    final sizeAnimation = Tween<Size>(
      begin: trigger.startSize,
      end: trigger.endSize,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    ));

    // Create active animation
    final animation = ActiveAnimation(
      animationId: animationId,
      cardId: trigger.cardId,
      card: cardModel,
      startPosition: trigger.startPosition,
      endPosition: trigger.endPosition,
      startSize: trigger.startSize,
      endSize: trigger.endSize,
      controller: controller,
      positionAnimation: positionAnimation,
      sizeAnimation: sizeAnimation,
      playerId: trigger.playerId,
      showBack: showBack,
    );

    setState(() {
      _activeAnimations[animationId] = animation;
    });

    // When a play animation starts, create an empty slot at the start position
    // This slot will remain visible during both play and reposition animations
    if (trigger.animationType == AnimationType.play) {
      final slotId = 'empty_slot_${trigger.key}_${_animationCounter}';
      final emptySlot = EmptySlotData(
        slotId: slotId,
        position: trigger.startPosition,
        size: trigger.startSize,
        playerId: trigger.playerId,
      );
      
      setState(() {
        _emptySlots[slotId] = emptySlot;
      });
      
      _logger.info(
        'CardAnimationLayer._startCardAnimation() - Created empty slot: $slotId at position (${trigger.startPosition.dx.toStringAsFixed(1)}, ${trigger.startPosition.dy.toStringAsFixed(1)})',
        isOn: LOGGING_SWITCH,
      );
    }

    _logger.info(
      'CardAnimationLayer._startCardAnimation() - Started $animationTypeName animation: $animationId\n'
      '  cardId: ${trigger.cardId}\n'
      '  showBack: $showBack\n'
      '  hasFullData: ${cardModel.hasFullData}\n'
      '  startPosition: (${trigger.startPosition.dx.toStringAsFixed(1)}, ${trigger.startPosition.dy.toStringAsFixed(1)})\n'
      '  endPosition: (${trigger.endPosition.dx.toStringAsFixed(1)}, ${trigger.endPosition.dy.toStringAsFixed(1)})\n'
      '  startSize: ${trigger.startSize.width.toStringAsFixed(1)}x${trigger.startSize.height.toStringAsFixed(1)}\n'
      '  endSize: ${trigger.endSize.width.toStringAsFixed(1)}x${trigger.endSize.height.toStringAsFixed(1)}',
      isOn: LOGGING_SWITCH,
    );

    // Start animation
    controller.forward().then((_) {
      // Notify tracker that animation completed
      final tracker = CardPositionTracker.instance();
      tracker.notifyAnimationComplete(
        cardId: trigger.cardId,
        key: trigger.key,
        animationType: trigger.animationType,
        playerId: trigger.playerId,
      );
      
      // When reposition animation completes, remove the empty slot
      // The reposition's end position should match the play's start position (where empty slot is)
      if (trigger.animationType == AnimationType.reposition) {
        // Find and remove empty slot that matches this reposition's end position
        String? slotToRemove;
        for (final entry in _emptySlots.entries) {
          final slot = entry.value;
          // Check if positions match (within a small tolerance)
          final positionMatch = (slot.position - trigger.endPosition).distance < 5.0;
          final sizeMatch = (slot.size.width - trigger.endSize.width).abs() < 5.0 &&
                           (slot.size.height - trigger.endSize.height).abs() < 5.0;
          
          if (positionMatch && sizeMatch) {
            slotToRemove = entry.key;
            break;
          }
        }
        
        if (slotToRemove != null) {
          setState(() {
            _emptySlots.remove(slotToRemove);
          });
          _logger.info(
            'CardAnimationLayer._startCardAnimation() - Removed empty slot: $slotToRemove after reposition completed',
            isOn: LOGGING_SWITCH,
          );
        }
      }
      
      // Cleanup after animation completes
      if (mounted) {
        setState(() {
          final removed = _activeAnimations.remove(animationId);
          if (removed != null) {
            removed.controller.dispose();
          }
        });
        _logger.info(
          'CardAnimationLayer._startCardAnimation() - Animation completed and cleaned up: $animationId',
          isOn: LOGGING_SWITCH,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size and app bar height for position conversion
    // The Stack is in the Scaffold body (below app bar), so we need to convert
    // from screen coordinates (from localToGlobal) to Stack-relative coordinates
    final screenSize = MediaQuery.of(context).size;
    final appBarHeight = Scaffold.of(context).appBarMaxHeight ?? kToolbarHeight;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    // Total offset from screen top to Stack top (app bar + safe area top)
    final stackTopOffset = appBarHeight + safeAreaTop;

    // Build list of widgets: animated cards + empty slots
    final List<Widget> overlayChildren = [];
    
    // Add animated cards
    overlayChildren.addAll(
      _activeAnimations.values.map((animation) {
        return _buildAnimatedCard(animation, stackTopOffset);
      }),
    );
    
    // Add empty slots
    overlayChildren.addAll(
      _emptySlots.values.map((slot) {
        return _buildEmptySlot(slot, stackTopOffset);
      }),
    );

    // If no active animations and no empty slots, return empty widget that doesn't block interactions
    if (overlayChildren.isEmpty) {
      return IgnorePointer(
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height - stackTopOffset,
        ),
      );
    }

    // Build overlay with animated cards and empty slots
    // Position at top: 0 since Stack is already in body (below app bar)
    return Positioned.fill(
      child: IgnorePointer(
        // Allow clicks to pass through to underlying widgets
        ignoring: true,
        child: Stack(
          children: overlayChildren,
        ),
      ),
    );
  }

  /// Build an animated card widget
  /// 
  /// [stackTopOffset] - The offset from screen top to Stack top (app bar + safe area)
  /// Used to convert screen coordinates (from localToGlobal) to Stack-relative coordinates
  Widget _buildAnimatedCard(ActiveAnimation animation, double stackTopOffset) {
    // Determine card display config based on location
    final config = animation.playerId != null
        ? CardDisplayConfig.forOpponent() // Opponent hand
        : CardDisplayConfig.forMyHand(); // My hand

    return AnimatedBuilder(
      animation: animation.controller,
      builder: (context, child) {
        final position = animation.positionAnimation.value;
        final size = animation.sizeAnimation.value;

        // Convert from screen coordinates (from localToGlobal) to Stack-relative coordinates
        // Screen coordinates include app bar, but Stack is in body (below app bar)
        final adjustedPosition = Offset(position.dx, position.dy - stackTopOffset);

        return Positioned(
          left: adjustedPosition.dx,
          top: adjustedPosition.dy,
          child: CardWidget(
            card: animation.card,
            dimensions: size,
            config: config,
            showBack: animation.showBack, // Use showBack from animation (based on animation type)
          ),
        );
      },
    );
  }

  /// Build an empty slot widget
  /// 
  /// [stackTopOffset] - The offset from screen top to Stack top (app bar + safe area)
  /// Used to convert screen coordinates (from localToGlobal) to Stack-relative coordinates
  Widget _buildEmptySlot(EmptySlotData slot, double stackTopOffset) {
    // Convert from screen coordinates (from localToGlobal) to Stack-relative coordinates
    // Screen coordinates include app bar, but Stack is in body (below app bar)
    final adjustedPosition = Offset(slot.position.dx, slot.position.dy - stackTopOffset);
    
    // Use card back color with saturation reduced to 0.2
    final cardBackColor = HSLColor.fromColor(AppColors.primaryColor)
        .withSaturation(0.2)
        .toColor();

    return Positioned(
      left: adjustedPosition.dx,
      top: adjustedPosition.dy,
      child: SizedBox(
        width: slot.size.width,
        height: slot.size.height,
        child: Container(
          decoration: BoxDecoration(
            color: cardBackColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderDefault,
              width: 2,
              style: BorderStyle.solid,
            ),
          ),
        ),
      ),
    );
  }
}

