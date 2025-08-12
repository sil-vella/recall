import 'package:flutter/material.dart';
import '../../../../models/card.dart' as cm;
import '../../../../../utils/consts/theme_consts.dart';

class MyHandPanel extends StatelessWidget {
  final List<cm.Card> hand;
  final cm.Card? selected;
  final void Function(cm.Card card, int index) onSelect;

  const MyHandPanel({Key? key, required this.hand, required this.selected, required this.onSelect}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (hand.isEmpty) {
      return Text('Your hand is empty', style: AppTextStyles.bodyMedium);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < hand.length; i++) _HandCardTile(card: hand[i], index: i, isSelected: selected == hand[i], onTap: () => onSelect(hand[i], i)),
      ],
    );
  }
}

class _HandCardTile extends StatelessWidget {
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
        onTap: onTap,
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
              Text('${card.points} pts', style: AppTextStyles.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}


