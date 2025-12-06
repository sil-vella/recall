import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../utils/modal_template_widget.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Instructions Widget for Recall Game
/// 
/// This widget displays game instructions as a modal overlay.
/// It's hidden by default and only shows when instructions are triggered.
/// Contains an X button to close the modal and a "don't show again" checkbox.
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class InstructionsWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = false;
  static final Logger _logger = Logger();
  
  // Track currently showing instruction key to prevent duplicate modals
  static String? _currentlyShowingKey;
  
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
        final instructionKey = instructionsData['key']?.toString();
        final isInitial = instructionKey == 'initial';
        
        _logger.info('InstructionsWidget: isVisible=$isVisible, title=$title, key=$instructionKey, currentlyShowing=$_currentlyShowingKey', isOn: LOGGING_SWITCH);
        
        // Don't render if not visible
        if (!isVisible || content.isEmpty) {
          // Clear currently showing key if instructions are hidden
          if (_currentlyShowingKey != null) {
            _currentlyShowingKey = null;
          }
          return const SizedBox.shrink();
        }
        
        // Only show modal if:
        // 1. No modal is currently showing, OR
        // 2. The instruction key has changed (different instruction type)
        final shouldShow = _currentlyShowingKey == null || _currentlyShowingKey != instructionKey;
        
        if (shouldShow && instructionKey != null) {
          // Mark this instruction as currently showing
          _currentlyShowingKey = instructionKey;
          
          // Show modal using Flutter's official showDialog method
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showInstructionsModal(context, title, content, instructionKey, isInitial);
          });
        } else if (!shouldShow) {
          _logger.info('InstructionsWidget: Skipping duplicate modal for key=$instructionKey (already showing)', isOn: LOGGING_SWITCH);
        }
        
        return const SizedBox.shrink();
      },
    );
  }

  /// Show the instructions modal with checkbox for "don't show again"
  void _showInstructionsModal(BuildContext context, String title, String content, String? instructionKey, bool isInitial) {
    // Use a StatefulBuilder to manage checkbox state
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        bool dontShowAgain = isInitial; // Initial message auto-checks the box
        
        return StatefulBuilder(
          builder: (context, setState) {
            return ModalTemplateWidget(
              title: title,
              content: content,
              icon: Icons.help_outline,
              showCloseButton: false, // Remove X button in header
              showFooter: false, // Remove default footer
              customContent: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  // Footer with checkbox and close button on same line
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor.withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Checkbox for "don't show again"
                        if (instructionKey != null) ...[
                          Checkbox(
                            value: dontShowAgain,
                            onChanged: (value) {
                              setState(() {
                                dontShowAgain = value ?? false;
                              });
                            },
                            activeColor: AppColors.accentColor,
                          ),
                          Expanded(
                            child: Text(
                              'Understood, don\'t show again',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ] else
                          const Spacer(),
                        // Close button
                        TextButton.icon(
                          onPressed: () => _closeInstructions(
                            context,
                            instructionKey,
                            dontShowAgain,
                          ),
                          icon: const Icon(Icons.close),
                          label: const Text('Close'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accentColor,
                            backgroundColor: AppColors.primaryColor,
                            padding: AppPadding.cardPadding,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      // Handle dialog dismissal (either by close button or tapping outside)
      // Clear the currently showing key when dialog is dismissed
      if (_currentlyShowingKey == instructionKey) {
        _currentlyShowingKey = null;
        // Also update state to hide instructions
        final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        final instructionsData = recallGameState['instructions'] as Map<String, dynamic>? ?? {};
        final currentDontShowAgain = Map<String, bool>.from(
          instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
        );
        
        StateManager().updateModuleState('recall_game', {
          'instructions': {
            'isVisible': false,
            'title': '',
            'content': '',
            'key': '',
            'dontShowAgain': currentDontShowAgain,
          },
        });
      }
    });
  }
  
  void _closeInstructions(BuildContext context, String? instructionKey, bool dontShowAgain) {
    try {
      _logger.info('InstructionsWidget: Closing instructions modal, key=$instructionKey, dontShowAgain=$dontShowAgain', isOn: LOGGING_SWITCH);
      
      // Clear currently showing key
      if (_currentlyShowingKey == instructionKey) {
        _currentlyShowingKey = null;
      }
      
      // Close the dialog first
      Navigator.of(context).pop();
      
      // Get current dontShowAgain map
      final recallGameState = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
      final instructionsData = recallGameState['instructions'] as Map<String, dynamic>? ?? {};
      final currentDontShowAgain = Map<String, bool>.from(
        instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
      );
      
      // Update dontShowAgain map if checkbox was checked
      if (instructionKey != null && dontShowAgain) {
        currentDontShowAgain[instructionKey] = true;
      }
      
      // Update state to hide instructions and save dontShowAgain preferences
      StateManager().updateModuleState('recall_game', {
        'instructions': {
          'isVisible': false,
          'title': '',
          'content': '',
          'key': '',
          'dontShowAgain': currentDontShowAgain,
        },
        'lastUpdated': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      _logger.error('InstructionsWidget: Failed to close instructions: $e', isOn: LOGGING_SWITCH);
      // Clear the flag even on error
      if (_currentlyShowingKey == instructionKey) {
        _currentlyShowingKey = null;
      }
    }
  }
}
