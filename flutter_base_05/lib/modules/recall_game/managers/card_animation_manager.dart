import 'package:flutter/material.dart';
import '../utils/card_position_tracker.dart';
import '../models/card_model.dart';
import '../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = true;

/// Represents an active card animation
class CardAnimation {
  final String cardId;
  final AnimationController controller;
  final Animation<Offset> positionAnimation;
  final Animation<double> widthAnimation;
  final Animation<double> heightAnimation;
  final Animation<double> opacityAnimation;
  final CardPosition startPosition;
  final CardPosition endPosition;
  final CardModel card;

  CardAnimation({
    required this.cardId,
    required this.controller,
    required this.positionAnimation,
    required this.widthAnimation,
    required this.heightAnimation,
    required this.opacityAnimation,
    required this.startPosition,
    required this.endPosition,
    required this.card,
  });

  /// Dispose of animation resources
  void dispose() {
    controller.dispose();
  }
}

/// Manages card animation state and coordinates between animation layer and widgets
class CardAnimationManager {
  static final CardAnimationManager _instance = CardAnimationManager._internal();
  factory CardAnimationManager() => _instance;
  CardAnimationManager._internal();

  final Logger _logger = Logger();
  final CardPositionTracker _positionTracker = CardPositionTracker();
  final Map<String, CardAnimation> _activeAnimations = {};
  
  // Animation configuration
  static const Duration _animationDuration = Duration(milliseconds: 400);
  static const Curve _animationCurve = Curves.easeInOut;
  static const int _maxConcurrentAnimations = 5;

  /// Get the position tracker instance
  CardPositionTracker get positionTracker => _positionTracker;

  /// Register a card's current position
  void registerCardPosition(CardPosition position) {
    _logger.info('🎬 CardAnimationManager: Registering position for card ${position.cardId} at ${position.location}', isOn: LOGGING_SWITCH);
    _positionTracker.registerCardPosition(position);
  }

  /// Register multiple card positions at once
  void registerCardPositions(List<CardPosition> positions) {
    _positionTracker.registerCardPositions(positions);
  }

  /// Save current positions as previous (call before state update)
  void saveCurrentAsPrevious() {
    _positionTracker.saveCurrentAsPrevious();
  }

  /// Detect card movements and create animations
  /// Returns list of animations to start
  List<CardAnimation> detectAndCreateAnimations(
    TickerProvider vsync,
    Map<String, CardModel> cardModels,
  ) {
    // Detect movements
    final movements = _positionTracker.detectMovements();
    
    _logger.info('🎬 CardAnimationManager: Detected ${movements.length} movements', isOn: LOGGING_SWITCH);
    for (final movement in movements) {
      _logger.info('🎬 CardAnimationManager:   Movement: ${movement.old.cardId} from ${movement.old.location} to ${movement.new_.location}', isOn: LOGGING_SWITCH);
    }
    
    // Limit concurrent animations
    final availableSlots = _maxConcurrentAnimations - _activeAnimations.length;
    _logger.info('🎬 CardAnimationManager: Available animation slots: $availableSlots (active: ${_activeAnimations.length})', isOn: LOGGING_SWITCH);
    
    if (availableSlots <= 0) {
      _logger.info('🎬 CardAnimationManager: No available animation slots', isOn: LOGGING_SWITCH);
      return [];
    }

    final animationsToStart = <CardAnimation>[];

    // Create animations for detected movements (up to available slots)
    for (int i = 0; i < movements.length && i < availableSlots; i++) {
      final movement = movements[i];
      final cardId = movement.new_.cardId;
      
      // Skip if already animating this card
      if (_activeAnimations.containsKey(cardId)) {
        continue;
      }

      // Get card model
      final cardModel = cardModels[cardId];
      if (cardModel == null) {
        _logger.info('🎬 CardAnimationManager: Card model not found for $cardId, skipping', isOn: LOGGING_SWITCH);
        continue;
      }

      // Create animation
      final animation = _createAnimation(
        vsync: vsync,
        cardId: cardId,
        card: cardModel,
        startPosition: movement.old,
        endPosition: movement.new_,
      );

      if (animation != null) {
        _logger.info('🎬 CardAnimationManager: Created animation for $cardId', isOn: LOGGING_SWITCH);
        animationsToStart.add(animation);
        _activeAnimations[cardId] = animation;
      } else {
        _logger.info('🎬 CardAnimationManager: Failed to create animation for $cardId', isOn: LOGGING_SWITCH);
      }
    }

    _logger.info('🎬 CardAnimationManager: Returning ${animationsToStart.length} animations to start', isOn: LOGGING_SWITCH);
    return animationsToStart;
  }

  /// Create a single card animation
  CardAnimation? _createAnimation({
    required TickerProvider vsync,
    required String cardId,
    required CardModel card,
    required CardPosition startPosition,
    required CardPosition endPosition,
  }) {
    // Create animation controller
    final controller = AnimationController(
      duration: _animationDuration,
      vsync: vsync,
    );

    // Create position animation (Offset from start to end)
    final positionTween = Tween<Offset>(
      begin: startPosition.position,
      end: endPosition.position,
    );
    final positionAnimation = positionTween.animate(
      CurvedAnimation(
        parent: controller,
        curve: _animationCurve,
      ),
    );

    // Create width animation
    final widthTween = Tween<double>(
      begin: startPosition.size.width,
      end: endPosition.size.width,
    );
    final widthAnimation = widthTween.animate(
      CurvedAnimation(
        parent: controller,
        curve: _animationCurve,
      ),
    );

    // Create height animation
    final heightTween = Tween<double>(
      begin: startPosition.size.height,
      end: endPosition.size.height,
    );
    final heightAnimation = heightTween.animate(
      CurvedAnimation(
        parent: controller,
        curve: _animationCurve,
      ),
    );

    // Create opacity animation - keep cards visible during movement
    // Slight fade at start/end for smooth transition, but stay mostly visible
    final opacityTween = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.95)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 0.05, // Slight fade at start
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.95), // Stay mostly visible during movement
        weight: 0.9, // Most of the animation time
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.95, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 0.05, // Fade back in at end
      ),
    ]);
    final opacityAnimation = opacityTween.animate(
      CurvedAnimation(
        parent: controller,
        curve: _animationCurve,
      ),
    );

    return CardAnimation(
      cardId: cardId,
      controller: controller,
      positionAnimation: positionAnimation,
      widthAnimation: widthAnimation,
      heightAnimation: heightAnimation,
      opacityAnimation: opacityAnimation,
      startPosition: startPosition,
      endPosition: endPosition,
      card: card,
    );
  }

  /// Start an animation
  void startAnimation(CardAnimation animation) {
    animation.controller.forward();
  }

  /// Get active animation for a card
  CardAnimation? getActiveAnimation(String cardId) {
    return _activeAnimations[cardId];
  }

  /// Get all active animations
  Map<String, CardAnimation> getActiveAnimations() {
    return Map.unmodifiable(_activeAnimations);
  }

  /// Check if a card is currently animating
  bool isAnimating(String cardId) {
    return _activeAnimations.containsKey(cardId);
  }

  /// Complete and remove an animation
  void completeAnimation(String cardId) {
    final animation = _activeAnimations.remove(cardId);
    animation?.dispose();
  }

  /// Cancel and remove an animation
  void cancelAnimation(String cardId) {
    final animation = _activeAnimations.remove(cardId);
    if (animation != null) {
      animation.controller.stop();
      animation.dispose();
    }
  }

  /// Clear all active animations
  void clearAllAnimations() {
    for (final animation in _activeAnimations.values) {
      animation.dispose();
    }
    _activeAnimations.clear();
  }

  /// Clean up completed animations (call periodically)
  void cleanupCompletedAnimations() {
    final completed = <String>[];
    
    for (final entry in _activeAnimations.entries) {
      final cardId = entry.key;
      final animation = entry.value;
      
      if (animation.controller.isCompleted || 
          animation.controller.isDismissed) {
        completed.add(cardId);
      }
    }

    for (final cardId in completed) {
      completeAnimation(cardId);
    }
  }

  /// Dispose of all resources
  void dispose() {
    clearAllAnimations();
    _positionTracker.clear();
  }
}

