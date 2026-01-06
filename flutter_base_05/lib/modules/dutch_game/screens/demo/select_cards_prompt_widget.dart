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
        // Get demo instructions phase and myCardsToPeek from state
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final demoInstructionsPhase = dutchGameState['demoInstructionsPhase']?.toString() ?? '';
        final myCardsToPeek = dutchGameState['myCardsToPeek'] as List<dynamic>? ?? [];
        final selectedCount = myCardsToPeek.length;
        
        // Only show during initial peek phase when 0 or 1 cards selected
        final shouldShow = demoInstructionsPhase == 'initial_peek' && selectedCount < 2;
        
        _logger.info('SelectCardsPromptWidget: demoPhase=$demoInstructionsPhase, selectedCount=$selectedCount, shouldShow=$shouldShow', isOn: LOGGING_SWITCH);
        
        if (!shouldShow) {
          return const SizedBox.shrink();
        }
        
        // Get actual myhand height from state (updated by unified widget via GlobalKey)
        final myHandHeight = dutchGameState['myHandHeight'] as double?;
        
        // Calculate margin: use actual height if available, otherwise fallback to estimate
        final marginBottom = myHandHeight != null 
            ? myHandHeight
            : MediaQuery.of(context).size.height * 0.18; // Fallback estimate
        
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
                  'Select two cards',
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

