import 'package:flutter/material.dart';
import '../models/card_model.dart';
import 'card_widget.dart';
import 'card_back_widget.dart';
import '../../../../utils/consts/theme_consts.dart';

/// Comprehensive demo widget showing the entire card system
/// 
/// This widget demonstrates:
/// - Regular cards with different sizes and states
/// - Card backs with different configurations
/// - Interactive cards (selectable, tappable)
/// - Special power cards
/// - Face-down cards
class CardSystemDemoWidget extends StatelessWidget {
  const CardSystemDemoWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card System Demo'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: AppColors.white,
      ),
      body: SingleChildScrollView(
        padding: AppPadding.defaultPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Regular Cards (CardWidget)'),
            _buildRegularCardsDemo(),
            
            const SizedBox(height: 32),
            _buildSectionTitle('Card Backs (CardBackWidget)'),
            _buildCardBacksDemo(),
            
            const SizedBox(height: 32),
            _buildSectionTitle('Interactive Cards'),
            _buildInteractiveCardsDemo(),
            
            const SizedBox(height: 32),
            _buildSectionTitle('Special Power Cards'),
            _buildSpecialPowerCardsDemo(),
            
            const SizedBox(height: 32),
            _buildSectionTitle('Face-Down Cards'),
            _buildFaceDownCardsDemo(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTextStyles.headingMedium(),
    );
  }

  Widget _buildRegularCardsDemo() {
    final demoCard = CardModel(
      cardId: 'demo_1',
      rank: 'ace',
      suit: 'spades',
      points: 1,
    );

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildCardWithLabel('Small', CardWidget(card: demoCard, size: CardSize.small)),
        _buildCardWithLabel('Medium', CardWidget(card: demoCard, size: CardSize.medium)),
        _buildCardWithLabel('Large', CardWidget(card: demoCard, size: CardSize.large)),
        _buildCardWithLabel('Extra Large', CardWidget(card: demoCard, size: CardSize.extraLarge)),
      ],
    );
  }

  Widget _buildCardBacksDemo() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildCardWithLabel('Default Back', CardBackWidget()),
        _buildCardWithLabel('Custom Symbol', CardBackWidget(customSymbol: '♠')),
        _buildCardWithLabel('Blue Theme', CardBackWidget(
          backgroundColor: Colors.blue.shade100,
          borderColor: Colors.blue.shade300,
        )),
        _buildCardWithLabel('Green Theme', CardBackWidget(
          backgroundColor: Colors.green.shade100,
          borderColor: Colors.green.shade300,
        )),
        _buildCardWithLabel('Small Size', CardBackWidget(size: CardSize.small)),
        _buildCardWithLabel('Large Size', CardBackWidget(size: CardSize.large)),
      ],
    );
  }

  Widget _buildInteractiveCardsDemo() {
    final card = CardModel(
      cardId: 'demo_2',
      rank: 'queen',
      suit: 'hearts',
      points: 10,
    );

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildCardWithLabel('Normal', CardWidget(card: card, size: CardSize.medium)),
        _buildCardWithLabel('Selectable', CardWidget(
          card: card,
          size: CardSize.medium,
          isSelectable: true,
          isSelected: false,
        )),
        _buildCardWithLabel('Selected', CardWidget(
          card: card,
          size: CardSize.medium,
          isSelectable: true,
          isSelected: true,
        )),
        _buildCardWithLabel('Interactive Back', CardBackWidget(
          size: CardSize.medium,
          isSelectable: true,
          isSelected: true,
          customSymbol: '?',
        )),
      ],
    );
  }

  Widget _buildSpecialPowerCardsDemo() {
    final specialCards = [
      CardModel(
        cardId: 'demo_3',
        rank: 'queen',
        suit: 'diamonds',
        points: 10,
        specialPower: 'queen',
      ),
      CardModel(
        cardId: 'demo_4',
        rank: 'jack',
        suit: 'clubs',
        points: 10,
        specialPower: 'jack',
      ),
      CardModel(
        cardId: 'demo_5',
        rank: '2',
        suit: 'hearts',
        points: 2,
        specialPower: 'added_power',
      ),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: specialCards.map((card) => _buildCardWithLabel(
        '${card.displayText}\n(${card.specialPower})',
        CardWidget(
          card: card,
          size: CardSize.medium,
          showSpecialPower: true,
          showPoints: true,
        ),
      )).toList(),
    );
  }

  Widget _buildFaceDownCardsDemo() {
    final card = CardModel(
      cardId: 'demo_6',
      rank: 'king',
      suit: 'spades',
      points: 10,
    );

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildCardWithLabel('Face Up', CardWidget(card: card, size: CardSize.medium)),
        _buildCardWithLabel('Face Down', CardWidget(
          card: card.copyWith(isFaceDown: true),
          size: CardSize.medium,
        )),
        _buildCardWithLabel('Show Back', CardWidget(
          card: card,
          size: CardSize.medium,
          showBack: true,
        )),
        _buildCardWithLabel('Card Back Widget', CardBackWidget(
          size: CardSize.medium,
          customSymbol: '?',
        )),
      ],
    );
  }

  Widget _buildCardWithLabel(String label, Widget card) {
    return Column(
      children: [
        card,
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.darkGray,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
