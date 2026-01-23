import 'package:flutter/material.dart';
import '../../managers/state_manager.dart';
import '../../../tools/logging/logger.dart';
import '../../../utils/consts/theme_consts.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false;

/// State-aware coins display feature widget
/// 
/// This widget subscribes to the dutch_game state slice and displays
/// the user's coin count in the app bar. It automatically updates
/// when the coins value changes.
class StateAwareCoinsDisplayFeature extends StatelessWidget {
  const StateAwareCoinsDisplayFeature({Key? key}) : super(key: key);
  
  static final Logger _logger = Logger();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get dutch game state from StateManager
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final userStats = dutchGameState['userStats'] as Map<String, dynamic>?;
        
        if (LOGGING_SWITCH) {
          _logger.info('🔍 Coins Display: Building widget - dutchGameState keys: ${dutchGameState.keys.toList()}');
        }
        if (LOGGING_SWITCH) {
          _logger.info('🔍 Coins Display: userStats=$userStats');
        }
        
        // Get coins from userStats, default to 0 if not available
        final coins = userStats?['coins'] as int? ?? 0;
        
        if (LOGGING_SWITCH) {
          _logger.info('🔍 Coins Display: coins=$coins');
        }
        
        // Return empty widget if userStats is not available (user not logged in or stats not loaded)
        if (userStats == null) {
          if (LOGGING_SWITCH) {
            _logger.warning('⚠️ Coins Display: userStats is null - hiding widget');
          }
          return const SizedBox.shrink();
        }
        
        if (LOGGING_SWITCH) {
          _logger.info('✅ Coins Display: Rendering coins chip with value: $coins');
        }
        
        // Return coins display chip with appropriate styling for app bar
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Chip(
            avatar: Icon(
              Icons.monetization_on,
              size: 18,
              color: AppColors.accentColor2,
            ),
            label: Text(
              coins.toString(),
              style: AppTextStyles.label().copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.accentColor2.withOpacity(0.2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        );
      },
    );
  }
}
