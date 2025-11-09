import 'package:flutter/material.dart';
import '../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = true;

/// Represents a card's position and size on screen
class CardPosition {
  final String cardId;
  final Offset position; // Top-left corner in global coordinates
  final Size size;
  final String location; // 'my_hand', 'opponent_hand', 'discard_pile', 'draw_pile'
  final String? playerId; // For player hands
  final int? index; // Position in hand/pile

  const CardPosition({
    required this.cardId,
    required this.position,
    required this.size,
    required this.location,
    this.playerId,
    this.index,
  });

  /// Create a copy with updated properties
  CardPosition copyWith({
    String? cardId,
    Offset? position,
    Size? size,
    String? location,
    String? playerId,
    int? index,
  }) {
    return CardPosition(
      cardId: cardId ?? this.cardId,
      position: position ?? this.position,
      size: size ?? this.size,
      location: location ?? this.location,
      playerId: playerId ?? this.playerId,
      index: index ?? this.index,
    );
  }

  /// Check if this position is significantly different from another
  bool isDifferentFrom(CardPosition other, {double threshold = 5.0}) {
    if (cardId != other.cardId) return true;
    if (location != other.location) return true;
    if (playerId != other.playerId) return true;
    
    // Check position difference
    final positionDiff = (position - other.position).distance;
    if (positionDiff > threshold) return true;
    
    // Check size difference
    final sizeDiff = (size.width - other.size.width).abs() + 
                     (size.height - other.size.height).abs();
    if (sizeDiff > threshold) return true;
    
    return false;
  }

  @override
  String toString() => 'CardPosition($cardId, $location, ${position.dx.toStringAsFixed(1)},${position.dy.toStringAsFixed(1)}, ${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)})';
}

/// Represents a card movement from old position to new position
class CardMovement {
  final CardPosition old;
  final CardPosition new_;

  const CardMovement({
    required this.old,
    required this.new_,
  });
}

/// Utility class to track and calculate card positions on screen
class CardPositionTracker {
  static final CardPositionTracker _instance = CardPositionTracker._internal();
  factory CardPositionTracker() => _instance;
  CardPositionTracker._internal();

  final Logger _logger = Logger();
  
  /// Map of cardId -> CardPosition for current positions
  final Map<String, CardPosition> _currentPositions = {};

  /// Map of cardId -> CardPosition for previous positions (for comparison)
  final Map<String, CardPosition> _previousPositions = {};

  /// Register a card's current position
  void registerCardPosition(CardPosition position) {
    _logger.info('🎬 CardPositionTracker: Registering position for ${position.cardId} at ${position.location} (${position.position.dx.toStringAsFixed(1)}, ${position.position.dy.toStringAsFixed(1)})', isOn: LOGGING_SWITCH);
    _currentPositions[position.cardId] = position;
  }

  /// Register multiple card positions at once
  void registerCardPositions(List<CardPosition> positions) {
    for (final position in positions) {
      registerCardPosition(position);
    }
  }

  /// Get current position for a card
  CardPosition? getCardPosition(String cardId) {
    return _currentPositions[cardId];
  }

  /// Get all current positions
  Map<String, CardPosition> getAllPositions() {
    return Map.unmodifiable(_currentPositions);
  }

  /// Calculate position from a GlobalKey
  /// Returns null if the key is not attached or not in the render tree
  CardPosition? calculatePositionFromKey(
    GlobalKey key,
    String cardId,
    String location, {
    String? playerId,
    int? index,
  }) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject == null || renderObject is! RenderBox) {
      _logger.info('🎬 CardPositionTracker: Cannot calculate position for $cardId - renderObject is null or not RenderBox', isOn: LOGGING_SWITCH);
      return null;
    }

    final renderBox = renderObject;
    
    // Get position in global coordinates
    final position = renderBox.localToGlobal(Offset.zero);
    
    // Get size
    final size = renderBox.size;
    
    _logger.info('🎬 CardPositionTracker: Calculated position for $cardId: (${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)}), size: ${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}', isOn: LOGGING_SWITCH);

    return CardPosition(
      cardId: cardId,
      position: position,
      size: size,
      location: location,
      playerId: playerId,
      index: index,
    );
  }

  /// Save current positions as previous positions (before state update)
  void saveCurrentAsPrevious() {
    _previousPositions.clear();
    _previousPositions.addAll(_currentPositions);
  }

  /// Detect card movements by comparing current and previous positions
  /// Returns list of movements: (oldPosition, newPosition)
  List<CardMovement> detectMovements() {
    final movements = <CardMovement>[];
    
    _logger.info('🎬 CardPositionTracker: Detecting movements - current: ${_currentPositions.length}, previous: ${_previousPositions.length}', isOn: LOGGING_SWITCH);

    // Check for cards that moved (exist in both old and new, but different position)
    for (final entry in _currentPositions.entries) {
      final cardId = entry.key;
      final newPosition = entry.value;
      final oldPosition = _previousPositions[cardId];

      if (oldPosition != null) {
        // Card exists in both old and new positions
        if (oldPosition.isDifferentFrom(newPosition)) {
          _logger.info('🎬 CardPositionTracker: Detected movement for $cardId: ${oldPosition.location} -> ${newPosition.location}', isOn: LOGGING_SWITCH);
          movements.add(CardMovement(old: oldPosition, new_: newPosition));
        }
      } else {
        // Card appeared (exists in new but not old)
        _logger.info('🎬 CardPositionTracker: Card $cardId appeared (new position)', isOn: LOGGING_SWITCH);
        // This is handled separately - we don't animate appearance
      }
    }

    // Check for cards that disappeared (exist in old but not new)
    for (final entry in _previousPositions.entries) {
      final cardId = entry.key;
      if (!_currentPositions.containsKey(cardId)) {
        // Card disappeared - this will be handled by the destination widget
        // when it appears in a new location
      }
    }

    return movements;
  }

  /// Clear all positions
  void clear() {
    _currentPositions.clear();
    _previousPositions.clear();
  }

  /// Clear positions for a specific location
  void clearLocation(String location) {
    _currentPositions.removeWhere((_, position) => position.location == location);
    _previousPositions.removeWhere((_, position) => position.location == location);
  }

  /// Remove a specific card's position
  void removeCardPosition(String cardId) {
    _currentPositions.remove(cardId);
    _previousPositions.remove(cardId);
  }

  /// Get count of tracked positions
  int get positionCount => _currentPositions.length;
}

