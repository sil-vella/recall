import 'package:flutter/material.dart';

/// PlayScreenFunctions provides utility methods for game play screen operations,
/// including getting RenderBox information for UI elements.
class PlayScreenFunctions {
  final GlobalKey? drawPileKey;
  final GlobalKey? discardPileKey;
  final GlobalKey? gameBoardKey;

  // ========== Pile Position and Size Tracking ==========
  /// Position and size for draw pile (updated rate-limited)
  Map<String, dynamic>? _drawPileBounds;
  
  /// Position and size for discard pile (updated rate-limited)
  Map<String, dynamic>? _discardPileBounds;
  
  /// Position and size for game board (updated rate-limited)
  Map<String, dynamic>? _gameBoardBounds;
  
  /// Position and size for individual my hand cards (index -> bounds with key info)
  final Map<int, Map<String, dynamic>> _myHandCardBounds = {};
  
  /// Key strings for individual my hand cards (index -> key string)
  final Map<int, String> _myHandCardKeys = {};
  
  /// Position and size for individual opponent cards (playerId -> index -> bounds)
  final Map<String, Map<int, Map<String, dynamic>>> _opponentCardBounds = {};
  
  /// Key strings for individual opponent cards (playerId -> index -> key string)
  final Map<String, Map<int, String>> _opponentCardKeys = {};
  
  /// Timestamp of last position update (for rate limiting)
  DateTime? _lastPositionUpdateTime;
  
  /// Rate limit duration for position updates (5 seconds)
  static const Duration _positionUpdateRateLimit = Duration(seconds: 5);
  
  /// Flag to prevent multiple pending updates
  bool _isPositionUpdatePending = false;

  /// Create a new PlayScreenFunctions instance with the provided GlobalKeys
  PlayScreenFunctions({
    this.drawPileKey,
    this.discardPileKey,
    this.gameBoardKey,
  });

  /// Get RenderBox for draw pile widget
  /// Returns null if the widget is not yet rendered or key is not provided
  RenderBox? getDrawPileRenderBox() {
    if (drawPileKey == null) return null;
    final context = drawPileKey!.currentContext;
    if (context != null) {
      return context.findRenderObject() as RenderBox?;
    }
    return null;
  }

  /// Get RenderBox for discard pile widget
  /// Returns null if the widget is not yet rendered or key is not provided
  RenderBox? getDiscardPileRenderBox() {
    if (discardPileKey == null) return null;
    final context = discardPileKey!.currentContext;
    if (context != null) {
      return context.findRenderObject() as RenderBox?;
    }
    return null;
  }

  /// Get RenderBox for a card widget by its GlobalKey
  /// Returns null if the widget is not yet rendered or key is not provided
  RenderBox? getCardRenderBox(GlobalKey? cardKey) {
    if (cardKey == null) return null;
    final context = cardKey.currentContext;
    if (context != null) {
      return context.findRenderObject() as RenderBox?;
    }
    return null;
  }

  /// Get RenderBox for game board widget
  /// Returns null if the widget is not yet rendered or key is not provided
  RenderBox? getGameBoardRenderBox() {
    if (gameBoardKey == null) return null;
    final context = gameBoardKey!.currentContext;
    if (context != null) {
      return context.findRenderObject() as RenderBox?;
    }
    return null;
  }

  /// Get the position and size of the draw pile widget
  /// Returns a map with 'position' (Offset) and 'size' (Size), or null if not available
  Map<String, dynamic>? getDrawPileBounds() {
    final renderBox = getDrawPileRenderBox();
    if (renderBox == null) return null;
    return {
      'position': renderBox.localToGlobal(Offset.zero),
      'size': renderBox.size,
    };
  }

  /// Get the position and size of the discard pile widget
  /// Returns a map with 'position' (Offset) and 'size' (Size), or null if not available
  Map<String, dynamic>? getDiscardPileBounds() {
    final renderBox = getDiscardPileRenderBox();
    if (renderBox == null) return null;
    return {
      'position': renderBox.localToGlobal(Offset.zero),
      'size': renderBox.size,
    };
  }

  /// Get the position and size of a card widget by its GlobalKey
  /// Returns a map with 'position' (Offset) and 'size' (Size), or null if not available
  Map<String, dynamic>? getCardBounds(GlobalKey? cardKey) {
    final renderBox = getCardRenderBox(cardKey);
    if (renderBox == null) return null;
    return {
      'position': renderBox.localToGlobal(Offset.zero),
      'size': renderBox.size,
    };
  }

  /// Get the position and size of the game board widget
  /// Returns a map with 'position' (Offset) and 'size' (Size), or null if not available
  Map<String, dynamic>? getGameBoardBounds() {
    final renderBox = getGameBoardRenderBox();
    if (renderBox == null) return null;
    return {
      'position': renderBox.localToGlobal(Offset.zero),
      'size': renderBox.size,
    };
  }

  // ========== Position and Size Update Methods ==========
  
  /// Update pile positions and sizes (rate-limited to once per 5 seconds)
  /// Uses postFrameCallback to ensure widgets are fully built and positioned
  /// [onUpdate] optional callback for logging or notification when update occurs
  /// [onBoundsChanged] optional callback called when bounds are actually updated (for triggering rebuilds)
  void updatePilePositions({
    void Function(String message)? onUpdate,
    void Function()? onBoundsChanged,
  }) {
    // Prevent multiple pending updates
    if (_isPositionUpdatePending) {
      return;
    }
    
    _isPositionUpdatePending = true;
    
    // Use postFrameCallback to ensure widgets are fully built and positioned
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Check rate limit inside callback (after widgets are built)
        final now = DateTime.now();
        if (_lastPositionUpdateTime != null) {
          final timeSinceLastUpdate = now.difference(_lastPositionUpdateTime!);
          if (timeSinceLastUpdate < _positionUpdateRateLimit) {
            // Too soon, skip update but reset flag
            _isPositionUpdatePending = false;
            return;
          }
        }
        
        // Track if any bounds actually changed
        bool boundsChanged = false;
        
        // Helper function to check if bounds actually changed
        bool _boundsChanged(Map<String, dynamic>? oldBounds, Map<String, dynamic>? newBounds) {
          if (oldBounds == null && newBounds == null) return false;
          if (oldBounds == null || newBounds == null) return true;
          
          final oldPos = oldBounds['position'] as Offset?;
          final newPos = newBounds['position'] as Offset?;
          final oldSize = oldBounds['size'] as Size?;
          final newSize = newBounds['size'] as Size?;
          
          if (oldPos == null || newPos == null || oldSize == null || newSize == null) {
            return oldBounds != newBounds;
          }
          
          return oldPos != newPos || oldSize != newSize;
        }
        
        // Update draw pile bounds
        final drawPileBounds = getDrawPileBounds();
        if (drawPileBounds != null) {
          if (_boundsChanged(_drawPileBounds, drawPileBounds)) {
            boundsChanged = true;
          }
          _drawPileBounds = drawPileBounds;
        }
        
        // Update discard pile bounds
        final discardPileBounds = getDiscardPileBounds();
        if (discardPileBounds != null) {
          if (_boundsChanged(_discardPileBounds, discardPileBounds)) {
            boundsChanged = true;
          }
          _discardPileBounds = discardPileBounds;
        }
        
        // Note: My hand cards are tracked individually via updateMyHandCardBounds()
        // They are not updated here in the bulk update
        
        // Update game board bounds
        final gameBoardBounds = getGameBoardBounds();
        if (gameBoardBounds != null) {
          if (_boundsChanged(_gameBoardBounds, gameBoardBounds)) {
            boundsChanged = true;
          }
          _gameBoardBounds = gameBoardBounds;
        }
        
        // Update timestamp
        _lastPositionUpdateTime = DateTime.now();
        
        if (onUpdate != null) {
          onUpdate('Updated pile positions - Draw: $_drawPileBounds, Discard: $_discardPileBounds');
        }
        
        // Notify that bounds changed (for triggering widget rebuilds)
        if (boundsChanged && onBoundsChanged != null) {
          onBoundsChanged();
        }
      } catch (e) {
        if (onUpdate != null) {
          onUpdate('Error updating pile positions: $e');
        }
      } finally {
        _isPositionUpdatePending = false;
      }
    });
  }
  
  /// Get cached draw pile bounds (position and size)
  /// Returns the last cached value, or null if not yet updated
  Map<String, dynamic>? getCachedDrawPileBounds() => _drawPileBounds;
  
  /// Get cached discard pile bounds (position and size)
  /// Returns the last cached value, or null if not yet updated
  Map<String, dynamic>? getCachedDiscardPileBounds() => _discardPileBounds;
  
  /// Callback for when card bounds change (set by unified widget)
  void Function()? onCardBoundsChanged;
  
  /// Update bounds for a specific my hand card by index
  /// [index] The index of the card in the hand
  /// [cardKey] The GlobalKey for the card widget
  /// [keyString] Optional key string for labeling (if not provided, will try to extract from GlobalKey)
  /// Returns true if bounds were updated
  bool updateMyHandCardBounds(int index, GlobalKey? cardKey, {String? keyString}) {
    final bounds = getCardBounds(cardKey);
    if (bounds == null) return false;
    
    final oldBounds = _myHandCardBounds[index];
    bool changed = false;
    
    if (oldBounds == null) {
      changed = true;
    } else {
      final oldPos = oldBounds['position'] as Offset?;
      final newPos = bounds['position'] as Offset?;
      final oldSize = oldBounds['size'] as Size?;
      final newSize = bounds['size'] as Size?;
      
      if (oldPos != newPos || oldSize != newSize) {
        changed = true;
      }
    }
    
    if (changed) {
      _myHandCardBounds[index] = bounds;
      // Store the key string for labeling
      if (keyString != null) {
        _myHandCardKeys[index] = keyString;
      } else if (cardKey != null) {
        // Try to get debugLabel from GlobalKey, or use toString as fallback
        final keyStr = cardKey.toString();
        // Extract the key identifier from the string representation
        // Format is usually something like: [GlobalKey#abc123 my_hand_user123_my_hand_0]
        // We'll try to extract the meaningful part
        final match = RegExp(r'\[GlobalKey[^\]]* ([^\]]+)\]').firstMatch(keyStr);
        _myHandCardKeys[index] = match?.group(1) ?? keyStr;
      }
      // Notify that bounds changed
      if (onCardBoundsChanged != null) {
        onCardBoundsChanged!();
      }
    }
    
    return changed;
  }
  
  /// Get cached bounds for a specific my hand card by index
  /// Returns the last cached value, or null if not yet updated
  Map<String, dynamic>? getCachedMyHandCardBounds(int index) => _myHandCardBounds[index];
  
  /// Get all cached my hand card bounds
  /// Returns a map of index -> bounds
  Map<int, Map<String, dynamic>> getCachedMyHandCardBoundsAll() => Map.from(_myHandCardBounds);
  
  /// Get all cached my hand card keys
  /// Returns a map of index -> key string
  Map<int, String> getCachedMyHandCardKeysAll() => Map.from(_myHandCardKeys);
  
  /// Clear bounds for my hand cards that are no longer present
  /// [currentIndices] List of indices that currently have cards
  /// [maxIndex] Maximum valid index (cards.length - 1), to clear indices beyond the list
  void clearMissingMyHandCardBounds(List<int> currentIndices, {int? maxIndex}) {
    final currentIndicesSet = currentIndices.toSet();
    final indicesToRemove = <int>[];
    
    // Remove indices that are not in current list
    for (final index in _myHandCardBounds.keys) {
      if (!currentIndicesSet.contains(index)) {
        indicesToRemove.add(index);
      }
    }
    
    // Also remove indices beyond the max index (if list shrunk)
    if (maxIndex != null) {
      for (final index in _myHandCardBounds.keys) {
        if (index > maxIndex && !indicesToRemove.contains(index)) {
          indicesToRemove.add(index);
        }
      }
    }
    
    for (final index in indicesToRemove) {
      _myHandCardBounds.remove(index);
      _myHandCardKeys.remove(index);
    }
    
    if (indicesToRemove.isNotEmpty && onCardBoundsChanged != null) {
      onCardBoundsChanged!();
    }
  }
  
  /// Update bounds for a specific opponent card by playerId and index
  /// [playerId] The player ID of the opponent
  /// [index] The index of the card in the opponent's hand
  /// [cardKey] The GlobalKey for the card widget
  /// [keyString] Optional key string for labeling
  /// Returns true if bounds were updated
  bool updateOpponentCardBounds(String playerId, int index, GlobalKey? cardKey, {String? keyString}) {
    final bounds = getCardBounds(cardKey);
    if (bounds == null) return false;
    
    // Initialize maps if needed
    if (!_opponentCardBounds.containsKey(playerId)) {
      _opponentCardBounds[playerId] = {};
    }
    if (!_opponentCardKeys.containsKey(playerId)) {
      _opponentCardKeys[playerId] = {};
    }
    
    final playerBounds = _opponentCardBounds[playerId]!;
    final oldBounds = playerBounds[index];
    bool changed = false;
    
    if (oldBounds == null) {
      changed = true;
    } else {
      final oldPos = oldBounds['position'] as Offset?;
      final newPos = bounds['position'] as Offset?;
      final oldSize = oldBounds['size'] as Size?;
      final newSize = bounds['size'] as Size?;
      
      if (oldPos != newPos || oldSize != newSize) {
        changed = true;
      }
    }
    
    if (changed) {
      playerBounds[index] = bounds;
      // Store the key string for labeling
      if (keyString != null) {
        _opponentCardKeys[playerId]![index] = keyString;
      } else if (cardKey != null) {
        final keyStr = cardKey.toString();
        final match = RegExp(r'\[GlobalKey[^\]]* ([^\]]+)\]').firstMatch(keyStr);
        _opponentCardKeys[playerId]![index] = match?.group(1) ?? keyStr;
      }
      // Notify that bounds changed
      if (onCardBoundsChanged != null) {
        onCardBoundsChanged!();
      }
    }
    
    return changed;
  }
  
  /// Get cached bounds for a specific opponent card by playerId and index
  /// Returns the last cached value, or null if not yet updated
  Map<String, dynamic>? getCachedOpponentCardBounds(String playerId, int index) {
    return _opponentCardBounds[playerId]?[index];
  }
  
  /// Get all cached opponent card bounds
  /// Returns a nested map of playerId -> index -> bounds
  Map<String, Map<int, Map<String, dynamic>>> getCachedOpponentCardBoundsAll() {
    final result = <String, Map<int, Map<String, dynamic>>>{};
    for (final entry in _opponentCardBounds.entries) {
      result[entry.key] = Map.from(entry.value);
    }
    return result;
  }
  
  /// Get all cached opponent card keys
  /// Returns a nested map of playerId -> index -> key string
  Map<String, Map<int, String>> getCachedOpponentCardKeysAll() {
    final result = <String, Map<int, String>>{};
    for (final entry in _opponentCardKeys.entries) {
      result[entry.key] = Map.from(entry.value);
    }
    return result;
  }
  
  /// Clear bounds for opponent cards that are no longer present
  /// [playerId] The player ID
  /// [currentIndices] List of indices that currently have cards for this player
  /// [maxIndex] Maximum valid index (cards.length - 1), to clear indices beyond the list
  void clearMissingOpponentCardBounds(String playerId, List<int> currentIndices, {int? maxIndex}) {
    if (!_opponentCardBounds.containsKey(playerId)) return;
    
    final currentIndicesSet = currentIndices.toSet();
    final playerBounds = _opponentCardBounds[playerId]!;
    final playerKeys = _opponentCardKeys[playerId];
    
    final indicesToRemove = <int>[];
    
    // Remove indices that are not in current list
    for (final index in playerBounds.keys) {
      if (!currentIndicesSet.contains(index)) {
        indicesToRemove.add(index);
      }
    }
    
    // Also remove indices beyond the max index (if list shrunk)
    if (maxIndex != null) {
      for (final index in playerBounds.keys) {
        if (index > maxIndex && !indicesToRemove.contains(index)) {
          indicesToRemove.add(index);
        }
      }
    }
    
    for (final index in indicesToRemove) {
      playerBounds.remove(index);
      playerKeys?.remove(index);
    }
    
    // Clean up empty player entries
    if (playerBounds.isEmpty) {
      _opponentCardBounds.remove(playerId);
    }
    if (playerKeys != null && playerKeys.isEmpty) {
      _opponentCardKeys.remove(playerId);
    }
    
    if (indicesToRemove.isNotEmpty && onCardBoundsChanged != null) {
      onCardBoundsChanged!();
    }
  }
  
  /// Get cached game board bounds (position and size)
  /// Returns the last cached value, or null if not yet updated
  Map<String, dynamic>? getCachedGameBoardBounds() => _gameBoardBounds;
}
