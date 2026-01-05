import 'package:flutter/material.dart';
import '../../../../../core/managers/state_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';

const bool LOGGING_SWITCH = false;

/// Widget to display the match pot information
/// 
/// This widget subscribes to the centerBoard state slice and displays:
/// - Match pot amount (total coins collected from all players)
/// - Visual representation of the pot
/// 
/// Follows the established pattern of subscribing to state slices using ListenableBuilder
class MatchPotWidget extends StatelessWidget {
  const MatchPotWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        
        // Get centerBoard state slice
        final centerBoard = dutchGameState['centerBoard'] as Map<String, dynamic>? ?? {};
        
        // Get match pot from centerBoard slice
        final matchPot = centerBoard['matchPot'] as int? ?? 0;
        
        // Get additional game state for context
        final gamePhase = dutchGameState['gamePhase']?.toString() ?? 'waiting';
        final isGameActive = dutchGameState['isGameActive'] ?? false;
        
        return _buildMatchPotDisplay(
          matchPot: matchPot,
          gamePhase: gamePhase,
          isGameActive: isGameActive,
        );
      },
    );
  }

  /// Build the match pot display widget
  Widget _buildMatchPotDisplay({
    required int matchPot,
    required String gamePhase,
    required bool isGameActive,
  }) {
    // Only show pot if game is active (not in waiting phase)
    final shouldShowPot = isGameActive && gamePhase != 'waiting';
    
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Text(
            'Match Pot',
            style: AppTextStyles.headingSmall(),
          ),
          const SizedBox(height: 12),
          
          // Pot amount display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: shouldShowPot 
                  ? AppColors.primaryColor.withOpacity(0.1)
                  : AppColors.widgetContainerBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: shouldShowPot 
                    ? AppColors.primaryColor.withOpacity(0.3)
                    : AppColors.borderDefault.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Coin icon or symbol
                Icon(
                  Icons.monetization_on,
                  color: shouldShowPot 
                      ? AppColors.primaryColor
                      : AppColors.textSecondary,
                  size: 24,
                ),
                const SizedBox(height: 8),
                
                // Pot amount
                Text(
                  shouldShowPot ? matchPot.toString() : '—',
                  style: AppTextStyles.headingMedium().copyWith(
                    color: shouldShowPot 
                        ? AppColors.primaryColor
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                // Label
                Text(
                  'coins',
                  style: AppTextStyles.bodySmall().copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
