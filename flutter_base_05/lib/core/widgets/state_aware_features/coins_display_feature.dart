import 'package:flutter/material.dart';
import '../../managers/state_manager.dart';
import '../../../tools/logging/logger.dart';

// Logging switch for this file
const bool LOGGING_SWITCH = false;

/// State-aware coins display feature widget
/// 
/// This widget subscribes to the cleco_game state slice and displays
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
        // Get cleco game state from StateManager
        final clecoGameState = StateManager().getModuleState<Map<String, dynamic>>('cleco_game') ?? {};
        final userStats = clecoGameState['userStats'] as Map<String, dynamic>?;
        
        _logger.info('🔍 Coins Display: Building widget - clecoGameState keys: ${clecoGameState.keys.toList()}', isOn: LOGGING_SWITCH);
        _logger.info('🔍 Coins Display: userStats=$userStats', isOn: LOGGING_SWITCH);
        
        // Get coins from userStats, default to 0 if not available
        final coins = userStats?['coins'] as int? ?? 0;
        
        _logger.info('🔍 Coins Display: coins=$coins', isOn: LOGGING_SWITCH);
        
        // Return empty widget if userStats is not available (user not logged in or stats not loaded)
        if (userStats == null) {
          _logger.warning('⚠️ Coins Display: userStats is null - hiding widget', isOn: LOGGING_SWITCH);
          return const SizedBox.shrink();
        }
        
        _logger.info('✅ Coins Display: Rendering coins chip with value: $coins', isOn: LOGGING_SWITCH);
        
        // Return coins display chip with appropriate styling for app bar
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Chip(
            avatar: const Icon(
              Icons.monetization_on,
              size: 18,
              color: Colors.amber,
            ),
            label: Text(
              coins.toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            backgroundColor: Colors.amber.withOpacity(0.2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        );
      },
    );
  }
}
