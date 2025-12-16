import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';
import 'draw_pile_widget.dart';
import 'discard_pile_widget.dart';

/// Widget to display the game board section
/// 
/// This widget displays:
/// - Game Board title
/// - Draw Pile Widget
/// - Discard Pile Widget
/// 
/// The draw and discard pile widgets handle their own state subscriptions
class GameBoardWidget extends StatelessWidget {
  const GameBoardWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: AppPadding.smallPadding.left),
      decoration: BoxDecoration(
        color: AppColors.widgetContainerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Draw Pile Widget
            const DrawPileWidget(),
            
            const SizedBox(width: 16),
            
            // Discard Pile Widget
            const DiscardPileWidget(),
          ],
        ),
      ),
    );
  }
}

