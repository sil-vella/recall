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

  /// Map of location -> CardPosition for static positions (draw_pile, discard_pile)
  /// These positions are cached once at match start and don't change
  final Map<String, CardPosition> _staticPositions = {};

  /// Check if a location is static (draw_pile or discard_pile)
  bool isStaticLocation(String location) {
    return location == 'draw_pile' || location == 'discard_pile';
  }

  /// Cache a static position (draw_pile or discard_pile)
  /// This should be called once at match start
  void cacheStaticPosition(String location, Offset position, Size size) {
    if (!isStaticLocation(location)) {
      _logger.warning('🎬 CardPositionTracker: Attempted to cache non-static location: $location', isOn: LOGGING_SWITCH);
      return;
    }

    // Create a placeholder CardPosition for the static location
    // The cardId is not important for static positions, we use the location as identifier
    final staticPosition = CardPosition(
      cardId: '_static_$location', // Placeholder ID
      position: position,
      size: size,
      location: location,
    );

    _staticPositions[location] = staticPosition;
    _logger.info('🎬 CardPositionTracker: Cached static position for $location at (${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)}), size: ${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}', isOn: LOGGING_SWITCH);
  }

  /// Get cached static position for a location
  CardPosition? getStaticPosition(String location) {
    return _staticPositions[location];
  }

  /// Check if a static position is cached
  bool hasStaticPosition(String location) {
    return _staticPositions.containsKey(location);
  }

  /// Register a card's current position
  /// For static locations (draw_pile, discard_pile), this only logs and doesn't register
  void registerCardPosition(CardPosition position) {
    // Skip registration for static locations - they use cached positions
    if (isStaticLocation(position.location)) {
      _logger.info('🎬 CardPositionTracker: Skipping registration for static location ${position.location} (cardId: ${position.cardId})', isOn: LOGGING_SWITCH);
      return;
    }

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

  /// Get all previous positions (for debugging)
  Map<String, CardPosition> getAllPreviousPositions() {
    return Map.unmodifiable(_previousPositions);
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
  /// Only saves hand positions, not static positions (which remain cached)
  void saveCurrentAsPrevious() {
    _previousPositions.clear();
    // Only save hand positions, skip static locations
    for (final entry in _currentPositions.entries) {
      if (!isStaticLocation(entry.value.location)) {
        _previousPositions[entry.key] = entry.value;
      }
    }
  }

  /// Detect card movements by comparing current and previous positions
  /// Uses cached static positions for draw_pile and discard_pile
  /// Returns list of movements: (oldPosition, newPosition)
  List<CardMovement> detectMovements() {
    final movements = <CardMovement>[];
    
    _logger.info('🎬 CardPositionTracker: Detecting movements - current: ${_currentPositions.length}, previous: ${_previousPositions.length}, static: ${_staticPositions.length}', isOn: LOGGING_SWITCH);
    
    // Log previous positions for debugging
    _logger.info('🎬 CardPositionTracker: Previous positions:', isOn: LOGGING_SWITCH);
    for (final entry in _previousPositions.entries) {
      _logger.info('🎬 CardPositionTracker:   Previous: ${entry.key} at ${entry.value.location}', isOn: LOGGING_SWITCH);
    }
    
    // Log current positions for debugging
    _logger.info('🎬 CardPositionTracker: Current positions:', isOn: LOGGING_SWITCH);
    for (final entry in _currentPositions.entries) {
      _logger.info('🎬 CardPositionTracker:   Current: ${entry.key} at ${entry.value.location}', isOn: LOGGING_SWITCH);
    }

    // Log static positions for debugging
    _logger.info('🎬 CardPositionTracker: Static positions:', isOn: LOGGING_SWITCH);
    for (final entry in _staticPositions.entries) {
      _logger.info('🎬 CardPositionTracker:   Static: ${entry.key} at (${entry.value.position.dx.toStringAsFixed(1)}, ${entry.value.position.dy.toStringAsFixed(1)})', isOn: LOGGING_SWITCH);
    }

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
        } else {
          _logger.info('🎬 CardPositionTracker: Card $cardId at same position (${oldPosition.location})', isOn: LOGGING_SWITCH);
        }
      } else {
        // Card appeared in hand (exists in new but not old)
        // Check if it came from draw_pile (use cached static position)
        if (newPosition.location == 'my_hand' || newPosition.location == 'opponent_hand') {
          final drawPilePosition = getStaticPosition('draw_pile');
          if (drawPilePosition != null) {
            // Create a CardPosition for this specific card at draw_pile
            final fromDrawPile = drawPilePosition.copyWith(cardId: cardId);
            _logger.info('🎬 CardPositionTracker: Card $cardId appeared in hand, animating from draw_pile', isOn: LOGGING_SWITCH);
            movements.add(CardMovement(old: fromDrawPile, new_: newPosition));
          } else {
            _logger.info('🎬 CardPositionTracker: Card $cardId appeared at ${newPosition.location} (draw_pile position not cached yet)', isOn: LOGGING_SWITCH);
          }
        }
      }
    }

    // Check for cards that disappeared from hands (exist in old but not new)
    // These likely moved to discard_pile
    for (final entry in _previousPositions.entries) {
      final cardId = entry.key;
      final oldPosition = entry.value;
      
      if (!_currentPositions.containsKey(cardId)) {
        // Card disappeared from hand
        // Check if it should animate to discard_pile (use cached static position)
        if (oldPosition.location == 'my_hand' || oldPosition.location == 'opponent_hand') {
          final discardPilePosition = getStaticPosition('discard_pile');
          if (discardPilePosition != null) {
            // Create a CardPosition for this specific card at discard_pile
            final toDiscardPile = discardPilePosition.copyWith(cardId: cardId);
            _logger.info('🎬 CardPositionTracker: Card $cardId disappeared from hand, animating to discard_pile', isOn: LOGGING_SWITCH);
            movements.add(CardMovement(old: oldPosition, new_: toDiscardPile));
          } else {
            _logger.info('🎬 CardPositionTracker: Card $cardId disappeared from ${oldPosition.location} (discard_pile position not cached yet)', isOn: LOGGING_SWITCH);
          }
        } else {
          _logger.info('🎬 CardPositionTracker: Card $cardId disappeared from ${oldPosition.location} (not in current positions)', isOn: LOGGING_SWITCH);
        }
      }
    }

    return movements;
  }

  /// Clear all positions (including static positions)
  void clear() {
    _currentPositions.clear();
    _previousPositions.clear();
    _staticPositions.clear();
  }

  /// Clear only dynamic positions (keep static positions cached)
  void clearDynamicPositions() {
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
    _logger.info('🎬 CardPositionTracker: Removed position registration for $cardId', isOn: LOGGING_SWITCH);
  }

  /// Get count of tracked positions
  int get positionCount => _currentPositions.length;
}

