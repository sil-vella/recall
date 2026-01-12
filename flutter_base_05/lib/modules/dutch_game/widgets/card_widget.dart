import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/card_display_config.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../utils/consts/config.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';

/// A reusable card widget for the Dutch game
/// 
/// Size is determined at the placement widget level and passed as dimensions.
/// Config only controls appearance (displayMode, showPoints, etc.)
class CardWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = false; // Enable logging for errors only
  static final Logger _logger = Logger();
  final CardModel card;
  final Size dimensions; // Required - size determined at placement widget level
  final CardDisplayConfig config;
  final bool showBack;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  CardWidget({
    Key? key,
    required this.card,
    required this.dimensions, // Required - placement widget must provide size
    CardDisplayConfig? config,
    this.showBack = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  }) : config = config ?? CardDisplayConfig.forDiscardPile(),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    // Show back if explicitly requested, face down, or if card only has ID (no full data)
    // For drawn cards, if showBack is explicitly false but card has no full data, still show back to avoid blank card
    final shouldShowBack = showBack || 
                           card.isFaceDown || 
                           !card.hasFullData ||
                           (card.rank == '?' || card.suit == '?');
    
    Widget cardContent = shouldShowBack
        ? _buildCardBack(dimensions)
        : _buildCardFront(dimensions);

    // Wrap in gesture detector if interactive
    if (onTap != null || onLongPress != null) {
      cardContent = GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: cardContent,
      );
    }

    // Add selection indicator if selectable and selected
    if (config.isSelectable && isSelected) {
      cardContent = _buildSelectionWrapper(cardContent, dimensions);
    }

    // Ensure exact dimensions are maintained even when wrapped in external GestureDetectors
    // cardContent is already wrapped in SizedBox with exact dimensions from _buildCardFront/_buildCardBack
    // But wrap again to ensure dimensions are maintained when CardWidget is wrapped externally
    return SizedBox(
      width: dimensions.width,
      height: dimensions.height,
      child: cardContent,
    );
  }

  /// Build the front face of the card
  Widget _buildCardFront(Size dimensions) {
    // Check if this is a special card that should use a background image
    final isSpecialCard = card.isFaceCard || card.rank.toLowerCase() == 'joker';
    final specialCardImagePath = _getSpecialCardImagePath();
    
    // Calculate padding based on card size (minimum 2px, maximum 8% of width)
    final padding = (dimensions.width * 0.05).clamp(2.0, dimensions.width * 0.08);
    
    return Container(
      width: dimensions.width,
      height: dimensions.height,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background image for special cards (queen, king, jack, joker)
          if (isSpecialCard && specialCardImagePath != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  image: AssetImage(specialCardImagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // If image fails to load, continue with normal card layout
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          
          // Card content (rank, suit, etc.) - properly constrained
          Padding(
            padding: EdgeInsets.all(padding),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate available space after padding
                final availableWidth = constraints.maxWidth;
                final availableHeight = constraints.maxHeight;
                
                return Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Centered display mode: rank and suit in center, no corners
            if (config.displayMode == CardDisplayMode.centeredOnly) ...[
              Expanded(
                child: Center(
                          child: _buildCenteredRankAndSuit(Size(availableWidth, availableHeight)),
                ),
              ),
            ] else ...[
              // Top-left rank and suit (always shown for non-centered modes)
              Align(
                alignment: Alignment.topLeft,
                        child: _buildCornerText(Size(availableWidth, availableHeight)),
              ),
              
                      // Center content - suit symbols for numbered cards
                      // For special cards with background images, center is empty (image shows)
              Expanded(
                child: Center(
                          child: (isSpecialCard && specialCardImagePath != null)
                              ? const SizedBox.shrink() // Background image shows, no center content needed
                              : _buildCenterContent(Size(availableWidth, availableHeight)),
                ),
              ),
              
              // Bottom-right rank and suit (rotated) - only shown in fullCorners mode
              if (config.displayMode == CardDisplayMode.fullCorners) ...[
                Align(
                  alignment: Alignment.bottomRight,
                  child: Transform.rotate(
                    angle: 3.14159, // 180 degrees
                            child: _buildCornerText(Size(availableWidth, availableHeight)),
                  ),
                ),
              ],
            ],
            
            // Special power indicator
            if (config.showSpecialPower && card.hasSpecialPower) ...[
              const SizedBox(height: 4),
                      _buildSpecialPowerIndicator(Size(availableWidth, availableHeight)),
            ],
            
            // Points indicator
            if (config.showPoints) ...[
              const SizedBox(height: 2),
                      _buildPointsIndicator(Size(availableWidth, availableHeight)),
            ],
          ],
                );
              },
            ),
        ),
        ],
      ),
    );
  }

  /// Get the path to special card image if available
  String? _getSpecialCardImagePath() {
    final rank = card.rank.toLowerCase();
    if (rank == 'queen') return 'assets/images/queen.png';
    if (rank == 'king') return 'assets/images/king.png';
    if (rank == 'jack') return 'assets/images/jack.png';
    if (rank == 'joker') return 'assets/images/joker.png';
    return null;
  }
  
  /// Build center content for numbered cards (shows appropriate number of suit symbols)
  Widget _buildCenterContent(Size dimensions) {
    // For numbered cards, show the number of suit symbols
    if (card.isNumberedCard) {
      final rankNum = int.tryParse(card.rank);
      if (rankNum != null && rankNum >= 2 && rankNum <= 10) {
        return _buildNumberedCardCenter(dimensions, rankNum);
      }
    }
    
    // For Ace, show single large suit symbol
    if (card.isAce) {
      return _buildCenterSuit(dimensions);
    }
    
    // Default: show single suit symbol
    return _buildCenterSuit(dimensions);
  }
  
  /// Build center for numbered cards - shows appropriate number of suit symbols
  Widget _buildNumberedCardCenter(Size dimensions, int rankNum) {
    final suitSymbol = card.suitSymbol;
    final suitColor = card.color;
    
    // Calculate font size based on available space, ensuring it fits
    // Use the smaller dimension to ensure it fits both width and height
    final minDimension = dimensions.width < dimensions.height ? dimensions.width : dimensions.height;
    // Calculate max font size: ensure symbols fit with spacing
    // For higher ranks, we need smaller symbols to fit more
    final baseFontSize = minDimension * 0.2;
    final fontSize = (rankNum <= 4) 
        ? baseFontSize.clamp(8.0, minDimension * 0.25)
        : (baseFontSize * 0.8).clamp(6.0, minDimension * 0.2);
    
    // Calculate spacing based on available space
    final verticalSpacing = (dimensions.height * 0.08).clamp(2.0, dimensions.height * 0.15);
    final horizontalSpacing = (dimensions.width * 0.1).clamp(2.0, dimensions.width * 0.2);
    
    // Use FittedBox to ensure content scales down if needed
    Widget buildSymbol() {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          suitSymbol,
          style: TextStyle(
            fontSize: fontSize,
            color: suitColor,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    
    // Arrange suit symbols based on number
    // For 2-6: show in a pattern
    // For 7-10: show in a pattern with more symbols
    if (rankNum == 2) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            buildSymbol(),
            SizedBox(height: verticalSpacing * 2),
            buildSymbol(),
          ],
        ),
      );
    } else if (rankNum == 3) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            buildSymbol(),
            SizedBox(height: verticalSpacing),
            buildSymbol(),
            SizedBox(height: verticalSpacing),
            buildSymbol(),
          ],
        ),
      );
    } else if (rankNum == 4) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSymbol(),
                SizedBox(width: horizontalSpacing),
                buildSymbol(),
              ],
            ),
            SizedBox(height: verticalSpacing * 1.5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSymbol(),
                SizedBox(width: horizontalSpacing),
                buildSymbol(),
              ],
            ),
          ],
        ),
      );
    } else if (rankNum == 5) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSymbol(),
                SizedBox(width: horizontalSpacing),
                buildSymbol(),
              ],
            ),
            SizedBox(height: verticalSpacing),
            buildSymbol(),
            SizedBox(height: verticalSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSymbol(),
                SizedBox(width: horizontalSpacing),
                buildSymbol(),
              ],
            ),
          ],
        ),
      );
    } else if (rankNum == 6) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSymbol(),
                SizedBox(width: horizontalSpacing),
                buildSymbol(),
              ],
            ),
            SizedBox(height: verticalSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSymbol(),
                SizedBox(width: horizontalSpacing),
                buildSymbol(),
              ],
            ),
            SizedBox(height: verticalSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSymbol(),
                SizedBox(width: horizontalSpacing),
                buildSymbol(),
              ],
            ),
          ],
        ),
      );
    } else {
      // For 7-10, show a grid pattern
      final symbolsPerRow = rankNum <= 8 ? 2 : 3;
      final totalRows = (rankNum / symbolsPerRow).ceil();
      
      final rows = <Widget>[];
      int symbolCount = 0;
      for (int row = 0; row < totalRows; row++) {
        final rowSymbols = <Widget>[];
        for (int col = 0; col < symbolsPerRow && symbolCount < rankNum; col++) {
          rowSymbols.add(buildSymbol());
          if (col < symbolsPerRow - 1 && symbolCount < rankNum - 1) {
            rowSymbols.add(SizedBox(width: horizontalSpacing));
          }
          symbolCount++;
        }
        rows.add(
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: rowSymbols,
          ),
        );
        if (row < totalRows - 1) {
          rows.add(SizedBox(height: verticalSpacing));
        }
      }
      
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        ),
      );
    }
  }



  /// Build corner text (rank and suit)
  Widget _buildCornerText(Size dimensions) {
    // Calculate font size based on available space
    final minDimension = dimensions.width < dimensions.height ? dimensions.width : dimensions.height;
    // Ensure minDimension is valid (at least 1.0) to prevent clamp errors
    final safeMinDimension = minDimension > 0 ? minDimension : 1.0;
    final calculatedSize = safeMinDimension * 0.12;
    final maxSize = safeMinDimension * 0.15;
    // Ensure clamp values are in correct order (min <= max)
    final fontSize = calculatedSize.clamp(8.0, maxSize > 8.0 ? maxSize : 8.0);
    
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: Text(
      '${card.rankSymbol}\n${card.suitSymbol}',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: card.color,
        height: 1.0,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }

  /// Build center suit symbol (for Ace)
  Widget _buildCenterSuit(Size dimensions) {
    // Calculate font size based on available space
    final minDimension = dimensions.width < dimensions.height ? dimensions.width : dimensions.height;
    final fontSize = (minDimension * 0.3).clamp(12.0, minDimension * 0.4);
    
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
      card.suitSymbol,
      style: TextStyle(
        fontSize: fontSize,
        color: card.color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Build centered rank and suit (for opponent cards)
  /// Shows rank and suit in the center, text size is 40% of card height
  Widget _buildCenteredRankAndSuit(Size dimensions) {
    // Calculate font size based on available space
    final minDimension = dimensions.width < dimensions.height ? dimensions.width : dimensions.height;
    final fontSize = (minDimension * 0.4).clamp(10.0, minDimension * 0.5);
    
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Rank
        Text(
          card.rankSymbol,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: card.color,
            height: 1.0,
          ),
            textAlign: TextAlign.center,
        ),
        // Suit
        Text(
          card.suitSymbol,
          style: TextStyle(
            fontSize: fontSize,
            color: card.color,
            height: 1.0,
          ),
            textAlign: TextAlign.center,
        ),
      ],
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
        color: card.points == 0 ? AppColors.successColor : AppColors.errorColor,
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
  /// Structure must EXACTLY match front face: Container -> Padding -> Column -> same children structure
  Widget _buildCardBack(Size dimensions) {
    return Container(
      width: dimensions.width,
      height: dimensions.height,
      decoration: BoxDecoration(
        color: AppColors.primaryColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(dimensions.width * 0.05),
        child: Center(
          child: Builder(
            builder: (context) {
              // Get currentGameId to detect practice mode (read once, no listener)
              final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
              final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
              
              // Detect practice mode: practice games have IDs starting with "practice_room_"
              final isPracticeMode = currentGameId.startsWith('practice_room_');
              
              // In practice mode, load from assets; otherwise load from server
              if (isPracticeMode) {
                // Load from assets for practice mode
                return Image(
                  image: AssetImage('assets/images/card_back.png'),
                  width: dimensions.width * 0.9, // Leave some padding
                  height: dimensions.height * 0.9,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    _logger.error('🖼️ CardWidget: Asset load error for card_back.png', isOn: LOGGING_SWITCH);
                    return Icon(
                      Icons.broken_image,
                      size: dimensions.width * 0.4,
                      color: AppColors.white.withOpacity(0.5),
                    );
                  },
                );
              } else {
                // Load from server for multiplayer games
                // Build image URL with cache-busting query parameters
                // Version 2: Increment this when uploading a new image to force cache refresh
                const int imageVersion = 2;
                final imageUrl = currentGameId.isNotEmpty
                    ? '${Config.apiUrl}/sponsors/images/card_back.png?gameId=$currentGameId&v=$imageVersion'
                    : '${Config.apiUrl}/sponsors/images/card_back.png?v=$imageVersion';
                
                // Use Image.network which uses browser's native image loading on web
                // This avoids CORS issues that affect the http package
                // Fallback to asset image if network fails
                return Image.network(
                  imageUrl,
                  width: dimensions.width * 0.9, // Leave some padding
                  height: dimensions.height * 0.9,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
                    // Show placeholder while loading
                    return Icon(
                      Icons.image,
                      size: dimensions.width * 0.4,
                      color: AppColors.white.withOpacity(0.5),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    _logger.error('🖼️ CardWidget: Network image load error, falling back to asset', isOn: LOGGING_SWITCH);
                    // Fallback to asset image if network fails
                    return Image(
                      image: AssetImage('assets/images/card_back.png'),
                      width: dimensions.width * 0.9,
                      height: dimensions.height * 0.9,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        _logger.error('🖼️ CardWidget: Asset fallback also failed', isOn: LOGGING_SWITCH);
                        return Icon(
                          Icons.broken_image,
                          size: dimensions.width * 0.4,
                          color: AppColors.white.withOpacity(0.5),
                        );
                      },
                    );
                  },
                );
              }
            },
          ),
        ),
      ),
    );
  }

  /// Build selection wrapper with highlight
  /// Ensures exact dimensions are maintained
  Widget _buildSelectionWrapper(Widget child, Size dimensions) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
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

}


