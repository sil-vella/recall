import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/card_display_config.dart';
import '../utils/card_dimensions.dart';
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
    final safeWidth = dimensions.width > 0 ? dimensions.width : 1.0;
    final maxPadding = safeWidth * 0.08;
    final padding = (safeWidth * 0.05).clamp(2.0, maxPadding > 2.0 ? maxPadding : 2.0);
    
    // Calculate border radius from card dimensions (SSOT approach)
    // Use dynamic calculation from CardDimensions if using default borderRadius (8.0)
    // Otherwise use the explicitly set borderRadius from config
    final borderRadius = (config.borderRadius == 8.0) 
        ? CardDimensions.calculateBorderRadius(dimensions)
        : config.borderRadius;
    
    return Container(
      width: dimensions.width,
      height: dimensions.height,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.28),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background image for special cards (queen, king, jack, joker)
          // 3/4 card height, aspect ratio preserved, aligned left (overflow clipped on right)
          if (isSpecialCard && specialCardImagePath != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(config.borderRadius),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image(
                    image: AssetImage(specialCardImagePath),
                    fit: BoxFit.fitHeight,
                    height: dimensions.height * 3 / 4,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          
          // Card content: two columns, 1/3 and 2/3 width, full available height. Left: rank/suit 1/4 col height. Right: rank/suit/circle 3/4 col height.
          Padding(
            padding: EdgeInsets.all(padding),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final availableHeight = constraints.maxHeight;
                var rowHeight = availableHeight;
                if (config.showSpecialPower && card.hasSpecialPower) rowHeight -= 4 + 24;
                if (config.showPoints) rowHeight -= 2 + 24;
                rowHeight = rowHeight.clamp(1.0, availableHeight);
                final leftColWidth = availableWidth * (1 / 3);
                final rightColWidth = availableWidth * (2 / 3);

                return Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 1,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: _buildTopLeftCornerText(
                                Size(leftColWidth, rowHeight),
                                heightFraction: 1 / 4,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: _buildBottomRightCornerText(
                                Size(rightColWidth, rowHeight),
                                heightFraction: 3 / 4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (config.showSpecialPower && card.hasSpecialPower) ...[
                      const SizedBox(height: 4),
                      _buildSpecialPowerIndicator(Size(availableWidth, availableHeight)),
                    ],
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

  /// Get the path to special card image if available.
  /// Images for king, queen, jack, and joker live in assets/images/backgrounds/
  /// (see DECK_CREATION_RESHUFFLING_AND_CONFIG.md and card_display in deck config).
  String? _getSpecialCardImagePath() {
    final rank = card.rank.toLowerCase();
    if (rank == 'queen') return 'assets/images/backgrounds/queen.png';
    if (rank == 'king') return 'assets/images/backgrounds/king.png';
    if (rank == 'jack') return 'assets/images/backgrounds/jack.png';
    if (rank == 'joker') return 'assets/images/backgrounds/joker.png';
    return null;
  }
  /// Build rank/suit text (single color, no stroke). Used for top-left and bottom-right corners. [fontWeight] defaults to bold; use w800 for extra-bold bottom rank.
  Widget _buildRankSuitText(String text, double fontSize, Color fillColor, TextAlign textAlign, {FontWeight fontWeight = FontWeight.bold}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: fillColor,
        height: 1.0,
      ),
      textAlign: textAlign,
    );
  }

  /// Build bottom-right corner rank/suit: simple white full circle behind, colored rank/suit in front; both centered. Used for all cards.
  Widget _buildBottomRightLayeredText(String text, double fontSize, Color fillColor, TextAlign textAlign) {
    final textSize = fontSize * 2;
    final circleDiameter = textSize * 1.6;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Center(
          child: Container(
            width: circleDiameter,
            height: circleDiameter,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ),
        Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: textSize,
              fontWeight: FontWeight.bold,
              color: fillColor,
              height: 1.0,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Build corner content: for joker show suit only (no rank); otherwise rank + suit text.
  /// Bottom-right: rank plain; suit has white circle behind it. Top-left is plain colored.
  Widget _buildCornerContent(Size dimensions, double blockHeight, double blockWidth, bool isTopLeft) {
    final initialFontSize = blockHeight * 0.45;
    final isJoker = card.rank.toLowerCase() == 'joker';
    final textAlign = isTopLeft ? TextAlign.left : TextAlign.right;

    if (isJoker) {
      return isTopLeft
          ? _buildRankSuitText(card.suitSymbol, initialFontSize, card.color, textAlign)
          : _buildBottomRightLayeredText(card.suitSymbol, initialFontSize, card.color, textAlign);
    }

    if (isTopLeft) {
      final text = '${card.rankSymbol}\n${card.suitSymbol}';
      return _buildRankSuitText(text, initialFontSize, card.color, textAlign);
    }
    // Bottom-right: rank and suit same size; rank plain (bold), suit with white circle behind
    final bottomRightTextSize = initialFontSize * 4;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildRankSuitText(card.rankSymbol, bottomRightTextSize, card.color, textAlign, fontWeight: FontWeight.w800),
        SizedBox(height: blockHeight * 0.05),
        _buildBottomRightLayeredText(card.suitSymbol, initialFontSize, card.color, textAlign),
      ],
    );
  }

  /// Build top-left corner text (rank over suit). Block height = [heightFraction] of column height; full column width so nothing restrains height/size.
  Widget _buildTopLeftCornerText(Size dimensions, {double heightFraction = 1 / 4}) {
    final blockHeight = dimensions.height * heightFraction;
    final blockWidth = dimensions.width;
    const padding = 2.0;

    return SizedBox(
      height: blockHeight,
      width: blockWidth,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topLeft,
          child: _buildCornerContent(dimensions, blockHeight - padding * 2, blockWidth - padding * 2, true),
        ),
      ),
    );
  }

  /// Build bottom-right corner (rank, suit with white circle). Block height = [heightFraction] of column height; full column width so content is not constrained.
  Widget _buildBottomRightCornerText(Size dimensions, {double heightFraction = 3 / 4}) {
    final blockHeight = dimensions.height * heightFraction;
    final blockWidth = dimensions.width;
    const padding = 2.0;

    return SizedBox(
      height: blockHeight,
      width: blockWidth,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.bottomRight,
          child: _buildCornerContent(dimensions, blockHeight - padding * 2, blockWidth - padding * 2, false),
        ),
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
    // Calculate border radius from card dimensions (SSOT approach)
    // Use dynamic calculation from CardDimensions if using default borderRadius (8.0)
    // Otherwise use the explicitly set borderRadius from config
    final borderRadius = (config.borderRadius == 8.0) 
        ? CardDimensions.calculateBorderRadius(dimensions)
        : config.borderRadius;
    
    return Container(
      width: dimensions.width,
      height: dimensions.height,
      decoration: BoxDecoration(
        color: AppColors.primaryColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.28),
            blurRadius: 6,
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
                    if (LOGGING_SWITCH) {
                      _logger.error('🖼️ CardWidget: Asset load error for card_back.png');
                    }
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
                    if (LOGGING_SWITCH) {
                      _logger.error('🖼️ CardWidget: Network image load error, falling back to asset');
                    }
                    // Fallback to asset image if network fails
                    return Image(
                      image: AssetImage('assets/images/card_back.png'),
                      width: dimensions.width * 0.9,
                      height: dimensions.height * 0.9,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        if (LOGGING_SWITCH) {
                          _logger.error('🖼️ CardWidget: Asset fallback also failed');
                        }
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

  /// Build selection wrapper: white border only (no fill), full opacity.
  /// Ensures exact dimensions are maintained.
  Widget _buildSelectionWrapper(Widget child, Size dimensions) {
    final borderRadius = (config.borderRadius == 8.0)
        ? CardDimensions.calculateBorderRadius(dimensions)
        : config.borderRadius;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: AppColors.white,
          width: 3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      ),
    );
  }

}


