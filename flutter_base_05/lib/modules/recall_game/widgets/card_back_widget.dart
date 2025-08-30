import 'package:flutter/material.dart';
import '../../../../utils/consts/theme_consts.dart';

/// A generic widget for displaying the back of cards
/// 
/// This widget can be used for:
/// - Draw pile cards (face down)
/// - Face-down cards in player hands
/// - Any situation where card content should be hidden
/// - Placeholder cards
class CardBackWidget extends StatelessWidget {
  final CardSize size;
  final bool isSelectable;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? customSymbol;
  final Color? backgroundColor;
  final Color? borderColor;

  const CardBackWidget({
    Key? key,
    this.size = CardSize.medium,
    this.isSelectable = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    this.customSymbol,
    this.backgroundColor,
    this.borderColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardDimensions = _getCardDimensions();
    
    Widget cardContent = _buildCardBack(cardDimensions);

    // Wrap in gesture detector if interactive
    if (onTap != null || onLongPress != null) {
      cardContent = GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: cardContent,
      );
    }

    // Add selection indicator if selectable and selected
    if (isSelectable && isSelected) {
      cardContent = _buildSelectionWrapper(cardContent, cardDimensions);
    }

    return cardContent;
  }

  /// Build the card back
  Widget _buildCardBack(Size dimensions) {
    return Container(
      width: dimensions.width,
      height: dimensions.height,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primaryColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor ?? AppColors.accentColor,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          customSymbol ?? '?',
          style: TextStyle(
            fontSize: dimensions.width * 0.4,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }

  /// Build selection wrapper with highlight
  Widget _buildSelectionWrapper(Widget child, Size dimensions) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.accentColor2,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentColor2.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: child,
    );
  }

  /// Get card dimensions based on size
  Size _getCardDimensions() {
    switch (size) {
      case CardSize.small:
        return const Size(50, 70);
      case CardSize.medium:
        return const Size(70, 100);
      case CardSize.large:
        return const Size(80, 120);
      case CardSize.extraLarge:
        return const Size(100, 140);
    }
  }
}

/// Card size options for different contexts
enum CardSize {
  small,      // Small cards (e.g., opponent cards)
  medium,     // Standard size (e.g., discard pile)
  large,      // Large cards (e.g., player hand)
  extraLarge, // Extra large cards (e.g., special display)
}
