import 'package:flutter/material.dart';
import '../../../../../tools/logging/logger.dart';

const bool LOGGING_SWITCH = false; // Enabled for animation system debugging and action data tracking

/// AnimationTypes enum for different animation types
enum AnimationType {
  fadeIn,
  fadeOut,
  slideIn,
  slideOut,
  scaleIn,
  scaleOut,
  move,
  moveCard,
  moveWithEmptySlot,
  swap,
  peek,
  flashCard,
  compoundSameRankReject, // Hand to discard, then discard to hand (wrong same-rank attempt, continuous)
  none,
}

/// Animations provides utility methods for mapping action names to animation types
/// and managing animation logic for the unified game board widget.
class Animations {
  static final Logger _logger = Logger();
  
  /// Cache of processed action names to prevent duplicate animations
  /// Action names are unique (include 6-digit ID), so we can track which ones have been animated
  static final Set<String> _processedActions = {};
  /// Map action names to animation types
  /// Action names come in format: 'action_name_${actionId}' (e.g., 'drawn_card_123456')
  static AnimationType getAnimationTypeForAction(String actionName) {
    // Extract base action name (remove the ID suffix)
    final baseActionName = extractBaseActionName(actionName);
    
    switch (baseActionName) {
      case 'drawn_card':
        return AnimationType.moveCard; // Card moves from draw pile to hand
      case 'collect_from_discard':
        return AnimationType.moveCard; // Card moves from discard pile to hand (same as draw but source = discard)
      case 'play_card':
        return AnimationType.moveWithEmptySlot; // Card moves from hand to discard pile, with empty slot at start
      case 'same_rank':
        return AnimationType.moveWithEmptySlot; // Card moves from hand to discard pile, with empty slot at start
      case 'draw_reposition':
        return AnimationType.moveWithEmptySlot; // Drawn card moves from original position to reposition destination, with empty slot at start
      case 'jack_swap':
        return AnimationType.moveWithEmptySlot; // Expanded at queue: jack_swap_1 (empty at source) + jack_swap_2 (empty at dest)
      case 'jack_swap_1':
        return AnimationType.moveWithEmptySlot; // First of two: card1 moves to slot2, empty slot at source
      case 'jack_swap_2':
        return AnimationType.moveWithEmptySlot; // Second of two: card2 moves to slot1, empty slot at destination
      case 'queen_peek':
        return AnimationType.flashCard; // Flash border on peeked card
      case 'initial_peek':
        return AnimationType.flashCard; // Flash border on peeked cards
      case 'jack_swap_flash':
        return AnimationType.flashCard; // Flash overlay on both swapped card indexes
      case 'same_rank_reject':
        return AnimationType.compoundSameRankReject; // Hand to discard, then back to hand (continuous)
      default:
        return AnimationType.none;
    }
  }
  
  /// Extract base action name from action string (removes ID suffix)
  /// Example: 'drawn_card_123456' -> 'drawn_card'
  static String extractBaseActionName(String actionName) {
    // Action names are in format: 'action_name_${6digitId}'
    // Find the last underscore and remove everything after it
    final lastUnderscoreIndex = actionName.lastIndexOf('_');
    if (lastUnderscoreIndex == -1) {
      return actionName;
    }
    
    // Check if the part after underscore is a 6-digit number (action ID)
    final suffix = actionName.substring(lastUnderscoreIndex + 1);
    if (suffix.length == 6 && int.tryParse(suffix) != null) {
      // It's an action ID, return the base name
      return actionName.substring(0, lastUnderscoreIndex);
    }
    
    // Not an action ID format, return as-is
    return actionName;
  }
  
  /// Get animation duration for a given animation type
  /// Returns default duration in milliseconds
  static Duration getAnimationDuration(AnimationType animationType) {
    switch (animationType) {
      case AnimationType.fadeIn:
      case AnimationType.fadeOut:
        return const Duration(milliseconds: 300); // TODO: Define actual duration
      case AnimationType.slideIn:
      case AnimationType.slideOut:
        return const Duration(milliseconds: 400); // TODO: Define actual duration
      case AnimationType.scaleIn:
      case AnimationType.scaleOut:
        return const Duration(milliseconds: 250); // TODO: Define actual duration
      case AnimationType.move:
        return const Duration(milliseconds: 500); // TODO: Define actual duration
      case AnimationType.moveCard:
        return const Duration(milliseconds: 1000);
      case AnimationType.moveWithEmptySlot:
        return const Duration(milliseconds: 1000);
      case AnimationType.swap:
        return const Duration(milliseconds: 600); // TODO: Define actual duration
      case AnimationType.peek:
        return const Duration(milliseconds: 400); // TODO: Define actual duration
      case AnimationType.flashCard:
        return const Duration(milliseconds: 1000); // 2 flashes (initial_peek, queen_peek, jack_swap_flash)
      case AnimationType.compoundSameRankReject:
        return const Duration(milliseconds: 2000); // 1s out + 1s back (continuous, actual timing in widget)
      case AnimationType.none:
        return Duration.zero;
    }
  }
  
  /// Get animation curve for a given animation type
  static Curve getAnimationCurve(AnimationType animationType) {
    switch (animationType) {
      case AnimationType.fadeIn:
      case AnimationType.fadeOut:
        return Curves.easeIn; // TODO: Define actual curve
      case AnimationType.slideIn:
      case AnimationType.slideOut:
        return Curves.easeInOut; // TODO: Define actual curve
      case AnimationType.scaleIn:
      case AnimationType.scaleOut:
        return Curves.easeOut; // TODO: Define actual curve
      case AnimationType.move:
        return Curves.easeInOutCubic; // TODO: Define actual curve
      case AnimationType.moveCard:
        return Curves.easeInOutCubic; // TODO: Define actual curve
      case AnimationType.moveWithEmptySlot:
        return Curves.easeInOutCubic; // Same as moveCard
      case AnimationType.swap:
        return Curves.easeInOut; // TODO: Define actual curve
      case AnimationType.peek:
        return Curves.easeOut; // TODO: Define actual curve
      case AnimationType.flashCard:
        return Curves.easeInOut; // Smooth flash transitions
      case AnimationType.compoundSameRankReject:
        return Curves.easeInOutCubic; // Same as moveCard/moveWithEmptySlot
      case AnimationType.none:
        return Curves.linear;
    }
  }
  
  /// Get animation parameters for a given action
  /// Returns a map with animation configuration
  static Map<String, dynamic> getAnimationParameters(String actionName) {
    final animationType = getAnimationTypeForAction(actionName);
    
    return {
      'type': animationType,
      'duration': getAnimationDuration(animationType),
      'curve': getAnimationCurve(animationType),
      // TODO: Add more parameters as needed (e.g., delay, repeat, etc.)
    };
  }
  
  /// Check if an action requires animation
  static bool requiresAnimation(String actionName) {
    final animationType = getAnimationTypeForAction(actionName);
    return animationType != AnimationType.none;
  }
  
  /// Get source and destination information for move animations
  /// Returns null if not applicable for the action type
  static Map<String, dynamic>? getMoveAnimationSourceDest(
    String actionName,
    Map<String, dynamic> actionData,
  ) {
    final animationType = getAnimationTypeForAction(actionName);
    
    if (animationType != AnimationType.move && animationType != AnimationType.swap) {
      return null;
    }
    
    // TODO: Extract source and destination from actionData
    // actionData contains card1Data (and card2Data for swap) with cardIndex and playerId
    return {
      'sourceIndex': actionData['card1Data']?['cardIndex'],
      'sourcePlayerId': actionData['card1Data']?['playerId'],
      'destIndex': null, // TODO: Determine destination from game state
      'destPlayerId': null, // TODO: Determine destination from game state
    };
  }
  
  /// Validate action data structure
  /// Returns true if action data is valid for animation
  static bool validateActionData(String actionName, Map<String, dynamic>? actionData) {
    if (actionData == null) return false;
    
    // All actions should have at least card1Data
    if (!actionData.containsKey('card1Data')) return false;
    
    final card1Data = actionData['card1Data'] as Map<String, dynamic>?;
    if (card1Data == null) return false;
    
    // card1Data should have cardIndex and playerId
    if (!card1Data.containsKey('cardIndex') || !card1Data.containsKey('playerId')) {
      return false;
    }
    
    // For jack_swap and initial_peek, also check card2Data (they require 2 cards)
    // queen_peek only has card1Data (1 card), so no additional validation needed
    if (actionName.startsWith('jack_swap') || actionName.startsWith('initial_peek')) {
      if (!actionData.containsKey('card2Data')) return false;
      
      final card2Data = actionData['card2Data'] as Map<String, dynamic>?;
      if (card2Data == null) return false;
      
      if (!card2Data.containsKey('cardIndex') || !card2Data.containsKey('playerId')) {
        return false;
      }
    }
    // Note: queen_peek only requires card1Data, which is already validated above
    
    return true;
  }
  
  /// Animate action - executes animation based on action name and data
  /// [actionName] The action name (e.g., 'drawn_card_123456')
  /// [actionData] The action data containing card information
  /// [playScreenFunctions] Instance of PlayScreenFunctions to get bounds
  /// Returns a Future that completes when animation finishes
  static Future<void> animateAction(
    String actionName,
    Map<String, dynamic>? actionData,
    dynamic playScreenFunctions, // PlayScreenFunctions instance
  ) async {
    // Check if this action has already been processed
    if (_processedActions.contains(actionName)) {
      if (LOGGING_SWITCH) {
        _logger.info('🎬 ANIMATION: Skipping duplicate action - $actionName (already processed)');
      }
      return;
    }
    
    // Validate action data
    if (actionData == null || !validateActionData(actionName, actionData)) {
      return;
    }
    
    // Cache the action name before processing to prevent duplicates
    _processedActions.add(actionName);
    
    if (LOGGING_SWITCH) {
      _logger.info('🎬 ANIMATION: Cached action name - $actionName');
    }
    
    final animationType = getAnimationTypeForAction(actionName);
    if (animationType == AnimationType.none) {
      // Remove from cache if no animation needed
      _processedActions.remove(actionName);
      return;
    }
    
    final duration = getAnimationDuration(animationType);
    
    // Handle moveCard animation (for drawn_card)
    if (animationType == AnimationType.moveCard) {
      await _animateMoveCard(actionName, actionData, playScreenFunctions, duration);
    } else {
      // TODO: Handle other animation types
      // For now, just wait for the duration
      await Future.delayed(duration);
    }
  }
  
  /// Clear processed actions cache (useful for testing or reset)
  static void clearProcessedActions() {
    _processedActions.clear();
    if (LOGGING_SWITCH) {
      _logger.info('🎬 ANIMATION: Cleared processed actions cache');
    }
  }
  
  /// Get count of processed actions (for debugging)
  static int getProcessedActionsCount() {
    return _processedActions.length;
  }
  
  /// Check if an action has already been processed
  static bool isActionProcessed(String actionName) {
    return _processedActions.contains(actionName);
  }

  /// Check if any action with the given base name has already been processed.
  /// Used for actions that should run only once per round (e.g. initial_peek:
  /// one flash for all players, subsequent initial_peek_<id> from other players
  /// must be skipped).
  static bool hasBaseActionProcessed(String baseActionName) {
    return _processedActions.any((name) => extractBaseActionName(name) == baseActionName);
  }
  
  /// Mark an action as processed (called when animation starts)
  static void markActionAsProcessed(String actionName) {
    _processedActions.add(actionName);
    if (LOGGING_SWITCH) {
      _logger.info('🎬 ANIMATION: Marked action as processed - $actionName');
    }
  }
  
  /// Animate moveCard (card moving from draw pile to hand)
  static Future<void> _animateMoveCard(
    String actionName,
    Map<String, dynamic> actionData,
    dynamic playScreenFunctions,
    Duration duration,
  ) async {
    // Get card1Data from actionData
    final card1Data = actionData['card1Data'] as Map<String, dynamic>?;
    if (card1Data == null) return;
    
    final playerId = card1Data['playerId']?.toString();
    final cardIndex = card1Data['cardIndex'] as int?;
    
    if (playerId == null || cardIndex == null) return;
    
    // Get draw pile bounds from PlayScreenFunctions
    final drawPileBounds = playScreenFunctions.getCachedDrawPileBounds();
    
    // Get card bounds by playerId and index
    Map<String, dynamic>? cardBounds;
    
    // Check if it's my hand (need to compare with current user ID)
    // For now, check both my hand and opponent hands
    final myHandCardBounds = playScreenFunctions.getCachedMyHandCardBoundsAll();
    cardBounds = myHandCardBounds[cardIndex];
    
    // If not in my hand, check opponent hands
    if (cardBounds == null) {
      final opponentCardBounds = playScreenFunctions.getCachedOpponentCardBoundsAll();
      final playerCardBounds = opponentCardBounds[playerId];
      if (playerCardBounds != null) {
        cardBounds = playerCardBounds[cardIndex];
      }
    }
    
    // Log the animation data
    if (LOGGING_SWITCH) {
      _logger.info('🎬 ANIMATION: moveCard');
      _logger.info('  Action: $actionName');
      _logger.info('  PlayerId: $playerId');
      _logger.info('  CardIndex: $cardIndex');
      _logger.info('  DrawPileBounds: $drawPileBounds');
      _logger.info('  CardBounds: $cardBounds');
      _logger.info('  Duration: ${duration.inMilliseconds}ms');
    }
    
    // TODO: Execute actual animation
    // For now, just wait for the duration
    await Future.delayed(duration);
  }
}
