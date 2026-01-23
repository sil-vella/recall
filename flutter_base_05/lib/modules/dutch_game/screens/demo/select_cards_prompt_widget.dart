import 'package:flutter/material.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';

/// Select Cards Prompt Widget
/// 
/// Displays a flashing "Select two cards" text above the myhand section
/// Only visible during initial peek phase when cards haven't been selected yet
class SelectCardsPromptWidget extends StatefulWidget {
  const SelectCardsPromptWidget({Key? key}) : super(key: key);

  @override
  State<SelectCardsPromptWidget> createState() => _SelectCardsPromptWidgetState();
}

class _SelectCardsPromptWidgetState extends State<SelectCardsPromptWidget> with SingleTickerProviderStateMixin {
  static const bool LOGGING_SWITCH = false;
  static final Logger _logger = Logger();
  
  late AnimationController _animationController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    
    // Create animation controller for flashing glow effect
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    // Create glow animation (0.3 to 1.0 opacity)
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get demo instructions phase, myCardsToPeek, and myDrawnCard from state
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final demoInstructionsPhase = dutchGameState['demoInstructionsPhase']?.toString() ?? '';
        final myCardsToPeek = dutchGameState['myCardsToPeek'] as List<dynamic>? ?? [];
        final selectedCount = myCardsToPeek.length;
        final myDrawnCard = dutchGameState['myDrawnCard'] as Map<String, dynamic>?;
        final hasDrawnCard = myDrawnCard != null;
        
        // Determine text and visibility based on phase
        String promptText = '';
        bool shouldShow = false;
        
        if (demoInstructionsPhase == 'initial_peek' && selectedCount < 2) {
          // Initial peek phase - show "Select two cards"
          promptText = 'Select two cards';
          shouldShow = true;
        } else if (demoInstructionsPhase == 'drawing' && !hasDrawnCard) {
          // Drawing phase - show "Tap the draw pile" until card is drawn
          promptText = 'Tap the draw pile';
          shouldShow = true;
        } else if (demoInstructionsPhase == 'playing') {
          // Playing phase - show "Select any card to play"
          promptText = 'Select any card to play';
          shouldShow = true;
        } else if (demoInstructionsPhase == 'same_rank') {
          // Same rank phase - show "Tap any card from your hand"
          promptText = 'Tap any card from your hand';
          shouldShow = true;
        } else if (demoInstructionsPhase == 'special_plays') {
          // Special plays phase - show "Tap any card from your hand"
          promptText = 'Tap any card from your hand';
          shouldShow = true;
        } else if (demoInstructionsPhase == 'queen_peek') {
          // Queen peek phase - show "Tap a card to peek"
          promptText = 'Tap a card to peek';
          shouldShow = true;
        } else if (demoInstructionsPhase == 'jack_swap') {
          // Jack swap phase - show "Tap two cards to swap"
          promptText = 'Tap two cards to swap';
          shouldShow = true;
        } else if (demoInstructionsPhase == 'call_dutch') {
          // Call Dutch phase - show "Tap 'Call Dutch' then play a card"
          promptText = 'Tap \'Call Dutch\' then play a card';
          shouldShow = true;
        }
        
        if (LOGGING_SWITCH) {
          _logger.info('SelectCardsPromptWidget: demoPhase=$demoInstructionsPhase, selectedCount=$selectedCount, hasDrawnCard=$hasDrawnCard, shouldShow=$shouldShow');
        }
        
        if (!shouldShow || promptText.isEmpty) {
          return const SizedBox.shrink();
        }
        
        // Get heights from state (updated by unified widget via GlobalKey)
        final myHandHeight = dutchGameState['myHandHeight'] as double?;
        final gameBoardHeight = dutchGameState['gameBoardHeight'] as double?;
        
        // Calculate position based on phase:
        // - Initial peek: above myhand (marginBottom = myHandHeight)
        // - Drawing: above game board (marginBottom = myHandHeight + gameBoardHeight + spacing)
        // - Playing: above myhand (marginBottom = myHandHeight)
        // - Same rank: above myhand (marginBottom = myHandHeight)
        // - Call Dutch: above myhand (marginBottom = myHandHeight)
        double marginBottom;
        if (demoInstructionsPhase == 'drawing') {
          // Drawing phase - position above game board
          // Game board is above myhand, so we need: myHandHeight + gameBoardHeight + spacing
          const spacing = 8.0; // Small spacing between game board and prompt
          if (myHandHeight != null && gameBoardHeight != null) {
            marginBottom = myHandHeight + gameBoardHeight + spacing;
          } else {
            // Fallback estimate
            marginBottom = MediaQuery.of(context).size.height * 0.5;
          }
        } else {
          // Initial peek, playing, and same rank phases - position above myhand
          marginBottom = myHandHeight != null 
              ? myHandHeight
              : MediaQuery.of(context).size.height * 0.18; // Fallback estimate for myhand
        }
        
        return AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: EdgeInsets.only(bottom: marginBottom),
              decoration: BoxDecoration(
                color: AppColors.scaffoldBackgroundColor.withValues(alpha: 0.95), // Same as instructions widget
                borderRadius: BorderRadius.only(
                  topLeft: AppBorderRadius.mediumRadius.topLeft,
                  topRight: AppBorderRadius.mediumRadius.topRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, -4), // Shadow above (since it's at bottom)
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  promptText,
                  style: AppTextStyles.headingMedium().copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      // Multiple shadow layers for glow effect
                      Shadow(
                        color: AppColors.accentColor.withOpacity(_glowAnimation.value),
                        blurRadius: 20,
                        offset: const Offset(0, 0),
                      ),
                      Shadow(
                        color: AppColors.accentColor.withOpacity(_glowAnimation.value * 0.7),
                        blurRadius: 30,
                        offset: const Offset(0, 0),
                      ),
                      Shadow(
                        color: AppColors.accentColor.withOpacity(_glowAnimation.value * 0.5),
                        blurRadius: 40,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

