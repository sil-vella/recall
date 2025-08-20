import 'package:flutter/material.dart';
import '../../../models/card.dart' as cm;
import '../../../../../../utils/consts/theme_consts.dart';
import '../../../../managers/state_manager.dart';
import '../../../../../tools/logging/logger.dart';

class MyHandPanel extends StatelessWidget {
  static final Logger _log = Logger();
  final void Function(cm.Card card, int index) onSelect;

  const MyHandPanel({Key? key, required this.onSelect}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StateManager(),
      builder: (context, child) {
        final recall = StateManager().getModuleState<Map<String, dynamic>>('recall_game') ?? {};
        
        // Access the new myHand structure with widget-specific state slice
        final myHandState = recall['myHand'] as Map<String, dynamic>?;
        final cardsData = myHandState?['cards'] as List<dynamic>?;
        
        final hand = cardsData
            ?.map((m) => cm.Card.fromJson((m as Map).cast<String, dynamic>()))
            .toList() ?? [];
        final selectedCardJson = myHandState?['selectedCard'] as Map<String, dynamic>?;
        final selectedCard = selectedCardJson != null ? cm.Card.fromJson(selectedCardJson) : null;

        _log.info('🎮 MyHandPanel: Hand has ${hand.length} cards, selected: ${selectedCard?.displayName ?? 'none'}');

        if (hand.isEmpty) {
          return Text('Your hand is empty', style: AppTextStyles.bodyMedium);
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < hand.length; i++) 
              _HandCardTile(
                card: hand[i], 
                index: i, 
                isSelected: selectedCard == hand[i], 
                onTap: () => onSelect(hand[i], i)
              ),
          ],
        );
      },
    );
  }
}

class _HandCardTile extends StatelessWidget {
  static final Logger _log = Logger();
  final cm.Card card;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  const _HandCardTile({required this.card, required this.index, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'hand_card_$index',
      identifier: 'hand_card_$index',
      button: true,
      child: InkWell(
        onTap: () {
          _log.info('🎮 HandCardTile: Card ${card.displayName} at index $index tapped');
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? AppColors.accentColor : AppColors.lightGray.withOpacity(0.3), width: isSelected ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(card.displayName, style: AppTextStyles.bodyLarge),
              const SizedBox(height: 4),
              Text('${card.points} pts', style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}


