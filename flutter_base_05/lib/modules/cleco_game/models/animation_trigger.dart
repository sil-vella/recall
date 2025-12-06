import 'package:flutter/material.dart';

/// Represents an animation trigger for card movements
/// 
/// Contains all information needed to animate a card from one location to another
class AnimationTrigger {
  final String cardId;
  final Map<String, dynamic>? cardData; // Full card data or null
  final Offset startPosition;
  final Size startSize;
  final Offset endPosition;
  final Size endSize;
  final String animationType; // 'draw', 'play', 'reposition', 'collect', 'jack_swap'
  final String startLocation; // 'draw_pile', 'my_hand', 'opponent_hand', 'discard_pile'
  final String endLocation;
  final DateTime timestamp;
  bool isComplete;
  
  AnimationTrigger({
    required this.cardId,
    this.cardData,
    required this.startPosition,
    required this.startSize,
    required this.endPosition,
    required this.endSize,
    required this.animationType,
    required this.startLocation,
    required this.endLocation,
    this.isComplete = false,
  }) : timestamp = DateTime.now();
  
  /// Create a copy with updated completion status
  AnimationTrigger copyWith({bool? isComplete}) {
    return AnimationTrigger(
      cardId: cardId,
      cardData: cardData,
      startPosition: startPosition,
      startSize: startSize,
      endPosition: endPosition,
      endSize: endSize,
      animationType: animationType,
      startLocation: startLocation,
      endLocation: endLocation,
      isComplete: isComplete ?? this.isComplete,
    );
  }
  
  @override
  String toString() {
    return 'AnimationTrigger(cardId: $cardId, type: $animationType, from: $startLocation, to: $endLocation, complete: $isComplete)';
  }
}

