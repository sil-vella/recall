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
  static const bool LOGGING_SWITCH = false; // Enabled for winner modal debugging
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
        _logger.info('📬 MessagesWidget: State update - isVisible=$isVisible, gamePhase=$gamePhase, isGameEnded=$isGameEnded, title="$title", content="$contentPreview", type=$messageType', isOn: LOGGING_SWITCH);
        _logger.info('📬 MessagesWidget: Full messagesData keys: ${messagesData.keys.toList()}', isOn: LOGGING_SWITCH);
        
        // Don't render if not visible, content is empty, or game hasn't ended
        if (!isVisible || content.isEmpty || !isGameEnded) {
          _logger.info('📬 MessagesWidget: Not rendering - isVisible=$isVisible, content.isEmpty=${content.isEmpty}, isGameEnded=$isGameEnded', isOn: LOGGING_SWITCH);
          return const SizedBox.shrink();
        }
        
        _logger.info('📬 MessagesWidget: Rendering modal with title="$title" (game phase is game_ended)', isOn: LOGGING_SWITCH);
        
        return _buildModalOverlay(context, title, content, messageType, showCloseButton, autoClose, autoCloseDelay);
      },
    );
  }
  
  Widget _buildModalOverlay(BuildContext context, String title, String content, String messageType, bool showCloseButton, bool autoClose, int autoCloseDelay) {
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
              
              // Content area
              Flexible(
                child: SingleChildScrollView(
                  padding: AppPadding.cardPadding,
                  child: Text(
                    content,
                    style: AppTextStyles.bodyMedium().copyWith(
                      color: AppColors.white, // Use white for maximum contrast on dark widgetContainerBackground
                      height: 1.5,
                      fontWeight: FontWeight.w500, // Slightly bolder for better readability
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
      _logger.info('MessagesWidget: Closing message modal', isOn: LOGGING_SWITCH);
      
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
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      _logger.error('MessagesWidget: Failed to close message: $e', isOn: LOGGING_SWITCH);
    }
  }
}
