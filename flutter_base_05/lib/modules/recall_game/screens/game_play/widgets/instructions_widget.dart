import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../utils/modal_template_widget.dart';

/// Instructions Widget for Recall Game
/// 
/// This widget displays game instructions as a modal overlay.
/// It's hidden by default and only shows when instructions are triggered.
/// Contains an X button to close the modal.
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class InstructionsWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = false;
  static final Logger _logger = Logger();
  
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
        
        _logger.info('InstructionsWidget: isVisible=$isVisible, title=$title', isOn: LOGGING_SWITCH);
        
        // Don't render if not visible
        if (!isVisible || content.isEmpty) {
          return const SizedBox.shrink();
        }
        
        // Show modal using Flutter's official showDialog method
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showInstructionsModal(context, title, content);
        });
        
        return const SizedBox.shrink();
      },
    );
  }

  /// Show the instructions modal using Flutter's official showDialog method
  void _showInstructionsModal(BuildContext context, String title, String content) {
    ModalTemplateWidget.show(
      context: context,
      title: title,
      content: content,
      icon: Icons.help_outline,
      onClose: () => _closeInstructions(context),
    );
  }
  
  void _closeInstructions(BuildContext context) {
    try {
      _logger.info('InstructionsWidget: Closing instructions modal', isOn: LOGGING_SWITCH);
      
      // Close the dialog first
      Navigator.of(context).pop();
      
      // Then update state to hide instructions
      StateManager().updateModuleState('recall_game', {
        'instructions': {
          'isVisible': false,
          'title': '',
          'content': '',
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      _logger.error('InstructionsWidget: Failed to close instructions: $e', isOn: LOGGING_SWITCH);
    }
  }
}
