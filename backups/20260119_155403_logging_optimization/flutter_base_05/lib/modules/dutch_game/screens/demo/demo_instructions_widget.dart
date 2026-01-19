import 'package:flutter/material.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../managers/dutch_game_state_updater.dart';
import 'demo_functionality.dart';

/// Demo Instructions Widget
/// 
/// Displays instructions for the current demo phase at the top of the demo screen.
/// Shows title and paragraph text based on the current game phase.
class DemoInstructionsWidget extends StatefulWidget {
  const DemoInstructionsWidget({Key? key}) : super(key: key);

  @override
  DemoInstructionsWidgetState createState() => DemoInstructionsWidgetState();
}

class DemoInstructionsWidgetState extends State<DemoInstructionsWidget> {
  static const bool LOGGING_SWITCH = false;
  static final Logger _logger = Logger();
  
  String? _previousPhase;
  Map<String, dynamic>? _cachedInstructions;

  @override
  void initState() {
    super.initState();
    // Listen to StateManager changes
    StateManager().addListener(_onStateChanged);
    // Initial update
    _updateInstructions();
  }

  @override
  void dispose() {
    StateManager().removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    // Only update if demoInstructionsPhase actually changed
    final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final currentPhase = dutchGameState['demoInstructionsPhase']?.toString() ?? '';
    
    if (currentPhase != _previousPhase) {
      _previousPhase = currentPhase;
      if (mounted) {
        setState(() {
          _updateInstructions();
        });
      }
    }
  }

  void _updateInstructions() {
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final demoInstructionsPhase = dutchGameState['demoInstructionsPhase']?.toString() ?? '';
        
        _logger.info('DemoInstructionsWidget: demoPhase=$demoInstructionsPhase, type=${demoInstructionsPhase.runtimeType}', isOn: LOGGING_SWITCH);
        
        // Get instructions for current demo phase
        final instructions = DemoFunctionality.instance.getInstructionsForPhase(demoInstructionsPhase);
    _cachedInstructions = instructions;
  }

  @override
  Widget build(BuildContext context) {
    final instructions = _cachedInstructions ?? {};
        final isVisible = instructions['isVisible'] as bool? ?? false;
        final title = instructions['title']?.toString() ?? '';
        final paragraph = instructions['paragraph']?.toString() ?? '';
        final hasButton = instructions['hasButton'] as bool? ?? false;
        
    _logger.info('DemoInstructionsWidget: demoPhase=$_previousPhase, isVisible=$isVisible, title="$title", paragraph="${paragraph.length > 50 ? paragraph.substring(0, 50) + '...' : paragraph}"', isOn: LOGGING_SWITCH);
        
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
              // "Let's go" button - shown for phases with hasButton: true
              if (hasButton) ...[
                SizedBox(height: AppPadding.defaultPadding.top),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {
                      _logger.info('DemoInstructionsWidget: "Let\'s go" button pressed for phase: $_previousPhase', isOn: LOGGING_SWITCH);
                      if (_previousPhase == 'initial') {
                        DemoFunctionality.instance.transitionToInitialPeek();
                      } else if (_previousPhase == 'wrong_same_rank_penalty') {
                        // Clear instructions and start opponent simulation
                        final stateUpdater = DutchGameStateUpdater.instance;
                        stateUpdater.updateStateSync({
                          'demoInstructionsPhase': '', // Clear instructions
                        });
                        // Start opponent simulation (end same rank window and simulate opponents)
                        DemoFunctionality.instance.endSameRankWindowAndSimulateOpponents().catchError((error, stackTrace) {
                          _logger.error('DemoInstructionsWidget: Error starting opponent simulation: $error', error: error, stackTrace: stackTrace, isOn: LOGGING_SWITCH);
                        });
                      }
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
  }
}

