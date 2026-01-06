import 'package:flutter/material.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import 'demo_functionality.dart';

/// Demo Instructions Widget
/// 
/// Displays instructions for the current demo phase at the top of the demo screen.
/// Shows title and paragraph text based on the current game phase.
class DemoInstructionsWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = false;
  static final Logger _logger = Logger();
  
  const DemoInstructionsWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get demo instructions phase from state (separate from game phase)
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final demoInstructionsPhase = dutchGameState['demoInstructionsPhase']?.toString() ?? '';
        
        // Get instructions for current demo phase
        final instructions = DemoFunctionality.instance.getInstructionsForPhase(demoInstructionsPhase);
        final isVisible = instructions['isVisible'] as bool? ?? false;
        final title = instructions['title']?.toString() ?? '';
        final paragraph = instructions['paragraph']?.toString() ?? '';
        
        _logger.info('DemoInstructionsWidget: demoPhase=$demoInstructionsPhase, isVisible=$isVisible, title=$title', isOn: LOGGING_SWITCH);
        
        // Don't render if not visible or no content
        if (!isVisible || title.isEmpty || paragraph.isEmpty) {
          return const SizedBox.shrink();
        }
        
        return Container(
          width: double.infinity,
          padding: AppPadding.defaultPadding,
          margin: EdgeInsets.only(
            left: AppPadding.defaultPadding.left,
            right: AppPadding.defaultPadding.right,
            top: AppPadding.defaultPadding.top,
            bottom: AppPadding.smallPadding.bottom,
          ),
          decoration: BoxDecoration(
            color: AppColors.scaffoldBackgroundColor.withValues(alpha: 0.95),
            borderRadius: BorderRadius.only(
              bottomLeft: AppBorderRadius.mediumRadius.bottomLeft,
              bottomRight: AppBorderRadius.mediumRadius.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                title,
                style: AppTextStyles.headingSmall().copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: AppPadding.smallPadding.top),
              // Paragraph
              Text(
                paragraph,
                style: AppTextStyles.bodyMedium().copyWith(
                  color: AppColors.white,
                  height: 1.5,
                ),
              ),
              // "Let's go" button - only shown for initial phase
              if (demoInstructionsPhase == 'initial') ...[
                SizedBox(height: AppPadding.defaultPadding.top),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {
                      _logger.info('DemoInstructionsWidget: "Let\'s go" button pressed', isOn: LOGGING_SWITCH);
                      DemoFunctionality.instance.transitionToInitialPeek();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentColor,
                      foregroundColor: AppColors.textOnAccent,
                      padding: AppPadding.cardPadding,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppBorderRadius.smallRadius,
                      ),
                    ),
                    child: Text(
                      'Let\'s go',
                      style: AppTextStyles.buttonText(
                        color: AppColors.textOnAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

