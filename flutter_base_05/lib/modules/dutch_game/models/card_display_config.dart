/// Card display mode - determines how corners are displayed
enum CardDisplayMode {
  /// Show both top-left and bottom-right corners (full card display)
  fullCorners,
  
  /// Show only top-left corner (compact display for smaller cards)
  singleCorner,
  
  /// Show rank and suit centered (no corners) - for opponent cards
  centeredOnly,
}

/// Card Display Configuration
/// 
/// Defines how a card should be displayed - appearance and behavior only.
/// Size is determined at the placement widget level, not in the config.
class CardDisplayConfig {
  /// Display mode (full corners or single corner)
  final CardDisplayMode displayMode;
  
  /// Show points indicator
  final bool showPoints;
  
  /// Show special power indicator
  final bool showSpecialPower;
  
  /// Card is selectable
  final bool isSelectable;
  
  /// Border radius for the card
  final double borderRadius;
  
  const CardDisplayConfig({
    this.displayMode = CardDisplayMode.fullCorners,
    this.showPoints = false,
    this.showSpecialPower = false,
    this.isSelectable = false,
    this.borderRadius = 8.0,
  });
  
  /// Factory constructor for player's own hand cards
  /// 
  /// Full corners display, selectable
  factory CardDisplayConfig.forMyHand() {
    return const CardDisplayConfig(
      displayMode: CardDisplayMode.fullCorners,
      isSelectable: true,
    );
  }
  
  /// Factory constructor for opponent cards
  /// 
  /// Centered rank and suit display (no corners), selectable
  factory CardDisplayConfig.forOpponent() {
    return const CardDisplayConfig(
      displayMode: CardDisplayMode.centeredOnly,
      isSelectable: true,
    );
  }
  
  /// Factory constructor for discard pile cards
  /// 
  /// Full corners display, not selectable
  factory CardDisplayConfig.forDiscardPile() {
    return const CardDisplayConfig(
      displayMode: CardDisplayMode.fullCorners,
      isSelectable: false,
    );
  }
  
  /// Factory constructor for draw pile cards
  /// 
  /// Full corners display, not selectable
  factory CardDisplayConfig.forDrawPile() {
    return const CardDisplayConfig(
      displayMode: CardDisplayMode.fullCorners,
      isSelectable: false,
    );
  }
  
  /// Create a copy with updated properties
  CardDisplayConfig copyWith({
    CardDisplayMode? displayMode,
    bool? showPoints,
    bool? showSpecialPower,
    bool? isSelectable,
    double? borderRadius,
  }) {
    return CardDisplayConfig(
      displayMode: displayMode ?? this.displayMode,
      showPoints: showPoints ?? this.showPoints,
      showSpecialPower: showSpecialPower ?? this.showSpecialPower,
      isSelectable: isSelectable ?? this.isSelectable,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }
}

