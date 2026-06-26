import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../managers/state_manager.dart';
import '../../managers/navigation_manager.dart';
import '../../../utils/consts/theme_consts.dart';
import '../../../utils/widgets/coin_icon.dart';

/// State-aware coins display feature widget
/// 
/// This widget subscribes to the dutch_game state slice and displays
/// the user's coin count in the app bar. It automatically updates
/// when the coins value changes.
class StateAwareCoinsDisplayFeature extends StatelessWidget {
  const StateAwareCoinsDisplayFeature({Key? key}) : super(key: key);

  void _navigateToCoinPurchase(BuildContext context) {
    try {
      final navigationManager =
          Provider.of<NavigationManager>(context, listen: false);
      navigationManager.navigateTo('/coin-purchase');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Navigation failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        // Get dutch game state from StateManager
        final dutchGameState = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
        final userStats = dutchGameState['userStats'] as Map<String, dynamic>?;
        
        final goldColor = AppColors.matchPotGold;

        if (userStats == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Semantics(
              label: 'Buy coins',
              identifier: 'app_bar_coins_purchase',
              button: true,
              child: ActionChip(
                avatar: CoinIcon(size: 18, color: goldColor),
                label: Text(
                  'Buy coins',
                  style: AppTextStyles.label().copyWith(
                    fontWeight: FontWeight.bold,
                    color: goldColor,
                  ),
                ),
                tooltip: 'Buy coins',
                onPressed: () => _navigateToCoinPurchase(context),
                backgroundColor: goldColor.withOpacity(0.2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
        }

        final coins = userStats['coins'] as int? ?? 0;
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Semantics(
            label: 'Buy coins',
            identifier: 'app_bar_coins_purchase',
            button: true,
            child: ActionChip(
              avatar: CoinIcon(size: 18, color: goldColor),
              label: Text(
                coins.toString(),
                style: AppTextStyles.label().copyWith(
                  fontWeight: FontWeight.bold,
                  color: goldColor,
                ),
              ),
              tooltip: 'Buy coins',
              onPressed: () => _navigateToCoinPurchase(context),
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
