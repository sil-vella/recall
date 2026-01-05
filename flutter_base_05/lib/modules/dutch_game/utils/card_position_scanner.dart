import 'package:flutter/material.dart';
import '../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = false; // Enabled for testing and debugging

/// Represents a card's position and metadata on screen
class CardPosition {
  final String cardId;
  final Offset position; // Global coordinates (top-left)
  final Size size;
  final String location; // 'my_hand', 'opponent_hand_{playerId}', 'draw_pile', 'discard_pile'
  final String? playerId; // For opponent cards
  final bool isFaceUp; // true for face up, false for face down
  final int? index; // Position in hand (for ordering)

  const CardPosition({
    required this.cardId,
    required this.position,
    required this.size,
    required this.location,
    this.playerId,
    required this.isFaceUp,
    this.index,
  });

  /// Create a copy with updated properties
  CardPosition copyWith({
    String? cardId,
    Offset? position,
    Size? size,
    String? location,
    String? playerId,
    bool? isFaceUp,
    int? index,
  }) {
    return CardPosition(
      cardId: cardId ?? this.cardId,
      position: position ?? this.position,
      size: size ?? this.size,
      location: location ?? this.location,
      playerId: playerId ?? this.playerId,
      isFaceUp: isFaceUp ?? this.isFaceUp,
      index: index ?? this.index,
    );
  }

  /// Check if this position is significantly different from another
  /// Returns true only if the card has moved to a different location OR
  /// has moved significantly within the same location (above threshold)
  bool isDifferentFrom(CardPosition other, {double threshold = 10.0}) {
    if (cardId != other.cardId) return true;
    
    // If location changed, it's definitely different (different pile/hand)
    if (location != other.location) return true;
    if (playerId != other.playerId) return true;
    
    // For same location, only consider it different if position moved significantly
    // This prevents minor layout shifts from triggering animations
    final positionDiff = (position - other.position).distance;
    if (positionDiff > threshold) return true;
    
    // Check size difference (shouldn't happen, but just in case)
    final sizeDiff = (size.width - other.size.width).abs() + 
                     (size.height - other.size.height).abs();
    if (sizeDiff > threshold) return true;
    
    return false;
  }

  @override
  String toString() => 'CardPosition($cardId, $location, ${position.dx.toStringAsFixed(1)},${position.dy.toStringAsFixed(1)}, ${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}, faceUp: $isFaceUp)';
}

/// Data structure for card key information
class CardKeyData {
  final GlobalKey key;
  final String location;
  final bool isFaceUp;
  final String? playerId;
  final int? index;

  const CardKeyData({
    required this.key,
    required this.location,
    required this.isFaceUp,
    this.playerId,
    this.index,
  });
}

/// Utility class to scan and track all card positions on screen
class CardPositionScanner {
  static final CardPositionScanner _instance = CardPositionScanner._internal();
  factory CardPositionScanner() => _instance;
  CardPositionScanner._internal();

  final Logger _logger = Logger();
  
  /// Map of cardId -> CardPosition for current positions
  final Map<String, CardPosition> _currentPositions = {};

  /// Map of cardId -> CardPosition for previous positions (for comparison)
  final Map<String, CardPosition> _previousPositions = {};

  /// Scan all cards and update positions
  /// 
  /// **State Update Handling**:
  /// - If cardId is missing from scan but exists in previous positions → preserve old position (state still updating)
  /// - If cardId appears in 2 different positions → use the NEW position (state still updating, prefer latest)
  /// 
  /// Returns map of cardId -> CardPosition
  Map<String, CardPosition> scanAllCards(
    BuildContext context,
    Map<String, CardKeyData> cardKeys,
  ) {
    // First, scan all provided card keys
    // If same cardId found multiple times, overwrite with latest (newest position)
    final Map<String, CardPosition> scannedPositions = {};
    
    for (final entry in cardKeys.entries) {
      final cardId = entry.key;
      final keyData = entry.value;
      
      final position = _calculatePositionFromKey(
        keyData.key,
        cardId,
        keyData.location,
        isFaceUp: keyData.isFaceUp,
        playerId: keyData.playerId,
        index: keyData.index,
      );
      
      if (position != null) {
        // If duplicate cardId, overwrite with latest (newest position)
        scannedPositions[cardId] = position;
        _logger.info('🎬 CardPositionScanner: Scanned $cardId at $keyData.location (${position.position.dx.toStringAsFixed(1)}, ${position.position.dy.toStringAsFixed(1)})', isOn: LOGGING_SWITCH);
      } else {
        _logger.info('🎬 CardPositionScanner: Cannot calculate position for $cardId - renderObject not available', isOn: LOGGING_SWITCH);
      }
    }
    
    // Merge with previous positions (preserve missing cardIds - state still updating)
    for (final entry in _previousPositions.entries) {
      if (!scannedPositions.containsKey(entry.key)) {
        // Preserve old position - state still updating, card not in current scan
        scannedPositions[entry.key] = entry.value;
        _logger.info('🎬 CardPositionScanner: Preserved position for $entry.key (missing from scan, state still updating)', isOn: LOGGING_SWITCH);
      }
    }
    
    // Update current positions
    _currentPositions.clear();
    _currentPositions.addAll(scannedPositions);
    
    _logger.info('🎬 CardPositionScanner: Scan complete - ${_currentPositions.length} positions tracked', isOn: LOGGING_SWITCH);
    
    return Map.unmodifiable(_currentPositions);
  }

  /// Calculate position from a GlobalKey
  /// Returns null if the key is not attached or not in the render tree
  CardPosition? _calculatePositionFromKey(
    GlobalKey key,
    String cardId,
    String location, {
    required bool isFaceUp,
    String? playerId,
    int? index,
  }) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject == null || renderObject is! RenderBox) {
      return null;
    }

    final renderBox = renderObject;
    
    // Get position in global coordinates
    final position = renderBox.localToGlobal(Offset.zero);
    
    // Get size
    final size = renderBox.size;
    
    return CardPosition(
      cardId: cardId,
      position: position,
      size: size,
      location: location,
      playerId: playerId,
      isFaceUp: isFaceUp,
      index: index,
    );
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

  /// Save current positions as previous positions (before next scan)
  void saveCurrentAsPrevious() {
    _previousPositions.clear();
    _previousPositions.addAll(_currentPositions);
    _logger.info('🎬 CardPositionScanner: Saved ${_previousPositions.length} positions as previous', isOn: LOGGING_SWITCH);
  }

  /// Clear all positions (including previous)
  void clearPositions() {
    _currentPositions.clear();
    _previousPositions.clear();
    _logger.info('🎬 CardPositionScanner: Cleared all positions', isOn: LOGGING_SWITCH);
  }

  /// Remove a specific card's position
  void removeCardPosition(String cardId) {
    _currentPositions.remove(cardId);
    _previousPositions.remove(cardId);
    _logger.info('🎬 CardPositionScanner: Removed position for $cardId', isOn: LOGGING_SWITCH);
  }

  /// Get count of tracked positions
  int get positionCount => _currentPositions.length;
}

