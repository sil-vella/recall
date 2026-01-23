import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = false; // Enabled for animation system debugging

/// Animation item structure for the queue
class AnimationItem {
  final String action; // 'drawn_card', 'play_card', 'same_rank', 'jack_swap', 'queen_peek', 'initial_peek'
  final Map<String, dynamic> actionData;
  final String playerId;
  final DateTime timestamp;

  AnimationItem({
    required this.action,
    required this.actionData,
    required this.playerId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'AnimationItem(action: $action, playerId: $playerId, actionData: $actionData)';
  }
}

/// Animation manager singleton for card animations
/// Manages local state, animation queue, and position tracking
class CardAnimationManager extends ChangeNotifier {
  static CardAnimationManager? _instance;
  static CardAnimationManager get instance {
    _instance ??= CardAnimationManager._internal();
    return _instance!;
  }

  // Logger
  final Logger _logger = Logger();

  // ========== Local State Structure ==========
  /// Local state matching widget slices structure
  /// Contains previous state values before computation + isOn flag
  Map<String, dynamic> _localState = {
    'isOn': false,
    'myHand': {
      'cards': [],
      'selectedIndex': -1,
      'canSelectCards': false,
      'playerStatus': 'unknown',
      'turn_events': [],
    },
    'centerBoard': {
      'drawPileCount': 0,
      'topDiscard': null,
      'topDraw': null,
      'canDrawFromDeck': false,
      'canTakeFromDiscard': false,
      'playerStatus': 'unknown',
      'matchPot': 0,
    },
    'opponentsPanel': {
      'opponents': [],
      'currentTurnIndex': -1,
      'turn_events': [],
      'currentPlayerStatus': 'unknown',
    },
  };

  // ========== Animation Queue System ==========
  /// Queue of animations to process
  final List<AnimationItem> _animationQueue = [];

  /// Whether animation queue is currently being processed
  bool _isProcessing = false;

  /// Current animation being processed
  AnimationItem? _currentAnimation;

  // ========== Position Tracking System ==========
  /// GlobalKey storage for cards (cardId -> GlobalKey)
  final Map<String, GlobalKey> _cardKeys = {};

  /// GlobalKey storage for sections (section -> GlobalKey)
  /// Sections: 'drawPile', 'discardPile', 'myHand', 'opponent_<playerId>'
  final Map<String, GlobalKey> _sectionKeys = {};

  /// Cached bounds for all registered keys (key -> Rect position)
  final Map<String, Rect> _cachedBounds = {};

  /// Fixed position cache for piles (captured once before animations start)
  Rect? _drawPilePosition;
  Rect? _discardPilePosition;

  /// Whether fixed positions have been captured
  bool _fixedPositionsCaptured = false;

  CardAnimationManager._internal() {
    if (LOGGING_SWITCH) {
      _logger.info('🎬 CardAnimationManager: Instance created (singleton initialization)');
    }
  }

  // ========== Public API ==========

  /// Whether animation system is currently active (replica widget should be visible)
  bool get isOn => _localState['isOn'] as bool? ?? false;

  /// Get local state (read-only copy)
  Map<String, dynamic> get localState => Map<String, dynamic>.from(_localState);

  /// Register a GlobalKey for a card
  /// [cardId] The card identifier
  /// [key] The GlobalKey for the card widget
  void registerCardKey(String cardId, GlobalKey key) {
    _cardKeys[cardId] = key;
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 CardAnimationManager: Registered card key for cardId: $cardId');
      }
    }
  }

  /// Register a GlobalKey for a section
  /// [section] Section identifier ('drawPile', 'discardPile', 'myHand', 'opponent_<playerId>')
  /// [key] The GlobalKey for the section widget
  void registerSectionKey(String section, GlobalKey key) {
    _sectionKeys[section] = key;
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 CardAnimationManager: Registered section key for section: $section');
      }
    }
  }

  /// Update cached bounds for all registered keys
  /// Should be called after widget build to capture current positions
  void updateCachedBounds() {
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 CardAnimationManager: Updating cached bounds for ${_cardKeys.length} cards and ${_sectionKeys.length} sections');
      }
    }

    // Update card bounds
    for (final entry in _cardKeys.entries) {
      final cardId = entry.key;
      final key = entry.value;
      final bounds = _getBoundsFromKey(key);
      if (bounds != null) {
        _cachedBounds[cardId] = bounds;
      }
    }

    // Update section bounds
    for (final entry in _sectionKeys.entries) {
      final section = entry.key;
      final key = entry.value;
      final bounds = _getBoundsFromKey(key);
      if (bounds != null) {
        _cachedBounds[section] = bounds;
      }
    }

    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 CardAnimationManager: Updated ${_cachedBounds.length} cached bounds');
      }
    }
  }

  /// Capture fixed positions (draw pile and discard pile) once before animations start
  /// These positions don't change during animations
  void captureFixedPositions() {
    if (_fixedPositionsCaptured) {
      if (LOGGING_SWITCH) {
        if (LOGGING_SWITCH) {
          _logger.debug('🎬 CardAnimationManager: Fixed positions already captured, skipping');
        }
      }
      return;
    }

    _drawPilePosition = getSectionPosition('drawPile');
    _discardPilePosition = getSectionPosition('discardPile');

    _fixedPositionsCaptured = true;

    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: Captured fixed positions - drawPile: ${_drawPilePosition != null ? "captured" : "null"}, discardPile: ${_discardPilePosition != null ? "captured" : "null"}');
      }
    }
  }

  /// Get card position by cardId
  /// Returns null if card not found or position unavailable
  Rect? getCardPosition(String cardId) {
    // First try cached bounds
    if (_cachedBounds.containsKey(cardId)) {
      return _cachedBounds[cardId];
    }

    // Fallback to GlobalKey lookup
    final key = _cardKeys[cardId];
    if (key != null) {
      final bounds = _getBoundsFromKey(key);
      if (bounds != null) {
        _cachedBounds[cardId] = bounds;
        return bounds;
      }
    }

    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.warning('🎬 CardAnimationManager: Card position not found for cardId: $cardId');
      }
    }
    return null;
  }

  /// Get card position by playerId and cardIndex (0-based)
  /// Captures fresh position RIGHT BEFORE animation for accuracy
  /// [playerId] The player identifier
  /// [cardIndex] The card index in the hand (0-based: cardIndex 2 = position 3 in hand)
  /// Returns null if card not found or position unavailable
  Rect? getHandCardPosition(String playerId, int cardIndex) {
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 CardAnimationManager: Getting hand card position for playerId: $playerId, cardIndex: $cardIndex');
      }
    }

    // Get player's hand from local state
    List<dynamic> hand = [];
    if (playerId == 'current_user' || playerId.isEmpty) {
      // Current user's hand
      final myHand = _localState['myHand'] as Map<String, dynamic>? ?? {};
      hand = myHand['cards'] as List<dynamic>? ?? [];
    } else {
      // Opponent's hand
      final opponentsPanel = _localState['opponentsPanel'] as Map<String, dynamic>? ?? {};
      final opponents = opponentsPanel['opponents'] as List<dynamic>? ?? [];
      final opponent = opponents.firstWhere(
        (p) => p['id']?.toString() == playerId,
        orElse: () => <String, dynamic>{},
      );
      hand = opponent['hand'] as List<dynamic>? ?? [];
    }

    // Validate cardIndex
    if (cardIndex < 0 || cardIndex >= hand.length) {
      if (LOGGING_SWITCH) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎬 CardAnimationManager: Invalid cardIndex $cardIndex for hand length ${hand.length}');
        }
      }
      return null;
    }

    // Get card at cardIndex
    final card = hand[cardIndex];
    if (card == null) {
      if (LOGGING_SWITCH) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎬 CardAnimationManager: Card at index $cardIndex is null');
        }
      }
      return null;
    }

    // Extract cardId
    String? cardId;
    if (card is Map<String, dynamic>) {
      cardId = card['cardId']?.toString();
    } else if (card is String) {
      cardId = card;
    }

    if (cardId == null || cardId.isEmpty) {
      if (LOGGING_SWITCH) {
        if (LOGGING_SWITCH) {
          _logger.warning('🎬 CardAnimationManager: Could not extract cardId from card at index $cardIndex');
        }
      }
      return null;
    }

    // Get position using cardId (captures fresh position)
    final position = getCardPosition(cardId);
    if (position != null && LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.debug('🎬 CardAnimationManager: Found card position for playerId: $playerId, cardIndex: $cardIndex, cardId: $cardId');
      }
    }

    return position;
  }

  /// Get card position by playerId and cardIndex (alternative method name)
  /// Same as getHandCardPosition
  Rect? getCardPositionByIndex(String playerId, int cardIndex) {
    return getHandCardPosition(playerId, cardIndex);
  }

  /// Get section position
  /// [section] Section identifier ('drawPile', 'discardPile', 'myHand', 'opponent_<playerId>')
  /// Returns null if section not found or position unavailable
  Rect? getSectionPosition(String section) {
    // For fixed positions, return cached value
    if (section == 'drawPile' && _drawPilePosition != null) {
      return _drawPilePosition;
    }
    if (section == 'discardPile' && _discardPilePosition != null) {
      return _discardPilePosition;
    }

    // First try cached bounds
    if (_cachedBounds.containsKey(section)) {
      return _cachedBounds[section];
    }

    // Fallback to GlobalKey lookup
    final key = _sectionKeys[section];
    if (key != null) {
      final bounds = _getBoundsFromKey(key);
      if (bounds != null) {
        _cachedBounds[section] = bounds;
        return bounds;
      }
    }

    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.warning('🎬 CardAnimationManager: Section position not found for section: $section');
      }
    }
    return null;
  }

  // ========== State Capture ==========

  /// Capture previous state slices before computation
  /// Called by StateUpdater before slice recomputation
  /// [previousSlices] Map containing 'myHand', 'centerBoard', 'opponentsPanel' slices
  void capturePreviousState(Map<String, dynamic> previousSlices) {
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: Capturing previous state slices');
      }
    }

    // Update local state with previous slices (deep copy)
    if (previousSlices.containsKey('myHand')) {
      final myHand = previousSlices['myHand'] as Map<String, dynamic>?;
      if (myHand != null) {
        _localState['myHand'] = Map<String, dynamic>.from(myHand);
      }
    }

    if (previousSlices.containsKey('centerBoard')) {
      final centerBoard = previousSlices['centerBoard'] as Map<String, dynamic>?;
      if (centerBoard != null) {
        _localState['centerBoard'] = Map<String, dynamic>.from(centerBoard);
      }
    }

    if (previousSlices.containsKey('opponentsPanel')) {
      final opponentsPanel = previousSlices['opponentsPanel'] as Map<String, dynamic>?;
      if (opponentsPanel != null) {
        _localState['opponentsPanel'] = Map<String, dynamic>.from(opponentsPanel);
      }
    }

    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: Previous state captured - myHand cards: ${(_localState['myHand'] as Map?)?['cards']?.length ?? 0}, centerBoard drawPileCount: ${(_localState['centerBoard'] as Map?)?['drawPileCount'] ?? 0}');
      }
    }
  }

  // ========== Action Detection and Queueing ==========

  /// Queue an animation for processing
  /// [action] Action type ('drawn_card', 'play_card', 'same_rank', 'jack_swap', 'queen_peek', 'initial_peek')
  /// [actionData] Action-specific data (cardId, cardIndex, etc.)
  /// [playerId] The player who performed the action
  void queueAnimation(String action, Map<String, dynamic> actionData, String playerId) {
    final animationItem = AnimationItem(
      action: action,
      actionData: actionData,
      playerId: playerId,
    );

    _animationQueue.add(animationItem);

    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: Queued animation - action: $action, playerId: $playerId, queue length: ${_animationQueue.length}');
      }
    }

    // Start processing if not already processing
    if (!_isProcessing) {
      _processAnimationQueue();
    }
  }

  // ========== Animation Processing ==========

  /// Process animation queue sequentially
  /// Processes one animation at a time until queue is empty
  Future<void> _processAnimationQueue() async {
    if (_isProcessing) {
      if (LOGGING_SWITCH) {
        if (LOGGING_SWITCH) {
          _logger.debug('🎬 CardAnimationManager: Already processing animations, skipping');
        }
      }
      return;
    }

    _isProcessing = true;

    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: Starting animation queue processing - queue length: ${_animationQueue.length}');
      }
    }

    // Capture fixed positions once before animations start
    if (!_fixedPositionsCaptured) {
      captureFixedPositions();
    }

    while (_animationQueue.isNotEmpty) {
      // Pop first item from queue
      _currentAnimation = _animationQueue.removeAt(0);

      if (LOGGING_SWITCH) {
        if (LOGGING_SWITCH) {
          _logger.info('🎬 CardAnimationManager: Processing animation: ${_currentAnimation}');
        }
      }

      // Set isOn to true (show replica widget)
      _localState['isOn'] = true;
      notifyListeners();

      try {
        // Call appropriate animation handler based on action type
        switch (_currentAnimation!.action) {
          case 'drawn_card':
            await _handleDrawCardAnimation(_currentAnimation!);
            break;
          case 'play_card':
            await _handlePlayCardAnimation(_currentAnimation!);
            break;
          case 'same_rank':
            await _handleSameRankAnimation(_currentAnimation!);
            break;
          case 'jack_swap':
            await _handleJackSwapAnimation(_currentAnimation!);
            break;
          case 'queen_peek':
            await _handleQueenPeekAnimation(_currentAnimation!);
            break;
          case 'initial_peek':
            await _handleInitialPeekAnimation(_currentAnimation!);
            break;
          default:
            if (LOGGING_SWITCH) {
              if (LOGGING_SWITCH) {
                _logger.warning('🎬 CardAnimationManager: Unknown action type: ${_currentAnimation!.action}');
              }
            }
        }
      } catch (e, stackTrace) {
        if (LOGGING_SWITCH) {
          _logger.error('🎬 CardAnimationManager: Error processing animation: $e', error: e, stackTrace: stackTrace);
        }
      }

      // Clear current animation
      _currentAnimation = null;
    }

    // Queue is empty, set isOn to false (hide replica widget)
    _localState['isOn'] = false;
    notifyListeners();

    _isProcessing = false;

    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: Animation queue processing complete');
      }
    }
  }

  // ========== Animation Handlers (Stubs for Phase 4) ==========

  /// Handle draw card animation
  /// Will be implemented in Phase 4
  Future<void> _handleDrawCardAnimation(AnimationItem item) async {
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: _handleDrawCardAnimation - action: ${item.action}, playerId: ${item.playerId}, actionData: ${item.actionData}');
      }
    }
    // TODO: Implement in Phase 4
    await Future.delayed(const Duration(milliseconds: 100)); // Placeholder
  }

  /// Handle play card animation
  /// Will be implemented in Phase 4
  Future<void> _handlePlayCardAnimation(AnimationItem item) async {
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: _handlePlayCardAnimation - action: ${item.action}, playerId: ${item.playerId}, actionData: ${item.actionData}');
      }
    }
    // TODO: Implement in Phase 4
    await Future.delayed(const Duration(milliseconds: 100)); // Placeholder
  }

  /// Handle same rank animation
  /// Will be implemented in Phase 4
  Future<void> _handleSameRankAnimation(AnimationItem item) async {
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: _handleSameRankAnimation - action: ${item.action}, playerId: ${item.playerId}, actionData: ${item.actionData}');
      }
    }
    // TODO: Implement in Phase 4
    await Future.delayed(const Duration(milliseconds: 100)); // Placeholder
  }

  /// Handle jack swap animation
  /// Will be implemented in Phase 4
  Future<void> _handleJackSwapAnimation(AnimationItem item) async {
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: _handleJackSwapAnimation - action: ${item.action}, playerId: ${item.playerId}, actionData: ${item.actionData}');
      }
    }
    // TODO: Implement in Phase 4
    await Future.delayed(const Duration(milliseconds: 100)); // Placeholder
  }

  /// Handle queen peek animation
  /// Will be implemented in Phase 4
  Future<void> _handleQueenPeekAnimation(AnimationItem item) async {
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: _handleQueenPeekAnimation - action: ${item.action}, playerId: ${item.playerId}, actionData: ${item.actionData}');
      }
    }
    // TODO: Implement in Phase 4
    await Future.delayed(const Duration(milliseconds: 100)); // Placeholder
  }

  /// Handle initial peek animation
  /// Will be implemented in Phase 4
  Future<void> _handleInitialPeekAnimation(AnimationItem item) async {
    if (LOGGING_SWITCH) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 CardAnimationManager: _handleInitialPeekAnimation - action: ${item.action}, playerId: ${item.playerId}, actionData: ${item.actionData}');
      }
    }
    // TODO: Implement in Phase 4
    await Future.delayed(const Duration(milliseconds: 100)); // Placeholder
  }

  // ========== Helper Methods ==========

  /// Get bounds from GlobalKey
  /// Returns null if key is not attached or render box not available
  Rect? _getBoundsFromKey(GlobalKey key) {
    try {
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final position = renderBox.localToGlobal(Offset.zero);
        return Rect.fromLTWH(position.dx, position.dy, renderBox.size.width, renderBox.size.height);
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        if (LOGGING_SWITCH) {
          _logger.debug('🎬 CardAnimationManager: Error getting bounds from key: $e');
        }
      }
    }
    return null;
  }
}
