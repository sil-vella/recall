import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';

/// Instructions Widget for Recall Game
/// 
/// This widget displays game instructions as a modal overlay.
/// It's hidden by default and only shows when instructions are triggered.
/// Contains an X button to close the modal.
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class InstructionsWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = true;
  
  const InstructionsWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Get instructions state slice
        final instructionsData = recallGameState['instructions'] as Map<String, dynamic>? ?? {};
        final isVisible = instructionsData['isVisible'] ?? false;
        final title = instructionsData['title']?.toString() ?? 'Game Instructions';
        final content = instructionsData['content']?.toString() ?? '';
        
        Logger().info('InstructionsWidget: isVisible=$isVisible, title=$title', isOn: LOGGING_SWITCH);
        
        // Don't render if not visible
        if (!isVisible || content.isEmpty) {
          return const SizedBox.shrink();
        }
        
        return _buildModalOverlay(context, title, content);
      },
    );
  }
  
  Widget _buildModalOverlay(BuildContext context, String title, String content) {
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
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.help_outline,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _closeInstructions(context),
                      icon: const Icon(Icons.close),
                      color: Theme.of(context).primaryColor,
                      tooltip: 'Close instructions',
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
                  ),
                ),
              ),
              
              // Footer with close button
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
                      onPressed: () => _closeInstructions(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
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
  
  void _closeInstructions(BuildContext context) {
    try {
      Logger().info('InstructionsWidget: Closing instructions modal', isOn: LOGGING_SWITCH);
      
      // Update state to hide instructions
      StateManager().updateModuleState('recall_game', {
        'instructions': {
          'isVisible': false,
          'title': '',
          'content': '',
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      Logger().error('InstructionsWidget: Failed to close instructions: $e', isOn: LOGGING_SWITCH);
    }
  }
}
