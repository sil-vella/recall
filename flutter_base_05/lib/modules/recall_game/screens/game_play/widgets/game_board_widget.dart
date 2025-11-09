import 'package:flutter/material.dart';
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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

