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
          // Full height, aspect ratio preserved, aligned left (overflow clipped on right)
          if (isSpecialCard && specialCardImagePath != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(config.borderRadius),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image(
                    image: AssetImage(specialCardImagePath),
                    fit: BoxFit.fitHeight,
                    height: dimensions.height,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
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
                
                // Unified layout for ALL cards: top-left 1/4 height, empty center, bottom-right 3/4 height
                return Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Top-left rank and suit - constrained to remaining 1/3 height (no overflow)
                    Align(
                      alignment: Alignment.topLeft,
                      child: _buildTopLeftCornerText(Size(availableWidth, availableHeight)),
                    ),
                    // Center: nothing
                    const Expanded(child: SizedBox.shrink()),
                    // Bottom-right rank and suit - block 3/4 of card height
                    Align(
                      alignment: Alignment.bottomRight,
                      child: _buildBottomRightCornerText(Size(availableWidth, availableHeight)),
                    ),
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
  /// Whether this card is a special rank (queen, king, jack, joker) – used for stroke size and corner inset.
  bool get _isSpecialRank => card.isFaceCard || card.rank.toLowerCase() == 'joker';

  /// Stroke width for rank/suit outline: doubled for special ranks so it reads over background images.
  double get _strokeWidth => _isSpecialRank ? 6.0 : 3.0;

  /// Inset for corner content so the stroke stays inside card bounds (no overflow, especially pointy symbols).
  double get _cornerStrokeInset => _strokeWidth / 2;

  /// Build rank/suit text. Optional white stroke (outline) only for bottom-right corner so it reads over background images.
  Widget _buildRankSuitText(String text, double fontSize, Color fillColor, TextAlign textAlign, {double? strokeWidth, bool applyStroke = true}) {
    final effectiveStroke = strokeWidth ?? _strokeWidth;
    if (!applyStroke) {
      return Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: fillColor,
          height: 1.0,
        ),
        textAlign: textAlign,
      );
    }
    return Stack(
      children: [
        // White stroke (outline) so text reads over background image (bottom-right only)
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = effectiveStroke
              ..color = AppColors.white,
          ),
          textAlign: textAlign,
        ),
        // Colored fill on top
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: fillColor,
            height: 1.0,
          ),
          textAlign: textAlign,
        ),
      ],
    );
  }

  /// Path to small joker icon for corner (rank). Place PNG at this path; fallback to rank symbol if missing.
  static const String _jokerIconPath = 'assets/images/joker_icon.png';

  /// Build corner content: for joker use PNG icon + suit text; otherwise rank + suit text.
  /// Stroke (border) only on bottom-right corner; top-left has no stroke.
  Widget _buildCornerContent(Size dimensions, double blockHeight, double blockWidth, bool isTopLeft) {
    final initialFontSize = blockHeight * 0.45;
    final isJoker = card.rank.toLowerCase() == 'joker';
    final textAlign = isTopLeft ? TextAlign.left : TextAlign.right;
    final applyStroke = !isTopLeft; // Border only on bottom-right

    if (isJoker) {
      final iconSize = initialFontSize * 1.2;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isTopLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Image.asset(
            _jokerIconPath,
            width: iconSize,
            height: iconSize,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return SizedBox(
                width: iconSize,
                height: iconSize,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: _buildRankSuitText(card.rankSymbol, initialFontSize, card.color, textAlign, applyStroke: applyStroke),
                ),
              );
            },
          ),
          SizedBox(height: blockHeight * 0.05),
          _buildRankSuitText(card.suitSymbol, initialFontSize, card.color, textAlign, applyStroke: applyStroke),
        ],
      );
    }

    final text = '${card.rankSymbol}\n${card.suitSymbol}';
    return _buildRankSuitText(text, initialFontSize, card.color, textAlign, applyStroke: applyStroke);
  }

  /// Build top-left corner text (rank and suit) - block sized to 1/4 of card height after padding, text fits without overflow.
  /// Corner content is inset by _cornerStrokeInset so the stroke stays inside card bounds.
  Widget _buildTopLeftCornerText(Size dimensions) {
    final blockHeight = dimensions.height * (1 / 4);
    final blockWidth = dimensions.width * 0.6;
    final inset = _cornerStrokeInset;

    return SizedBox(
      height: blockHeight,
      width: blockWidth,
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topLeft,
          child: _buildCornerContent(dimensions, blockHeight - inset * 2, blockWidth - inset * 2, true),
        ),
      ),
    );
  }

  /// Build bottom-right corner text (rank and suit) - block sized to 3/4 of card height, text fills that space.
  /// Corner content is inset by _cornerStrokeInset so the stroke stays inside card bounds.
  Widget _buildBottomRightCornerText(Size dimensions) {
    final blockHeight = dimensions.height * (3 / 4);
    final blockWidth = dimensions.width * 0.6;
    final inset = _cornerStrokeInset;

    return SizedBox(
      height: blockHeight,
      width: blockWidth,
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.bottomRight,
          child: _buildCornerContent(dimensions, blockHeight - inset * 2, blockWidth - inset * 2, false),
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

  /// Build selection wrapper with overlay (same color 0.5 opacity, no border)
  /// Ensures exact dimensions are maintained
  Widget _buildSelectionWrapper(Widget child, Size dimensions) {
    final borderRadius = (config.borderRadius == 8.0)
        ? CardDimensions.calculateBorderRadius(dimensions)
        : config.borderRadius;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.successColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }

}


