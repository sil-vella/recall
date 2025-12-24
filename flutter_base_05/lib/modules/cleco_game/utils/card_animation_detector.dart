import 'package:flutter/foundation.dart';
import 'card_position_scanner.dart';
import '../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = true; // Enabled for testing and debugging

/// Animation types for different card movements
enum AnimationType {
  draw,           // Card drawn from draw pile to hand
  play,           // Card played from hand to discard pile
  collect,         // Card collected from discard pile to hand
  reposition,      // Card repositioned within same hand
  sameRankPlay,   // Card played during same rank window
  jackSwap,       // Card swapped between players (jack power)
}

/// Represents a card animation from start to end position
class CardAnimation {
  final String cardId;
  final CardPosition startPosition;
  final CardPosition endPosition;
  final AnimationType type;
  final bool showFaceUp; // Whether to show card face during animation

  const CardAnimation({
    required this.cardId,
    required this.startPosition,
    required this.endPosition,
    required this.type,
    required this.showFaceUp,
  });

  @override
  String toString() => 'CardAnimation($cardId, $type, ${startPosition.location} -> ${endPosition.location}, faceUp: $showFaceUp)';
}

/// Utility class to detect card movements requiring animation
class CardAnimationDetector {
  static final CardAnimationDetector _instance = CardAnimationDetector._internal();
  factory CardAnimationDetector() => _instance;
  CardAnimationDetector._internal();

  final Logger _logger = Logger();
  
  /// ValueNotifier for animation triggers - CardAnimationLayer listens to this
  final ValueNotifier<List<CardAnimation>?> animationTriggers = ValueNotifier<List<CardAnimation>?>(null);

  /// Detect animations by comparing current and previous positions
  /// 
  /// **State Update Handling**:
  /// - Missing cardId in current scan: Do NOT create animation (position preserved in scanner)
  /// - CardId in new position: Create animation from old to new position, even if old widget still exists
  /// 
  /// Returns list of CardAnimation objects
  List<CardAnimation> detectAnimations(
    Map<String, CardPosition> currentPositions,
    Map<String, CardPosition> previousPositions,
  ) {
    final animations = <CardAnimation>[];
    
    _logger.info('🎬 CardAnimationDetector: Detecting animations - current: ${currentPositions.length}, previous: ${previousPositions.length}', isOn: LOGGING_SWITCH);
    
    // Only create animations for cardIds that exist in current scan
    // Missing cardIds are preserved in scanner (state still updating), so don't animate them
    for (final entry in currentPositions.entries) {
      final cardId = entry.key;
      final newPosition = entry.value;
      final oldPosition = previousPositions[cardId];
      
      // Skip special pile cardIds (draw_pile_full, draw_pile_empty, discard_pile_empty)
      if (cardId.startsWith('draw_pile_') || cardId == 'discard_pile_empty') {
        continue;
      }
      
      _logger.info('🎬 CardAnimationDetector: Checking $cardId - old: ${oldPosition?.location ?? 'null'}, new: ${newPosition.location}', isOn: LOGGING_SWITCH);
      
      if (oldPosition != null) {
        // Card exists in both old and new positions
        // Check if location changed (this catches play, collect, draw, jackSwap)
        if (oldPosition.location != newPosition.location) {
          // Location changed - determine animation type
          final animationType = _determineAnimationType(oldPosition, newPosition);
          final showFaceUp = _shouldShowFaceUp(animationType, oldPosition, newPosition);
          
          final animation = CardAnimation(
            cardId: cardId,
            startPosition: oldPosition,
            endPosition: newPosition,
            type: animationType,
            showFaceUp: showFaceUp,
          );
          
          animations.add(animation);
          _logger.info('🎬 CardAnimationDetector: Detected $animationType animation for $cardId: ${oldPosition.location} -> ${newPosition.location}', isOn: LOGGING_SWITCH);
        } else if (oldPosition.isDifferentFrom(newPosition)) {
          // Same location but different position - reposition
          final animationType = AnimationType.reposition;
          
          // Skip reposition animations for static locations (draw_pile, discard_pile)
          // These shouldn't animate unless they're actually moving to a different location
          final isStaticLocation = oldPosition.location == 'draw_pile' || 
                                  oldPosition.location == 'discard_pile';
          if (isStaticLocation) {
            _logger.info('🎬 CardAnimationDetector: Skipping reposition animation for static location $cardId at ${oldPosition.location}', isOn: LOGGING_SWITCH);
          } else {
            final showFaceUp = _shouldShowFaceUp(animationType, oldPosition, newPosition);
            
            final animation = CardAnimation(
              cardId: cardId,
              startPosition: oldPosition,
              endPosition: newPosition,
              type: animationType,
              showFaceUp: showFaceUp,
            );
            
            animations.add(animation);
            _logger.info('🎬 CardAnimationDetector: Detected $animationType animation for $cardId: ${oldPosition.location} -> ${newPosition.location}', isOn: LOGGING_SWITCH);
          }
        } else {
          _logger.info('🎬 CardAnimationDetector: Card $cardId at same position (${oldPosition.location})', isOn: LOGGING_SWITCH);
        }
      } else {
        // Card appeared (exists in new but not old)
        // Check if it came from draw pile (appeared in hand)
        if (newPosition.location == 'my_hand' || newPosition.location.startsWith('opponent_hand_')) {
          // Try to find draw pile position - look for draw_pile_full or draw_pile_empty
          final drawPilePosition = _findDrawPilePosition(currentPositions);
          if (drawPilePosition != null) {
            // Verify it's actually the draw pile (not discard pile)
            if (drawPilePosition.location != 'draw_pile') {
              _logger.warning('🎬 CardAnimationDetector: Found position with wrong location for draw pile: ${drawPilePosition.location}', isOn: LOGGING_SWITCH);
            }
            _logger.info('🎬 CardAnimationDetector: Using draw pile position: location=${drawPilePosition.location}, position=(${drawPilePosition.position.dx.toStringAsFixed(1)}, ${drawPilePosition.position.dy.toStringAsFixed(1)})', isOn: LOGGING_SWITCH);
            final animation = CardAnimation(
              cardId: cardId,
              startPosition: drawPilePosition.copyWith(cardId: cardId),
              endPosition: newPosition,
              type: AnimationType.draw,
              showFaceUp: false, // Draw animations show card back
            );
            animations.add(animation);
            _logger.info('🎬 CardAnimationDetector: Detected draw animation for $cardId from draw_pile to ${newPosition.location}', isOn: LOGGING_SWITCH);
          } else {
            _logger.info('🎬 CardAnimationDetector: Card $cardId appeared at ${newPosition.location} (draw_pile position not found)', isOn: LOGGING_SWITCH);
          }
        }
      }
    }
    
    // Check for cards that disappeared from hands (exist in old but not new)
    // These likely moved to discard pile (but the card might appear in discard pile in current scan with different cardId)
    // Actually, when a card is played, it should appear in discard pile in current scan, so we should detect it above
    // This check is for cards that truly disappeared (not in current scan at all)
    for (final entry in previousPositions.entries) {
      final cardId = entry.key;
      final oldPosition = entry.value;
      
      // Skip special pile cardIds
      if (cardId.startsWith('draw_pile_') || cardId == 'discard_pile_empty') {
        continue;
      }
      
      if (!currentPositions.containsKey(cardId)) {
        // Card disappeared completely
        // Check if it was in hand and should animate to discard pile
        if (oldPosition.location == 'my_hand' || oldPosition.location.startsWith('opponent_hand_')) {
          final discardPilePosition = _findDiscardPilePosition(currentPositions);
          if (discardPilePosition != null) {
            final animation = CardAnimation(
              cardId: cardId,
              startPosition: oldPosition,
              endPosition: discardPilePosition.copyWith(cardId: cardId),
              type: AnimationType.play,
              showFaceUp: true, // Play animations show card face
            );
            animations.add(animation);
            _logger.info('🎬 CardAnimationDetector: Detected play animation for $cardId from ${oldPosition.location} to discard_pile (card disappeared)', isOn: LOGGING_SWITCH);
          } else {
            _logger.info('🎬 CardAnimationDetector: Card $cardId disappeared from ${oldPosition.location} (discard_pile position not found)', isOn: LOGGING_SWITCH);
          }
        }
      }
    }
    
    _logger.info('🎬 CardAnimationDetector: Detection complete - ${animations.length} animations found', isOn: LOGGING_SWITCH);
    
    // Trigger animations via ValueNotifier
    if (animations.isNotEmpty) {
      animationTriggers.value = animations;
      // Clear after one frame to prevent duplicate triggers
      Future.microtask(() {
        animationTriggers.value = null;
      });
    }
    
    return animations;
  }

  /// Determine animation type based on position change
  AnimationType _determineAnimationType(CardPosition oldPos, CardPosition newPos) {
    _logger.info('🎬 CardAnimationDetector: Determining animation type for ${oldPos.location} -> ${newPos.location}', isOn: LOGGING_SWITCH);
    
    // Hand to discard = play (highest priority - check first)
    if ((oldPos.location == 'my_hand' || oldPos.location.startsWith('opponent_hand_')) && 
        newPos.location == 'discard_pile') {
      _logger.info('🎬 CardAnimationDetector: Detected play animation (hand -> discard)', isOn: LOGGING_SWITCH);
      return AnimationType.play;
    }
    
    // Draw pile to hand = draw
    if (oldPos.location == 'draw_pile' && 
        (newPos.location == 'my_hand' || newPos.location.startsWith('opponent_hand_'))) {
      _logger.info('🎬 CardAnimationDetector: Detected draw animation (draw_pile -> hand)', isOn: LOGGING_SWITCH);
      return AnimationType.draw;
    }
    
    // Discard to hand = collect
    if (oldPos.location == 'discard_pile' && 
        (newPos.location == 'my_hand' || newPos.location.startsWith('opponent_hand_'))) {
      _logger.info('🎬 CardAnimationDetector: Detected collect animation (discard -> hand)', isOn: LOGGING_SWITCH);
      return AnimationType.collect;
    }
    
    // Opponent hand to opponent hand = jack swap
    if (oldPos.location.startsWith('opponent_hand_') && 
        newPos.location.startsWith('opponent_hand_') &&
        oldPos.location != newPos.location) {
      _logger.info('🎬 CardAnimationDetector: Detected jackSwap animation (opponent -> opponent)', isOn: LOGGING_SWITCH);
      return AnimationType.jackSwap;
    }
    
    // Same location but different position = reposition
    if (oldPos.location == newPos.location) {
      _logger.info('🎬 CardAnimationDetector: Detected reposition animation (same location)', isOn: LOGGING_SWITCH);
      return AnimationType.reposition;
    }
    
    // Default to reposition
    _logger.info('🎬 CardAnimationDetector: Defaulting to reposition animation', isOn: LOGGING_SWITCH);
    return AnimationType.reposition;
  }

  /// Determine if card should show face up during animation
  bool _shouldShowFaceUp(AnimationType type, CardPosition oldPos, CardPosition newPos) {
    switch (type) {
      case AnimationType.draw:
        return false; // Draw animations show card back
      case AnimationType.play:
        return true; // Play animations show card face
      case AnimationType.collect:
        return true; // Collect animations show card face
      case AnimationType.reposition:
        return oldPos.isFaceUp; // Reposition maintains face state
      case AnimationType.sameRankPlay:
        return true; // Same rank play shows card face
      case AnimationType.jackSwap:
        return false; // Jack swap shows card back (privacy)
    }
  }

  /// Find draw pile position in current positions
  CardPosition? _findDrawPilePosition(Map<String, CardPosition> positions) {
    // First, try to find draw_pile_full or draw_pile_empty by cardId
    final drawPileFull = positions['draw_pile_full'];
    if (drawPileFull != null && drawPileFull.location == 'draw_pile') {
      _logger.info('🎬 CardAnimationDetector: Found draw_pile_full position: (${drawPileFull.position.dx.toStringAsFixed(1)}, ${drawPileFull.position.dy.toStringAsFixed(1)})', isOn: LOGGING_SWITCH);
      return drawPileFull;
    }
    
    final drawPileEmpty = positions['draw_pile_empty'];
    if (drawPileEmpty != null && drawPileEmpty.location == 'draw_pile') {
      _logger.info('🎬 CardAnimationDetector: Found draw_pile_empty position: (${drawPileEmpty.position.dx.toStringAsFixed(1)}, ${drawPileEmpty.position.dy.toStringAsFixed(1)})', isOn: LOGGING_SWITCH);
      return drawPileEmpty;
    }
    
    // Fallback: look for any position with location == 'draw_pile'
    // But verify it's not actually a discard pile card
    for (final entry in positions.entries) {
      final cardId = entry.key;
      final position = entry.value;
      if (position.location == 'draw_pile' && 
          !cardId.startsWith('discard_pile_') && 
          cardId != 'discard_pile_empty') {
        _logger.info('🎬 CardAnimationDetector: Found draw_pile position from $cardId: (${position.position.dx.toStringAsFixed(1)}, ${position.position.dy.toStringAsFixed(1)})', isOn: LOGGING_SWITCH);
        return position;
      }
    }
    
    _logger.warning('🎬 CardAnimationDetector: No draw_pile position found', isOn: LOGGING_SWITCH);
    return null;
  }

  /// Find discard pile position in current positions
  CardPosition? _findDiscardPilePosition(Map<String, CardPosition> positions) {
    for (final position in positions.values) {
      if (position.location == 'discard_pile') {
        return position;
      }
    }
    return null;
  }

  /// Clear all tracked positions
  void clear() {
    // This is handled by CardPositionScanner
    _logger.info('🎬 CardAnimationDetector: Clear called (positions managed by scanner)', isOn: LOGGING_SWITCH);
  }
}

