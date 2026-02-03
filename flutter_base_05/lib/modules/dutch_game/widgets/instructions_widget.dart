import 'package:flutter/material.dart';
import '../../../core/managers/state_manager.dart';
import '../../../core/managers/navigation_manager.dart';
import '../../../tools/logging/logger.dart';
import '../utils/modal_template_widget.dart';
import '../../../utils/consts/theme_consts.dart';
import 'initial_peek_demonstration_widget.dart';
import 'drawing_card_demonstration_widget.dart';
import 'playing_card_demonstration_widget.dart';
import 'queen_peek_demonstration_widget.dart';
import 'jack_swap_demonstration_widget.dart';
import 'same_rank_window_demonstration_widget.dart';
import 'collection_card_demonstration_widget.dart';

/// Instructions Widget for Dutch Game
/// 
/// This widget displays game instructions as a modal overlay.
/// It's hidden by default and only shows when instructions are triggered.
/// Contains an X button to close the modal and a "don't show again" checkbox.
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class InstructionsWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = true;
  static final Logger _logger = Logger();
  
  // Track currently showing instruction key to prevent duplicate modals
  static String? _currentlyShowingKey;
  
  const InstructionsWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        
        // Get instructions state slice
        final instructionsData = dutchGameState['instructions'] as Map<String, dynamic>? ?? {};
        final isVisible = instructionsData['isVisible'] ?? false;
        final title = instructionsData['title']?.toString() ?? 'Game Instructions';
        final content = instructionsData['content']?.toString() ?? '';
        final instructionKey = instructionsData['key']?.toString();
        final hasDemonstration = instructionsData['hasDemonstration'] as bool? ?? false;
        final isInitial = instructionKey == 'initial' || instructionKey == 'initial_peek';
        // Get optional custom close callback (function reference stored in state)
        final onCloseCallback = instructionsData['onClose'] as void Function()?;
        
        if (LOGGING_SWITCH) {
          _logger.info('InstructionsWidget: isVisible=$isVisible, title=$title, key=$instructionKey, currentlyShowing=$_currentlyShowingKey');
        }
        
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
            _showInstructionsModal(
              context, 
              title, 
              content, 
              instructionKey, 
              isInitial, 
              hasDemonstration,
              onCloseCallback,
            );
        });
        } else if (!shouldShow) {
          if (LOGGING_SWITCH) {
            _logger.info('InstructionsWidget: Skipping duplicate modal for key=$instructionKey (already showing)');
          }
        }
        
        return const SizedBox.shrink();
      },
    );
  }

  /// Get status color for instruction key (matches PlayerStatusChip colors)
  /// Returns null for instructions without status colors (initial, collection_card)
  Color? _getStatusColorForInstructionKey(String? instructionKey) {
    if (instructionKey == null) return null;
    
    switch (instructionKey) {
      case 'initial_peek':
        return AppColors.statusInitialPeek; // Teal
      case 'drawing_card':
        return AppColors.statusDrawing; // Orange
      case 'playing_card':
        return AppColors.statusPlaying; // Green
      case 'queen_peek':
        return AppColors.statusQueenPeek; // Pink
      case 'jack_swap':
        return AppColors.statusJackSwap; // Indigo
      case 'same_rank_window':
        return AppColors.statusSameRank; // Purple
      case 'initial':
      case 'collection_card':
      default:
        return null; // No status color - use default accent color
    }
  }

  /// Show the instructions modal with checkbox for "don't show again"
  /// Uses root navigator to be independent of screen constraints
  /// 
  /// [onCloseCallback] - Optional custom callback to execute when close button is pressed.
  ///                     If provided, this will be called instead of the default close behavior.
  ///                     The default behavior (closing the widget) will still execute after the callback.
  void _showInstructionsModal(
    BuildContext context, 
    String title, 
    String content, 
    String? instructionKey, 
    bool isInitial, 
    bool hasDemonstration,
    void Function()? onCloseCallback,
  ) {
    // Get status color for this instruction key
    final headerColor = _getStatusColorForInstructionKey(instructionKey);
    
    // Get root navigator context - independent of screen constraints
    final navigationManager = NavigationManager();
    final rootNavigator = navigationManager.navigatorKey.currentContext;
    
    // Use root context if available, otherwise fall back to provided context
    final dialogContext = rootNavigator ?? context;
    
    if (LOGGING_SWITCH) {
      _logger.info('InstructionsWidget: Showing modal with rootNavigator=${rootNavigator != null}');
    }
    
    // Use root navigator to ensure modal is independent of screen constraints
    showDialog(
      context: dialogContext,
      barrierDismissible: true,
      useRootNavigator: true, // Always use root navigator for independence
      barrierColor: AppColors.black.withOpacity(AppOpacity.barrier), // Ensure barrier is visible
      builder: (BuildContext builderContext) {
            return ModalTemplateWidget(
              title: title,
              content: content,
              icon: Icons.help_outline,
              showCloseButton: false, // Remove X button in header
              showFooter: false, // Remove default footer
              backgroundColor: AppColors.card, // Use white card background for better text visibility
              textColor: AppColors.textOnCard, // Use text color for card backgrounds
              headerColor: headerColor, // Use status color for header title and border
              fullScreen: true, // Use full screen for independence from screen constraints
              customContent: Column(
                mainAxisSize: MainAxisSize.max, // Use max to fill available space
                children: [
                  // Scrollable content area (demonstration + text) - takes all available space
                  Expanded(
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
                  // Footer with close button (fixed at bottom)
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
                        // Close button (text only, no icon)
                        TextButton(
                          onPressed: () => _closeInstructions(
                            builderContext,
                            instructionKey,
                            onCloseCallback,
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
    ).then((_) {
      // Handle dialog dismissal (either by close button or tapping outside)
      // Clear the currently showing key when dialog is dismissed
      if (_currentlyShowingKey == instructionKey) {
        _currentlyShowingKey = null;
        
        // Execute custom close callback if provided (for tapping outside dismissal)
        if (onCloseCallback != null) {
          if (LOGGING_SWITCH) {
            _logger.info('InstructionsWidget: Executing custom close callback for key=$instructionKey (dismissed by tapping outside)');
          }
          try {
            onCloseCallback();
          } catch (e) {
            if (LOGGING_SWITCH) {
              _logger.error('InstructionsWidget: Error executing custom close callback: $e');
            }
          }
        }
        
        // Also update state to hide instructions
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final instructionsData = dutchGameState['instructions'] as Map<String, dynamic>? ?? {};
        final currentDontShowAgain = Map<String, bool>.from(
          instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
        );
        
        StateManager().updateModuleState('dutch_game', {
          'instructions': {
            'isVisible': false,
            'title': '',
            'content': '',
            'key': '',
            'dontShowAgain': currentDontShowAgain,
            'onClose': null, // Clear custom callback
          },
        });
      }
    });
  }
  
  /// Close instructions modal
  /// 
  /// [onCloseCallback] - Optional custom callback to execute before default close behavior.
  ///                     If provided, this will be called first, then the default behavior executes.
  void _closeInstructions(
    BuildContext context, 
    String? instructionKey,
    void Function()? onCloseCallback,
  ) {
    try {
      if (LOGGING_SWITCH) {
        _logger.info('InstructionsWidget: Closing instructions modal, key=$instructionKey, hasCustomCallback=${onCloseCallback != null}');
      }
      
      // Execute custom close callback if provided (instruction-specific action)
      if (onCloseCallback != null) {
        if (LOGGING_SWITCH) {
          _logger.info('InstructionsWidget: Executing custom close callback for key=$instructionKey');
        }
        try {
          onCloseCallback();
        } catch (e) {
          if (LOGGING_SWITCH) {
            _logger.error('InstructionsWidget: Error executing custom close callback: $e');
          }
        }
      }
      
      // Default behavior: Clear currently showing key
      if (_currentlyShowingKey == instructionKey) {
        _currentlyShowingKey = null;
      }
      
      // Default behavior: Close the dialog
      Navigator.of(context).pop();
      
      // Default behavior: Get current dontShowAgain map
      final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
      final instructionsData = dutchGameState['instructions'] as Map<String, dynamic>? ?? {};
      final currentDontShowAgain = Map<String, bool>.from(
        instructionsData['dontShowAgain'] as Map<String, dynamic>? ?? {},
      );
      
      // Default behavior: Update state to hide instructions
      StateManager().updateModuleState('dutch_game', {
        'instructions': {
          'isVisible': false,
          'title': '',
          'content': '',
          'key': '',
          'dontShowAgain': currentDontShowAgain,
          'onClose': null, // Clear custom callback
        },
        // Removed lastUpdated - causes unnecessary state updates
      });
      
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.error('InstructionsWidget: Failed to close instructions: $e');
      }
      // Clear the flag even on error
      if (_currentlyShowingKey == instructionKey) {
        _currentlyShowingKey = null;
      }
    }
  }
}
