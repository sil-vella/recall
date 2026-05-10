import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../managers/state_manager.dart';
import '../../managers/navigation_manager.dart';
import '../../../utils/consts/theme_consts.dart';

/// State-aware coins display feature widget
/// 
/// This widget subscribes to the dutch_game state slice and displays
/// the user's coin count in the app bar. It automatically updates
/// when the coins value changes.
class StateAwareCoinsDisplayFeature extends StatelessWidget {
  const StateAwareCoinsDisplayFeature({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get dutch game state from StateManager
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final userStats = dutchGameState['userStats'] as Map<String, dynamic>?;
        
        // Get coins from userStats, default to 0 if not available
        final coins = userStats?['coins'] as int? ?? 0;
        
        // Return empty widget if userStats is not available (user not logged in or stats not loaded)
        if (userStats == null) {
          return const SizedBox.shrink();
        }
        
        // Tappable coins display — same navigation pattern as notifications / profile app bar features.
        final goldColor = AppColors.matchPotGold;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Semantics(
            label: 'Buy coins',
            identifier: 'app_bar_coins_purchase',
            button: true,
            child: ActionChip(
              avatar: Icon(
                Icons.monetization_on,
                size: 18,
                color: goldColor,
              ),
              label: Text(
                coins.toString(),
                style: AppTextStyles.label().copyWith(
                  fontWeight: FontWeight.bold,
                  color: goldColor,
                ),
              ),
              tooltip: 'Buy coins',
              onPressed: () {
                try {
                  final navigationManager =
                      Provider.of<NavigationManager>(context, listen: false);
                  navigationManager.navigateTo('/coin-purchase');
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Navigation failed: $e')),
                  );
                }
              },
              backgroundColor: goldColor.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      },
    );
  }
}
