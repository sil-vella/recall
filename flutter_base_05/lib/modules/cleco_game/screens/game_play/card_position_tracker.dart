import 'package:flutter/material.dart';
import '../../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = false; // Enabled for animation debugging

/// Animation types
enum AnimationType {
  draw,      // Card drawn from draw pile to hand
  play,      // Card played from hand to discard pile
  collect,   // Card collected from discard pile to hand
  reposition, // Card repositioned within hand (same rank play)
}

/// Animation trigger data for card animations
class CardAnimationTrigger {
  final String cardId;
  final String key;
  final AnimationType animationType;
  final Offset startPosition;
  final Offset endPosition;
  final Size startSize;
  final Size endSize;
  final String? playerId;
  final DateTime timestamp;

  CardAnimationTrigger({
    required this.cardId,
    required this.key,
    required this.animationType,
    required this.startPosition,
    required this.endPosition,
    required this.startSize,
    required this.endSize,
    this.playerId,
  }) : timestamp = DateTime.now();
}

/// Animation completion event data
class CardAnimationComplete {
  final String cardId;
  final String key;
  final AnimationType animationType;
  final String? playerId;
  final DateTime timestamp;

  CardAnimationComplete({
    required this.cardId,
    required this.key,
    required this.animationType,
    this.playerId,
  }) : timestamp = DateTime.now();
}

/// Position data for a tracked card
class CardPositionData {
  final Offset position;
  final Size size;
  final String location;
  final String? playerId;
  final String? playerStatus;
  final DateTime lastUpdated;

  CardPositionData({
    required this.position,
    required this.size,
    required this.location,
    this.playerId,
    this.playerStatus,
  }) : lastUpdated = DateTime.now();

  @override
  String toString() {
    return 'CardPositionData(position: ${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)}, size: ${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}, location: $location, playerId: $playerId, playerStatus: $playerStatus)';
  }
}

/// Singleton that tracks the position of all cards on the game play screen
/// 
/// Widgets update positions on each rebuild, and the tracker logs all positions
/// for debugging and future animation implementation.
class CardPositionTracker {
  static CardPositionTracker? _instance;
  final Logger _logger = Logger();

  // Map of cardId -> CardPositionData
  // For opponent cards, key format is: 'playerId_cardId'
  // For my hand cards, key format is: 'cardId'
  // For piles, key format is: 'draw_pile' or 'discard_pile' or 'discard_pile_empty'
  final Map<String, CardPositionData> _positions = {};

  // ValueNotifier for animation triggers - animation layer can listen to this
  final ValueNotifier<CardAnimationTrigger?> cardAnimationTrigger = ValueNotifier<CardAnimationTrigger?>(null);
  
  // ValueNotifier for animation completion events - widgets can listen to this
  final ValueNotifier<CardAnimationComplete?> cardAnimationComplete = ValueNotifier<CardAnimationComplete?>(null);
  
  // Track recently triggered animations to prevent duplicates
  // Map<key, AnimationType> - tracks which animations have been triggered for which cards
  final Map<String, AnimationType> _recentAnimations = {};

  CardPositionTracker._internal();

  /// Factory constructor to return the singleton instance
  factory CardPositionTracker.instance() {
    if (_instance == null) {
      _instance = CardPositionTracker._internal();
      _instance!._logger.info('CardPositionTracker: Singleton instance created', isOn: LOGGING_SWITCH);
    }
    return _instance!;
  }

  /// Update the position of a card
  /// 
  /// [cardId] - The unique identifier for the card
  /// [position] - The screen position (Offset) of the card
  /// [size] - The size of the card
  /// [location] - The location type: 'my_hand', 'opponent_hand', 'draw_pile', 'discard_pile'
  /// [playerId] - Optional player ID for opponent cards
  /// [playerStatus] - Optional player status (e.g., 'drawing_card', 'playing_card', etc.)
  /// [suggestedAnimationType] - Optional animation type hint from widgets (takes priority over position-based detection)
  void updateCardPosition(
    String cardId,
    Offset position,
    Size size,
    String location, {
    String? playerId,
    String? playerStatus,
    AnimationType? suggestedAnimationType,
  }) {
    _logger.info(
      'CardPositionTracker.updateCardPosition() called - cardId: $cardId, location: $location${playerId != null ? ', playerId: $playerId' : ''}${playerStatus != null ? ', playerStatus: $playerStatus' : ''}',
      isOn: LOGGING_SWITCH,
    );

    // Create composite key for opponent cards
    final key = playerId != null ? '${playerId}_$cardId' : cardId;

    // Get old position data if it exists
    // For discard pile, also check if card was previously in a hand with playerId prefix
    CardPositionData? oldPositionData = _positions[key];
    String? oldKey = key;
    if (oldPositionData == null && location == 'discard_pile' && playerId == null) {
      // Card moving to discard pile - check if it was in any player's hand
      // Search for existing position with this cardId but with a playerId prefix (opponent)
      // or just the cardId (my hand)
      for (final entry in _positions.entries) {
        final isHandLocation = entry.value.location == 'my_hand' || entry.value.location == 'opponent_hand';
        if (isHandLocation && (entry.key == cardId || entry.key.endsWith('_$cardId'))) {
          oldPositionData = entry.value;
          oldKey = entry.key; // Store the old key for proper cleanup
          _logger.info(
            'CardPositionTracker.updateCardPosition() - Found old position for discard pile card: oldKey=$oldKey, oldLocation=${entry.value.location}',
            isOn: LOGGING_SWITCH,
          );
          break;
        }
      }
    }
    
    // Create new position data
    final newPositionData = CardPositionData(
      position: position,
      size: size,
      location: location,
      playerId: playerId,
      playerStatus: playerStatus,
    );

    // PRIORITY 1: Use suggested animation type from widgets (if provided)
    // This takes precedence over position-based detection
    AnimationType? animationType;
    Offset? startPosition;
    Size? startSize;
    
    // Variables for position-based detection (used in fallback)
    final isNewCard = oldPositionData == null;
    final isHandLocation = location == 'my_hand' || location == 'opponent_hand';
    final isDiscardLocation = location == 'discard_pile';
    final positionChanged = oldPositionData != null && oldPositionData.position != position;
    final locationChanged = oldPositionData != null && oldPositionData.location != location;
    final sizeChanged = oldPositionData != null && oldPositionData.size != size;
    
    if (suggestedAnimationType != null) {
      _logger.info(
        'CardPositionTracker.updateCardPosition() - Using suggested animation type: $suggestedAnimationType',
        isOn: LOGGING_SWITCH,
      );
      
      animationType = suggestedAnimationType;
      
      // Determine start position based on animation type
      if (suggestedAnimationType == AnimationType.collect) {
        // For collect, start position is discard pile (card is being collected from discard)
        final discardPilePosition = _positions[cardId]; // Discard pile tracks by cardId
        if (discardPilePosition != null && discardPilePosition.location == 'discard_pile') {
          startPosition = discardPilePosition.position;
          startSize = discardPilePosition.size;
        } else {
          // Fallback: try to find discard pile position
          final discardPilePos = _positions['discard_pile'];
          if (discardPilePos != null) {
            startPosition = discardPilePos.position;
            startSize = discardPilePos.size;
          } else {
            _logger.info(
              'CardPositionTracker.updateCardPosition() - Collect animation suggested but discard pile position not found',
              isOn: LOGGING_SWITCH,
            );
          }
        }
      } else if (suggestedAnimationType == AnimationType.draw) {
        // For draw, start position is draw pile
        final drawPilePosition = _positions['draw_pile'];
        if (drawPilePosition != null) {
          startPosition = drawPilePosition.position;
          startSize = drawPilePosition.size;
        } else {
          _logger.info(
            'CardPositionTracker.updateCardPosition() - Draw animation suggested but draw pile position not found',
            isOn: LOGGING_SWITCH,
          );
        }
      } else if (oldPositionData != null) {
        // For play and reposition, use old position as start
        startPosition = oldPositionData.position;
        startSize = oldPositionData.size;
      }
    } else {
      // PRIORITY 2: Position-based animation detection (fallback when no suggestion)
      if (isNewCard && isHandLocation) {
        // New card in hand without old position → draw from deck
        final drawPilePosition = _positions['draw_pile'];
        if (drawPilePosition != null) {
          animationType = AnimationType.draw;
          startPosition = drawPilePosition.position;
          startSize = drawPilePosition.size;
        } else {
          _logger.info(
            'CardPositionTracker.updateCardPosition() - New card in hand detected but draw pile position not found',
            isOn: LOGGING_SWITCH,
          );
        }
      } else if (oldPositionData != null) {
        final oldLocation = oldPositionData.location;
        final oldIsHand = oldLocation == 'my_hand' || oldLocation == 'opponent_hand';
        
        if (oldIsHand && isDiscardLocation) {
          // Card moved from hand to discard pile → play card
          animationType = AnimationType.play;
          startPosition = oldPositionData.position;
          startSize = oldPositionData.size;
          // End position is the discard pile position (already tracked as top card)
        } else if (oldLocation == 'discard_pile' && isHandLocation) {
          // Card moved from discard pile to hand → collect from discard
          animationType = AnimationType.collect;
          startPosition = oldPositionData.position;
          startSize = oldPositionData.size;
        } else if (oldIsHand && isHandLocation && positionChanged) {
          // Card repositioned within hand → same rank play
          animationType = AnimationType.reposition;
          startPosition = oldPositionData.position;
          startSize = oldPositionData.size;
        }
      }
    }
    
    // Trigger animation if detected and not already triggered recently
    if (animationType != null && startPosition != null && startSize != null) {
      // Check if we've already triggered this animation for this card
      final recentAnimation = _recentAnimations[key];
      final isDuplicate = recentAnimation == animationType;
      
      if (!isDuplicate) {
        // Mark this animation as triggered
        _recentAnimations[key] = animationType;
        
        // Clear the recent animation after a delay (longer than animation duration)
        // This prevents duplicate triggers while allowing re-triggers if card moves again
        Future.delayed(const Duration(milliseconds: 800), () {
          _recentAnimations.remove(key);
        });
        
        _triggerCardAnimation(
          cardId: cardId,
          key: key,
          animationType: animationType,
          startPosition: startPosition,
          endPosition: position,
          startSize: startSize,
          endSize: size,
          playerId: playerId,
        );
      } else {
        _logger.info(
          'CardPositionTracker.updateCardPosition() - Skipping duplicate animation: $animationType for key: $key',
          isOn: LOGGING_SWITCH,
        );
      }
    } else if (oldPositionData != null && (positionChanged || locationChanged || sizeChanged)) {
      // Position changed but no animation type detected
      _logger.info(
        'CardPositionTracker.updateCardPosition() - Position changed but no animation triggered:\n'
        '  oldLocation: ${oldPositionData.location}\n'
        '  newLocation: $location\n'
        '  positionChanged: $positionChanged\n'
        '  locationChanged: $locationChanged',
        isOn: LOGGING_SWITCH,
      );
    }

    // Update the position
    // If we found an old position with a different key (e.g., playerId prefix), remove it
    if (oldKey != key && oldPositionData != null) {
      _positions.remove(oldKey);
      _logger.info(
        'CardPositionTracker.updateCardPosition() - Removed old position entry with key: $oldKey',
        isOn: LOGGING_SWITCH,
      );
    }
    _positions[key] = newPositionData;

    _logger.info(
      'Card Position ${oldPositionData != null ? "Updated" : "Added"}:\n  key: $key\n  cardId: $cardId\n  position: (${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)})\n  size: (${size.width.toStringAsFixed(1)}, ${size.height.toStringAsFixed(1)})\n  location: $location${playerId != null ? '\n  playerId: $playerId' : ''}${playerStatus != null ? '\n  playerStatus: $playerStatus' : ''}\n  totalCardsTracked: ${_positions.length}',
      isOn: LOGGING_SWITCH,
    );
  }

  /// Trigger card animation based on detected animation type
  /// 
  /// This method is called when a card position change is detected that requires animation.
  /// It notifies the animation layer via ValueNotifier.
  void _triggerCardAnimation({
    required String cardId,
    required String key,
    required AnimationType animationType,
    required Offset startPosition,
    required Offset endPosition,
    required Size startSize,
    required Size endSize,
    String? playerId,
  }) {
    final animationTypeName = animationType.toString().split('.').last;
    _logger.info(
      'CardPositionTracker._triggerCardAnimation() - $animationTypeName ANIMATION TRIGGERED:\n'
      '  key: $key\n'
      '  cardId: $cardId\n'
      '  animationType: $animationTypeName\n'
      '  startPosition: (${startPosition.dx.toStringAsFixed(1)}, ${startPosition.dy.toStringAsFixed(1)})\n'
      '  endPosition: (${endPosition.dx.toStringAsFixed(1)}, ${endPosition.dy.toStringAsFixed(1)})\n'
      '  startSize: ${startSize.width.toStringAsFixed(1)}x${startSize.height.toStringAsFixed(1)}\n'
      '  endSize: ${endSize.width.toStringAsFixed(1)}x${endSize.height.toStringAsFixed(1)}\n'
      '  distance: ${(startPosition - endPosition).distance.toStringAsFixed(1)}px',
      isOn: LOGGING_SWITCH,
    );

    // Create animation trigger and notify listeners
    final trigger = CardAnimationTrigger(
      cardId: cardId,
      key: key,
      animationType: animationType,
      startPosition: startPosition,
      endPosition: endPosition,
      startSize: startSize,
      endSize: endSize,
      playerId: playerId,
    );

    // Notify animation layer
    cardAnimationTrigger.value = trigger;
  }

  /// Get the position data for a card
  /// 
  /// [cardId] - The unique identifier for the card
  /// [playerId] - Optional player ID for opponent cards
  /// Returns the CardPositionData if found, null otherwise
  CardPositionData? getCardPosition(String cardId, {String? playerId}) {
    final key = playerId != null ? '${playerId}_$cardId' : cardId;
    final positionData = _positions[key];
    
    if (positionData != null) {
      _logger.info(
        'CardPositionTracker.getCardPosition() - Found: key=$key, position=${positionData.position}, size=${positionData.size}',
        isOn: LOGGING_SWITCH,
      );
    } else {
      _logger.info(
        'CardPositionTracker.getCardPosition() - Not found: key=$key',
        isOn: LOGGING_SWITCH,
      );
    }
    
    return positionData;
  }

  /// Clear all tracked positions
  void clearAllPositions() {
    final count = _positions.length;
    _positions.clear();
    _recentAnimations.clear(); // Clear recent animations tracking
    cardAnimationTrigger.value = null; // Clear any pending animation triggers
    _logger.info(
      'CardPositionTracker.clearAllPositions() - Cleared $count position(s)',
      isOn: LOGGING_SWITCH,
    );
  }

  /// Notify that an animation has completed
  /// 
  /// This is called by CardAnimationLayer when an animation finishes.
  /// Widgets can listen to cardAnimationComplete to react to animation completion.
  void notifyAnimationComplete({
    required String cardId,
    required String key,
    required AnimationType animationType,
    String? playerId,
  }) {
    final completion = CardAnimationComplete(
      cardId: cardId,
      key: key,
      animationType: animationType,
      playerId: playerId,
    );
    
    _logger.info(
      'CardPositionTracker.notifyAnimationComplete() - Animation completed:\n'
      '  key: $key\n'
      '  cardId: $cardId\n'
      '  animationType: ${animationType.toString().split('.').last}',
      isOn: LOGGING_SWITCH,
    );
    
    cardAnimationComplete.value = completion;
    
    // Clear the completion event after notifying (similar to trigger pattern)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      cardAnimationComplete.value = null;
    });
  }

  /// Dispose resources (call when tracker is no longer needed)
  void dispose() {
    cardAnimationTrigger.dispose();
    cardAnimationComplete.dispose();
  }

  /// Log all currently tracked positions
  void logAllPositions() {
    _logger.info(
      'CardPositionTracker.logAllPositions() called - total positions: ${_positions.length}',
      isOn: LOGGING_SWITCH,
    );
    
    if (_positions.isEmpty) {
      _logger.info('CardPositionTracker: No positions tracked', isOn: LOGGING_SWITCH);
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('=== Card Position Tracker - All Positions ===');
    buffer.writeln('Total cards tracked: ${_positions.length}');
    buffer.writeln('');

    // Group by location for better readability
    final byLocation = <String, List<MapEntry<String, CardPositionData>>>{};
    for (final entry in _positions.entries) {
      final location = entry.value.location;
      byLocation.putIfAbsent(location, () => []).add(entry);
    }

    for (final location in byLocation.keys.toList()..sort()) {
      buffer.writeln('--- $location (${byLocation[location]!.length} cards) ---');
      for (final entry in byLocation[location]!) {
        final data = entry.value;
        buffer.writeln('  ${entry.key}: ${data.position.dx.toStringAsFixed(1)}, ${data.position.dy.toStringAsFixed(1)} | ${data.size.width.toStringAsFixed(1)}x${data.size.height.toStringAsFixed(1)}${data.playerId != null ? ' | playerId: ${data.playerId}' : ''}');
      }
      buffer.writeln('');
    }

    buffer.writeln('===========================================');

    _logger.info(buffer.toString(), isOn: LOGGING_SWITCH);
  }

  /// Get all positions (for internal use or testing)
  Map<String, CardPositionData> getAllPositions() {
    return Map.unmodifiable(_positions);
  }
}

