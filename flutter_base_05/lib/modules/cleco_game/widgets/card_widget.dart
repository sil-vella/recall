import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/card_display_config.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../utils/consts/config.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';

/// A reusable card widget for the Cleco game
/// 
/// Size is determined at the placement widget level and passed as dimensions.
/// Config only controls appearance (displayMode, showPoints, etc.)
class CardWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = true; // Enable logging for card back image debugging
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
    Widget cardContent = showBack || card.isFaceDown || !card.hasFullData
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
      child: Padding(
        padding: EdgeInsets.all(dimensions.width * 0.05),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Centered display mode: rank and suit in center, no corners
            if (config.displayMode == CardDisplayMode.centeredOnly) ...[
              Expanded(
                child: Center(
                  child: _buildCenteredRankAndSuit(dimensions),
                ),
              ),
            ] else ...[
              // Top-left rank and suit (always shown for non-centered modes)
              Align(
                alignment: Alignment.topLeft,
                child: _buildCornerText(dimensions),
              ),
              
              // Center suit symbol (always shown for non-centered modes)
              Expanded(
                child: Center(
                  child: _buildCenterSuit(dimensions),
                ),
              ),
              
              // Bottom-right rank and suit (rotated) - only shown in fullCorners mode
              if (config.displayMode == CardDisplayMode.fullCorners) ...[
                Align(
                  alignment: Alignment.bottomRight,
                  child: Transform.rotate(
                    angle: 3.14159, // 180 degrees
                    child: _buildCornerText(dimensions),
                  ),
                ),
              ],
            ],
            
            // Special power indicator
            if (config.showSpecialPower && card.hasSpecialPower) ...[
              const SizedBox(height: 4),
              _buildSpecialPowerIndicator(dimensions),
            ],
            
            // Points indicator
            if (config.showPoints) ...[
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

  /// Build centered rank and suit (for opponent cards)
  /// Shows rank and suit in the center, text size is 40% of card height
  Widget _buildCenteredRankAndSuit(Size dimensions) {
    final fontSize = dimensions.height * 0.4; // 40% of card height
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
        ),
        // Suit
        Text(
          card.suitSymbol,
          style: TextStyle(
            fontSize: fontSize,
            color: card.color,
            height: 1.0,
          ),
        ),
      ],
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
        child: Stack(
          children: [
            // Structure matching front face - placeholders for layout consistency
            Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Centered mode: no corner placeholders needed
            if (config.displayMode == CardDisplayMode.centeredOnly) ...[
              Expanded(child: Container()), // Spacer for centered content
            ] else ...[
              // Top-left placeholder to match front face structure
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: dimensions.width * 0.12,
                  height: dimensions.width * 0.12 * 2, // Match corner text height (2 lines)
                ),
              ),
              
              // Expanded spacer to match front face structure
              Expanded(child: Container()),
              
              // Bottom-right placeholder to match front face structure (when fullCorners mode)
              if (config.displayMode == CardDisplayMode.fullCorners) ...[
                Align(
                  alignment: Alignment.bottomRight,
                  child: SizedBox(
                    width: dimensions.width * 0.12,
                    height: dimensions.width * 0.12 * 2, // Match corner text height (2 lines)
                  ),
                ),
              ],
            ],
            
            // Special power indicator placeholder to match front face structure
            if (config.showSpecialPower && card.hasSpecialPower) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: dimensions.width * 0.2,
                height: dimensions.width * 0.2, // Match icon size
              ),
            ],
            
            // Points indicator placeholder to match front face structure
            if (config.showPoints) ...[
              const SizedBox(height: 2),
              SizedBox(
                width: dimensions.width * 0.3,
                height: dimensions.width * 0.1 + 4, // Match points indicator height (fontSize + padding)
              ),
            ],
              ],
            ),
            
            // Center the card back image - loaded from server with cache-busting per match
            Center(
              child: ListenableBuilder(
                listenable: StateManager(),
                builder: (context, child) {
                  // Get currentGameId to detect practice mode
                  final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
                  final currentGameId = clecoGameState['currentGameId']?.toString() ?? '';
                  
                  // Detect practice mode: practice games have IDs starting with "practice_room_"
                  final isPracticeMode = currentGameId.startsWith('practice_room_');
                  
                  // Log image loading details
                  _logger.info('🖼️ CardWidget: Loading card back image', isOn: LOGGING_SWITCH);
                  _logger.info('🖼️ CardWidget: currentGameId=$currentGameId', isOn: LOGGING_SWITCH);
                  _logger.info('🖼️ CardWidget: isPracticeMode=$isPracticeMode', isOn: LOGGING_SWITCH);
                  
                  // In practice mode, load from assets; otherwise load from server
                  if (isPracticeMode) {
                    // Load from assets for practice mode
                    _logger.info('🖼️ CardWidget: Loading from assets: assets/images/card_back.png', isOn: LOGGING_SWITCH);
                    return Image.asset(
                      'assets/images/card_back.png',
                      width: dimensions.width * 0.9, // Leave some padding
                      height: dimensions.height * 0.9,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        _logger.error('🖼️ CardWidget: Asset load error for assets/images/card_back.png', isOn: LOGGING_SWITCH);
                        _logger.error('🖼️ CardWidget: Error details: $error', isOn: LOGGING_SWITCH);
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
                    
                    _logger.info('🖼️ CardWidget: apiUrl=${Config.apiUrl}', isOn: LOGGING_SWITCH);
                    _logger.info('🖼️ CardWidget: imageUrl=$imageUrl', isOn: LOGGING_SWITCH);
                    
                    // Use Image.network which uses browser's native image loading on web
                    // This avoids CORS issues that affect the http package
                    return Image.network(
                      imageUrl,
                      width: dimensions.width * 0.9, // Leave some padding
                      height: dimensions.height * 0.9,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          _logger.info('🖼️ CardWidget: Image loaded successfully', isOn: LOGGING_SWITCH);
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
                        _logger.error('🖼️ CardWidget: Image load error for $imageUrl', isOn: LOGGING_SWITCH);
                        _logger.error('🖼️ CardWidget: Error details: $error', isOn: LOGGING_SWITCH);
                        _logger.error('🖼️ CardWidget: Stack trace: $stackTrace', isOn: LOGGING_SWITCH);
                        if (error is Exception) {
                          _logger.error('🖼️ CardWidget: Exception type: ${error.runtimeType}', isOn: LOGGING_SWITCH);
                          _logger.error('🖼️ CardWidget: Exception message: ${error.toString()}', isOn: LOGGING_SWITCH);
                        }
                        return Icon(
                          Icons.broken_image,
                          size: dimensions.width * 0.4,
                          color: AppColors.white.withOpacity(0.5),
                        );
                      },
                    );
                  }
                },
              ),
            ),
          ],
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


