import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../utils/modal_template_widget.dart';
import '../../../../../utils/consts/theme_consts.dart';
import 'initial_peek_demonstration_widget.dart';
import 'drawing_card_demonstration_widget.dart';
import 'playing_card_demonstration_widget.dart';
import 'queen_peek_demonstration_widget.dart';
import 'jack_swap_demonstration_widget.dart';
import 'same_rank_window_demonstration_widget.dart';
import 'collection_card_demonstration_widget.dart';

/// Instructions Widget for Cleco Game
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
        final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        
        // Get instructions state slice
        final instructionsData = clecoGameState['instructions'] as Map<String, dynamic>? ?? {};
        final isVisible = instructionsData['isVisible'] ?? false;
        final title = instructionsData['title']?.toString() ?? 'Game Instructions';
        final content = instructionsData['content']?.toString() ?? '';
        final instructionKey = instructionsData['key']?.toString();
        final hasDemonstration = instructionsData['hasDemonstration'] as bool? ?? false;
        final isInitial = instructionKey == 'initial' || instructionKey == 'initial_peek';
        
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
            _showInstructionsModal(context, title, content, instructionKey, isInitial, hasDemonstration);
        });
        } else if (!shouldShow) {
          _logger.info('InstructionsWidget: Skipping duplicate modal for key=$instructionKey (already showing)', isOn: LOGGING_SWITCH);
        }
        
        return const SizedBox.shrink();
      },
    );
  }

  /// Show the instructions modal with checkbox for "don't show again"
  void _showInstructionsModal(BuildContext context, String title, String content, String? instructionKey, bool isInitial, bool hasDemonstration) {
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
              backgroundColor: AppColors.card, // Use white card background for better text visibility
              textColor: AppColors.textOnCard, // Use text color for card backgrounds
              customContent: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scrollable content area (demonstration + text)
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        top: AppPadding.defaultPadding.top,
                        left: AppPadding.defaultPadding.left,
                        right: AppPadding.defaultPadding.right,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Demonstration container (only shown if hasDemonstration is true)
                          if (hasDemonstration) ...[
                            Container(
                              width: double.infinity,
                              padding: AppPadding.defaultPadding,
                              decoration: BoxDecoration(
                                color: AppColors.cardVariant,
                                borderRadius: AppBorderRadius.mediumRadius,
                              ),
                      child: instructionKey == 'initial_peek'
                          ? const InitialPeekDemonstrationWidget()
                          : instructionKey == 'drawing_card'
                              ? const DrawingCardDemonstrationWidget()
                              : instructionKey == 'playing_card'
                                  ? const PlayingCardDemonstrationWidget()
                                  : instructionKey == 'queen_peek'
                                      ? const QueenPeekDemonstrationWidget()
                                      : instructionKey == 'jack_swap'
                                          ? const JackSwapDemonstrationWidget()
                                          : instructionKey == 'same_rank_window'
                                              ? const SameRankWindowDemonstrationWidget()
                                              : instructionKey == 'collection_card'
                                                  ? const CollectionCardDemonstrationWidget()
                                                  : const SizedBox(
                                                      height: 150, // Placeholder for other demonstrations
                                                    ),
                            ),
                            SizedBox(height: AppPadding.defaultPadding.top),
                          ],
                          // Text content
                          Padding(
                            padding: AppPadding.defaultPadding,
                            child: Text(
                              content,
                              style: AppTextStyles.bodyMedium(
                                color: AppColors.textOnCard,
                              ).copyWith(
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Footer with checkbox and close button on same line (fixed at bottom)
                  Container(
                    padding: AppPadding.cardPadding,
                    decoration: BoxDecoration(
                      color: AppColors.cardVariant, // Use theme-aware subtle background
                      borderRadius: AppBorderRadius.only(
                        bottomLeft: AppBorderRadius.large,
                        bottomRight: AppBorderRadius.large,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Checkbox for "don't show again" - aligned to the right
                        if (instructionKey != null) ...[
                          // Text before checkbox
                          Text(
                            'Understood, don\'t show again',
                            style: AppTextStyles.bodySmall(
                              color: AppColors.textOnCard,
                            ),
                          ),
                          SizedBox(width: AppPadding.smallPadding.left),
                          // Checkbox
                          Checkbox(
                            value: dontShowAgain,
                            onChanged: (value) {
                              setState(() {
                                dontShowAgain = value ?? false;
                              });
                            },
                            activeColor: AppColors.accentColor,
                            checkColor: AppColors.textOnAccent,
                          ),
                          SizedBox(width: AppPadding.smallPadding.left),
                        ],
                        // Close button (text only, no icon)
                        TextButton(
                          onPressed: () => _closeInstructions(
                            context,
                            instructionKey,
                            dontShowAgain,
                          ),
                          child: Text(
                            'Close',
                            style: AppTextStyles.buttonText(
                              color: AppColors.textOnAccent,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textOnAccent,
                            backgroundColor: AppColors.accentColor,
                            padding: AppPadding.cardPadding,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppBorderRadius.smallRadius,
                            ),
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
        final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        final instructionsData = clecoGameState['instructions'] as Map<String, dynamic>? ?? {};
        final currentDontShowAgain = Map<String, bool>.from(
          instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
        );
        
        StateManager().updateModuleState('cleco_game', {
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
      final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
      final instructionsData = clecoGameState['instructions'] as Map<String, dynamic>? ?? {};
      final currentDontShowAgain = Map<String, bool>.from(
        instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
      );
      
      // Update dontShowAgain map if checkbox was checked
      // For initial and initial_peek instructions, always mark as "don't show again" since checkbox is pre-checked
      if (instructionKey != null) {
        if (dontShowAgain || instructionKey == 'initial' || instructionKey == 'initial_peek') {
          currentDontShowAgain[instructionKey] = true;
        }
      }
      
      // Update state to hide instructions and save dontShowAgain preferences
      StateManager().updateModuleState('cleco_game', {
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
