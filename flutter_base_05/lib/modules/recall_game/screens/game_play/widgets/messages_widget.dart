import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';

/// Messages Widget for Recall Game
/// 
/// This widget displays game messages as a modal overlay.
/// It's hidden by default and only shows when messages are triggered.
/// Used for match notifications like "Match Starting", "Match Over", "Winner", "Points", etc.
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class MessagesWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = true;
  
  const MessagesWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get messages state slice
        final messagesData = recallGameState['messages'] as Map<String, dynamic>? ?? {};
        final isVisible = messagesData['isVisible'] ?? false;
        final title = messagesData['title']?.toString() ?? 'Game Message';
        final content = messagesData['content']?.toString() ?? '';
        final messageType = messagesData['type']?.toString() ?? 'info'; // info, success, warning, error
        final showCloseButton = messagesData['showCloseButton'] ?? true;
        final autoClose = messagesData['autoClose'] ?? false;
        final autoCloseDelay = messagesData['autoCloseDelay'] ?? 3000; // milliseconds
        
        Logger().info('MessagesWidget: isVisible=$isVisible, title=$title, type=$messageType', isOn: LOGGING_SWITCH);
        
        // Don't render if not visible
        if (!isVisible || content.isEmpty) {
          return const SizedBox.shrink();
        }
        
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
    
    return Material(
      color: Colors.black54, // Semi-transparent background
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          constraints: const BoxConstraints(
            maxWidth: 500,
            maxHeight: 600,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getMessageTypeColor(context, messageType).withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getMessageTypeIcon(messageType),
                      color: _getMessageTypeColor(context, messageType),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getMessageTypeColor(context, messageType),
                        ),
                      ),
                    ),
                    if (showCloseButton)
                      IconButton(
                        onPressed: () => _closeMessage(context),
                        icon: const Icon(Icons.close),
                        color: _getMessageTypeColor(context, messageType),
                        tooltip: 'Close message',
                      ),
                  ],
                ),
              ),
              
              // Content area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    content,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              
              // Footer with close button (if enabled)
              if (showCloseButton)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor.withOpacity(0.1),
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
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                        style: TextButton.styleFrom(
                          foregroundColor: _getMessageTypeColor(context, messageType),
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
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'error':
        return Colors.red;
      case 'info':
      default:
        return Theme.of(context).primaryColor;
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
      Logger().info('MessagesWidget: Closing message modal', isOn: LOGGING_SWITCH);
      
      // Update state to hide messages
      StateManager().updateModuleState('recall_game', {
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
      Logger().error('MessagesWidget: Failed to close message: $e', isOn: LOGGING_SWITCH);
    }
  }
}
