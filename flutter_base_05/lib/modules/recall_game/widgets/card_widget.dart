import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../../../../utils/consts/theme_consts.dart';

/// A reusable card widget for the Recall game
/// 
/// This widget can be configured for different contexts:
/// - Player hand cards (larger, selectable)
/// - Opponent cards (smaller, view-only)
/// - Discard pile cards (medium, view-only)
/// - Draw pile cards (back-facing)
class CardWidget extends StatelessWidget {
  final CardModel card;
  final CardSize size;
  final bool showBack;
  final bool isSelectable;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showPoints;
  final bool showSpecialPower;

  const CardWidget({
    Key? key,
    required this.card,
    this.size = CardSize.medium,
    this.showBack = false,
    this.isSelectable = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    this.showPoints = false,
    this.showSpecialPower = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardDimensions = _getCardDimensions();
    
    // Show back if explicitly requested, face down, or if card only has ID (no full data)
    Widget cardContent = showBack || card.isFaceDown || !card.hasFullData
        ? _buildCardBack(cardDimensions)
        : _buildCardFront(cardDimensions);

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

  /// Build the front face of the card
  Widget _buildCardFront(Size dimensions) {
    return Container(
      width: dimensions.width,
      height: dimensions.height,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? AppColors.accentColor2 : Colors.grey.shade400,
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
      child: Padding(
        padding: EdgeInsets.all(dimensions.width * 0.05),
        child: Column(
          children: [
            // Top-left rank and suit
            Align(
              alignment: Alignment.topLeft,
              child: _buildCornerText(dimensions),
            ),
            
            // Center suit symbol
            Expanded(
              child: Center(
                child: _buildCenterSuit(dimensions),
              ),
            ),
            
            // Bottom-right rank and suit (rotated)
            Align(
              alignment: Alignment.bottomRight,
              child: Transform.rotate(
                angle: 3.14159, // 180 degrees
                child: _buildCornerText(dimensions),
              ),
            ),
            
            // Special power indicator
            if (showSpecialPower && card.hasSpecialPower) ...[
              const SizedBox(height: 4),
              _buildSpecialPowerIndicator(dimensions),
            ],
            
            // Points indicator
            if (showPoints) ...[
              const SizedBox(height: 2),
              _buildPointsIndicator(dimensions),
            ],
          ],
        ),
      ),
    );
  }



  /// Build corner text (rank and suit)
  Widget _buildCornerText(Size dimensions) {
    final fontSize = dimensions.width * 0.12;
    
    return Text(
      '${card.rankSymbol}\n${card.suitSymbol}',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: card.color,
        height: 1.0,
      ),
    );
  }

  /// Build center suit symbol
  Widget _buildCenterSuit(Size dimensions) {
    final fontSize = dimensions.width * 0.3;
    
    return Text(
      card.suitSymbol,
      style: TextStyle(
        fontSize: fontSize,
        color: card.color,
      ),
    );
  }

  /// Build special power indicator
  Widget _buildSpecialPowerIndicator(Size dimensions) {
    final iconSize = dimensions.width * 0.2;
    
    IconData iconData;
    Color iconColor;
    
    switch (card.specialPower) {
      case 'queen':
        iconData = Icons.visibility;
        iconColor = Colors.purple;
        break;
      case 'jack':
        iconData = Icons.swap_horiz;
        iconColor = Colors.blue;
        break;
      case 'added_power':
        iconData = Icons.star;
        iconColor = Colors.orange;
        break;
      default:
        iconData = Icons.flash_on;
        iconColor = Colors.yellow;
    }
    
    return Icon(
      iconData,
      size: iconSize,
      color: iconColor,
    );
  }

  /// Build points indicator
  Widget _buildPointsIndicator(Size dimensions) {
    final fontSize = dimensions.width * 0.1;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dimensions.width * 0.05,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: card.points == 0 ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${card.points}',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: AppColors.white,
        ),
      ),
    );
  }

  /// Build the card back
  Widget _buildCardBack(Size dimensions) {
    return Container(
      width: dimensions.width,
      height: dimensions.height,
      decoration: BoxDecoration(
        color: AppColors.primaryColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? AppColors.accentColor2 : AppColors.accentColor,
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
          '?',
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


