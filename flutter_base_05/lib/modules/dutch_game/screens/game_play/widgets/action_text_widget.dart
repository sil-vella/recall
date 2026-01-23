import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Action Text Widget
/// 
/// Displays contextual action prompts (e.g., "Tap a card to peek", "Draw a card")
/// as an overlay at the bottom of the screen.
/// Only visible when showInstructions is true and actionText is set in state.
class ActionTextWidget extends StatelessWidget {
  static const bool LOGGING_SWITCH = false;
  static final Logger _logger = Logger();
  
  const ActionTextWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        
        // Get action text state
        final actionTextData = dutchGameState['actionText'] as Map<String, dynamic>? ?? {};
        final isVisible = actionTextData['isVisible'] as bool? ?? false;
        final text = actionTextData['text']?.toString() ?? '';
        
        // Check if instructions are enabled (only show when instructions are enabled)
        final games = dutchGameState['games'] as Map<String, dynamic>? ?? {};
        final currentGameId = dutchGameState['currentGameId']?.toString() ?? '';
        final game = currentGameId.isNotEmpty ? games[currentGameId] as Map<String, dynamic>? : null;
        final gameData = game?['gameData'] as Map<String, dynamic>?;
        final gameState = gameData?['game_state'] as Map<String, dynamic>?;
        final showInstructions = gameState?['showInstructions'] as bool? ?? false;
        
        if (LOGGING_SWITCH) {
          _logger.info('ActionTextWidget: isVisible=$isVisible, text=$text, showInstructions=$showInstructions');
        }
        
        // Don't render if not visible, text is empty, or instructions are disabled
        if (!isVisible || text.isEmpty || !showInstructions) {
          return const SizedBox.shrink();
        }
        
        return Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: AppPadding.defaultPadding,
            decoration: BoxDecoration(
              color: AppColors.scaffoldBackgroundColor.withOpacity(0.95),
              borderRadius: BorderRadius.only(
                topLeft: AppBorderRadius.mediumRadius.topLeft,
                topRight: AppBorderRadius.mediumRadius.topRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                text,
                style: AppTextStyles.headingMedium().copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}

