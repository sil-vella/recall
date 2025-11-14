import 'package:flutter/material.dart';
import '../../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = true;

/// Position data for a tracked card
class CardPositionData {
  final Offset position;
  final Size size;
  final String location;
  final String? playerId;
  final DateTime lastUpdated;

  CardPositionData({
    required this.position,
    required this.size,
    required this.location,
    this.playerId,
  }) : lastUpdated = DateTime.now();

  @override
  String toString() {
    return 'CardPositionData(position: ${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)}, size: ${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}, location: $location, playerId: $playerId)';
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
  void updateCardPosition(
    String cardId,
    Offset position,
    Size size,
    String location, {
    String? playerId,
  }) {
    _logger.info(
      'CardPositionTracker.updateCardPosition() called - cardId: $cardId, location: $location${playerId != null ? ', playerId: $playerId' : ''}',
      isOn: LOGGING_SWITCH,
    );

    // Create composite key for opponent cards
    final key = playerId != null ? '${playerId}_$cardId' : cardId;

    final wasExisting = _positions.containsKey(key);
    _positions[key] = CardPositionData(
      position: position,
      size: size,
      location: location,
      playerId: playerId,
    );

    _logger.info(
      'Card Position ${wasExisting ? "Updated" : "Added"}:\n  key: $key\n  cardId: $cardId\n  position: (${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)})\n  size: (${size.width.toStringAsFixed(1)}, ${size.height.toStringAsFixed(1)})\n  location: $location${playerId != null ? '\n  playerId: $playerId' : ''}\n  totalCardsTracked: ${_positions.length}',
      isOn: LOGGING_SWITCH,
    );
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
    _logger.info(
      'CardPositionTracker.clearAllPositions() - Cleared $count position(s)',
      isOn: LOGGING_SWITCH,
    );
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

