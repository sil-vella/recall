import 'package:flutter/material.dart';
import '../../../../utils/consts/theme_consts.dart';

/// Card Dimensions - Single Source of Truth (SSOT)
/// 
/// This class provides all card dimensions maintaining the standard poker card
/// aspect ratio (5:7, matching 2.5" x 3.5" physical cards).
/// 
/// All card dimensions must use this class to ensure consistency.
class CardDimensions {
  /// UNIFIED CARD SIZE - All cards use this size for consistency
  /// This ensures all cards (hand, opponent, discard, draw, collection) have the same dimensions
  static const CardSize UNIFIED_CARD_SIZE = CardSize.medium;
  
  /// Maximum card width - all cards are capped at this size
  static const double MAX_CARD_WIDTH = 55.0;
  
  /// Standard poker card aspect ratio (width:height)
  /// Matches physical poker cards: 2.5 inches x 3.5 inches
  static const double CARD_ASPECT_RATIO = 5.0 / 7.0;
  
  /// Base widths for each card size
  static const Map<CardSize, double> _baseWidths = {
    CardSize.small: 50.0,
    CardSize.medium: 55.0, // Capped at MAX_CARD_WIDTH
    CardSize.large: 55.0,  // Capped at max
    CardSize.extraLarge: 55.0, // Capped at max
  };
  
  /// Stack offset percentage (10% of card height)
  static const double STACK_OFFSET_PERCENTAGE = 0.10;
  
  /// Container height padding (additional height for container beyond card height)
  static const double CONTAINER_HEIGHT_PADDING = 20.0;
  
  /// Clamp card width to maximum allowed size
  /// 
  /// Ensures all card widths never exceed MAX_CARD_WIDTH
  static double clampCardWidth(double width) {
    return width.clamp(0.0, MAX_CARD_WIDTH);
  }
  
  /// Get card dimensions for a given size
  /// 
  /// Returns a Size object with width and height maintaining poker card aspect ratio
  /// Width is automatically clamped to MAX_CARD_WIDTH
  static Size getDimensions(CardSize size) {
    final width = clampCardWidth(_baseWidths[size] ?? 55.0);
    final height = width / CARD_ASPECT_RATIO;
    return Size(width, height);
  }
  
  /// Get card width for a given size
  /// Width is automatically clamped to MAX_CARD_WIDTH
  static double getWidth(CardSize size) {
    return clampCardWidth(_baseWidths[size] ?? 55.0);
  }
  
  /// Get card height for a given size (calculated from width using aspect ratio)
  static double getHeight(CardSize size) {
    final width = getWidth(size);
    return width / CARD_ASPECT_RATIO;
  }
  
  /// Get stack offset for collection cards (10% of card height)
  /// 
  /// Used when stacking collection rank cards on top of each other
  static double getStackOffset(CardSize size) {
    final height = getHeight(size);
    return height * STACK_OFFSET_PERCENTAGE;
  }
  
  /// Get container height for a given card size
  /// 
  /// Container height includes padding for proper display in ListView/GridView
  static double getContainerHeight(CardSize size) {
    final height = getHeight(size);
    return height + CONTAINER_HEIGHT_PADDING;
  }
  
  /// Get dimensions as a Map for easy access
  static Map<String, double> getDimensionsMap(CardSize size) {
    return {
      'width': getWidth(size),
      'height': getHeight(size),
      'stackOffset': getStackOffset(size),
      'containerHeight': getContainerHeight(size),
    };
  }
  
  /// Get unified card dimensions (convenience method for placement widgets)
  /// 
  /// Returns dimensions for UNIFIED_CARD_SIZE
  static Size getUnifiedDimensions() {
    return getDimensions(UNIFIED_CARD_SIZE);
  }
  
  /// Get unified card width (convenience method for placement widgets)
  static double getUnifiedWidth() {
    return getWidth(UNIFIED_CARD_SIZE);
  }
  
  /// Get unified card height (convenience method for placement widgets)
  static double getUnifiedHeight() {
    return getHeight(UNIFIED_CARD_SIZE);
  }
  
  /// Get unified stack offset (convenience method for placement widgets)
  static double getUnifiedStackOffset() {
    return getStackOffset(UNIFIED_CARD_SIZE);
  }
  
  /// Get unified container height (convenience method for placement widgets)
  static double getUnifiedContainerHeight() {
    return getContainerHeight(UNIFIED_CARD_SIZE);
  }
  
  /// Calculate border radius as a percentage of card size
  /// 
  /// Uses 5% of card width as the border radius, with minimum of 2.0 and maximum of 12.0
  /// This ensures cards have proportional corner rounding regardless of size
  /// 
  /// [dimensions] - The card dimensions (Size object with width and height)
  /// Returns the calculated border radius
  static double calculateBorderRadius(Size dimensions) {
    final safeWidth = dimensions.width > 0 ? dimensions.width : 1.0;
    // Use 5% of card width for border radius (standard for playing cards)
    final calculatedRadius = safeWidth * 0.05;
    // Clamp between 2.0 (minimum for very small cards) and 12.0 (maximum for very large cards)
    return calculatedRadius.clamp(2.0, 12.0);
  }
  
  /// Calculate border radius for a given card size
  /// 
  /// Convenience method that uses getDimensions() to calculate borderRadius
  static double getBorderRadius(CardSize size) {
    final dimensions = getDimensions(size);
    return calculateBorderRadius(dimensions);
  }
  
  /// Get unified border radius (convenience method for placement widgets)
  /// 
  /// Returns border radius for UNIFIED_CARD_SIZE
  static double getUnifiedBorderRadius() {
    return getBorderRadius(UNIFIED_CARD_SIZE);
  }
}

