import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Messages Widget for Dutch Game
/// 
/// This widget displays game messages as a modal overlay.
/// It's hidden by default and only shows when messages are triggered.
/// Used for match notifications like "Match Starting", "Match Over", "Winner", "Points", etc.
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class MessagesWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = true; // Enabled for winner modal debugging
  static final Logger _logger = Logger();
  
  const MessagesWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        
        // Get messages state slice
        final messagesData = dutchGameState['messages'] as Map<String, dynamic>? ?? {};
        final isVisible = messagesData['isVisible'] ?? false;
        final title = messagesData['title']?.toString() ?? 'Game Message';
        final content = messagesData['content']?.toString() ?? '';
        final messageType = messagesData['type']?.toString() ?? 'info'; // info, success, warning, error
        final showCloseButton = messagesData['showCloseButton'] ?? true;
        final autoClose = messagesData['autoClose'] ?? false;
        final autoCloseDelay = messagesData['autoCloseDelay'] ?? 3000; // milliseconds
        
        // Get game phase to ensure modal only shows when game has ended
        final gamePhase = dutchGameState['gamePhase']?.toString() ?? '';
        final isGameEnded = gamePhase == 'game_ended';
        
        final contentPreview = content.length > 50 ? '${content.substring(0, 50)}...' : content;
        if (LOGGING_SWITCH) {
          _logger.info('📬 MessagesWidget: State update - isVisible=$isVisible, gamePhase=$gamePhase, isGameEnded=$isGameEnded, title="$title", content="$contentPreview", type=$messageType');
        }
        if (LOGGING_SWITCH) {
          _logger.info('📬 MessagesWidget: Full messagesData keys: ${messagesData.keys.toList()}');
        }
        
        // Don't render if not visible, or game hasn't ended (allow empty content when we have ordered winners)
        if (!isVisible || !isGameEnded) {
          if (LOGGING_SWITCH) {
            _logger.info('📬 MessagesWidget: Not rendering - isVisible=$isVisible, isGameEnded=$isGameEnded');
          }
          return const SizedBox.shrink();
        }
        
        // Get ordered winners list from current game state for end-of-game popup
        final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
        final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGame = games[currentGameId] as Map<String, dynamic>?;
        final gameData = currentGame?['gameData'] as Map<String, dynamic>?;
        final gameState = gameData?['game_state'] as Map<String, dynamic>?;
        final orderedWinners = gameState?['winners'] as List<dynamic>?;
        final hasOrderedWinners = orderedWinners != null && orderedWinners.isNotEmpty;
        if (!hasOrderedWinners && content.isEmpty) {
          if (LOGGING_SWITCH) {
            _logger.info('📬 MessagesWidget: Not rendering - content empty and no ordered winners');
          }
          return const SizedBox.shrink();
        }
        
        if (LOGGING_SWITCH) {
          _logger.info('📬 MessagesWidget: Rendering modal with title="$title" (game phase is game_ended)');
        }
        
        return _buildModalOverlay(
          context,
          title,
          content,
          messageType,
          showCloseButton,
          autoClose,
          autoCloseDelay,
          orderedWinners: hasOrderedWinners ? orderedWinners : null,
        );
      },
    );
  }
  
  Widget _buildModalOverlay(
    BuildContext context,
    String title,
    String content,
    String messageType,
    bool showCloseButton,
    bool autoClose,
    int autoCloseDelay, {
    List<dynamic>? orderedWinners,
  }) {
    // Auto-close timer if enabled
    if (autoClose) {
      Future.delayed(Duration(milliseconds: autoCloseDelay), () {
        _closeMessage(context);
      });
    }
    
    final messageTypeColor = _getMessageTypeColor(context, messageType);
    // Blend message type color with widget container background for better contrast
    // Use 15% message color + 85% container background to create a subtle tinted header
    final headerBackgroundColor = Color.lerp(
      AppColors.widgetContainerBackground,
      messageTypeColor,
      0.15,
    ) ?? AppColors.widgetContainerBackground;
    // Calculate text color based on the header background to ensure readability
    final headerTextColor = ThemeConfig.getTextColorForBackground(headerBackgroundColor);
    
    return Material(
      color: AppColors.black.withValues(alpha: 0.54), // Semi-transparent background
      child: Center(
        child: Container(
          margin: AppPadding.defaultPadding,
          constraints: const BoxConstraints(
            maxWidth: 500,
            maxHeight: 600,
          ),
          decoration: BoxDecoration(
            color: AppColors.widgetContainerBackground,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with title and close button
              Container(
                padding: AppPadding.cardPadding,
                decoration: BoxDecoration(
                  color: headerBackgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getMessageTypeIcon(messageType),
                      color: messageTypeColor,
                      size: 24,
                    ),
                    SizedBox(width: AppPadding.smallPadding.left),
                    Expanded(
                      child: Text(
                        title,
                        style: AppTextStyles.headingSmall().copyWith(
                          color: headerTextColor,
                        ),
                      ),
                    ),
                    if (showCloseButton)
                      IconButton(
                        onPressed: () => _closeMessage(context),
                        icon: Icon(
                          Icons.close,
                          color: headerTextColor,
                        ),
                        tooltip: 'Close message',
                      ),
                  ],
                ),
              ),
              
              // Content area: ordered winners list (game ended) or plain message
              Flexible(
                child: SingleChildScrollView(
                  padding: AppPadding.cardPadding,
                  child: orderedWinners != null && orderedWinners.isNotEmpty
                      ? _buildOrderedWinnersContent(orderedWinners)
                      : Text(
                          content,
                          style: AppTextStyles.bodyMedium().copyWith(
                            color: AppColors.white,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              
              // Footer with close button (if enabled)
              if (showCloseButton)
                Container(
                  padding: AppPadding.cardPadding,
                  decoration: BoxDecoration(
                    color: AppColors.cardVariant,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _closeMessage(context),
                        icon: Icon(
                          Icons.close,
                          color: AppColors.textOnCard,
                        ),
                        label: Text(
                          'Close',
                          style: AppTextStyles.buttonText().copyWith(
                            color: AppColors.textOnCard,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textOnCard,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Build content for game-ended popup: ordered list (winners at top, then by points).
  Widget _buildOrderedWinnersContent(List<dynamic> orderedWinners) {
    String winTypeLabel(dynamic winType) {
      switch (winType?.toString()) {
        case 'four_of_a_kind':
          return 'Four of a Kind';
        case 'empty_hand':
          return 'No Cards Left';
        case 'lowest_points':
          return 'Lowest Points';
        case 'dutch':
          return 'Dutch Called';
        default:
          return 'Winner';
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < orderedWinners.length; i++) ...[
          if (i > 0) SizedBox(height: AppPadding.smallPadding.top),
          Builder(
            builder: (context) {
              final e = orderedWinners[i];
              if (e is! Map<String, dynamic>) return const SizedBox.shrink();
              final name = e['playerName']?.toString() ?? 'Unknown';
              final winType = e['winType'];
              final points = e['points'] as int?;
              final cardCount = e['cardCount'] as int?;
              final isWinner = winType != null && winType.toString().isNotEmpty;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${i + 1}. ',
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      name,
                      style: AppTextStyles.bodyMedium().copyWith(
                        color: AppColors.white,
                        fontWeight: isWinner ? FontWeight.w600 : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    isWinner
                        ? ' (${winTypeLabel(winType)}) — ${points ?? 0} pts, ${cardCount ?? 0} cards'
                        : (points != null && cardCount != null
                            ? ' — ${points} pts, $cardCount cards'
                            : ''),
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: isWinner ? AppColors.successColor : AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Color _getMessageTypeColor(BuildContext context, String messageType) {
    switch (messageType) {
      case 'success':
        return AppColors.successColor;
      case 'warning':
        return AppColors.warningColor;
      case 'error':
        return AppColors.errorColor;
      case 'info':
      default:
        return AppColors.infoColor;
    }
  }
  
  IconData _getMessageTypeIcon(String messageType) {
    switch (messageType) {
      case 'success':
        return Icons.check_circle;
      case 'warning':
        return Icons.warning;
      case 'error':
        return Icons.error;
      case 'info':
      default:
        return Icons.info;
    }
  }
  
  void _closeMessage(BuildContext context) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('MessagesWidget: Closing message modal');
      }
      
      // Update state to hide messages
      StateManager().updateModuleState('dutch_game', {
        'messages': {
          'isVisible': false,
          'title': '',
          'content': '',
          'type': 'info',
          'showCloseButton': true,
          'autoClose': false,
          'autoCloseDelay': 3000,
        },
        // Removed lastUpdated - causes unnecessary state updates
      });
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('MessagesWidget: Failed to close message: $e');
      }
    }
  }
}
