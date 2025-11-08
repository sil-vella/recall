import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/card_display_config.dart';
import '../utils/card_dimensions.dart';
import 'card_widget.dart';
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
            _buildSectionTitle('Card Backs (CardWidget with showBack=true)'),
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
        _buildCardWithLabel('Small', CardWidget(
          card: demoCard,
          dimensions: CardDimensions.getDimensions(CardSize.small),
          config: CardDisplayConfig.forMyHand(),
        )),
        _buildCardWithLabel('Medium', CardWidget(
          card: demoCard,
          dimensions: CardDimensions.getDimensions(CardSize.medium),
          config: CardDisplayConfig.forMyHand(),
        )),
        _buildCardWithLabel('Large', CardWidget(
          card: demoCard,
          dimensions: CardDimensions.getDimensions(CardSize.large),
          config: CardDisplayConfig.forMyHand(),
        )),
        _buildCardWithLabel('Extra Large', CardWidget(
          card: demoCard,
          dimensions: CardDimensions.getDimensions(CardSize.extraLarge),
          config: CardDisplayConfig.forMyHand(),
        )),
      ],
    );
  }

  Widget _buildCardBacksDemo() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildCardWithLabel('Default Back', CardWidget(
          card: CardModel(cardId: 'demo_back', rank: '?', suit: '?', points: 0),
          dimensions: CardDimensions.getUnifiedDimensions(),
          config: CardDisplayConfig.forDrawPile(),
          showBack: true,
        )),
        _buildCardWithLabel('Custom Symbol', CardWidget(
          card: CardModel(cardId: 'demo_back_spade', rank: '?', suit: '?', points: 0),
          dimensions: CardDimensions.getUnifiedDimensions(),
          config: CardDisplayConfig.forDrawPile(),
          showBack: true,
        )),
        _buildCardWithLabel('Blue Theme', CardWidget(
          card: CardModel(cardId: 'demo_back_blue', rank: '?', suit: '?', points: 0),
          dimensions: CardDimensions.getUnifiedDimensions(),
          config: CardDisplayConfig.forDrawPile(),
          showBack: true,
        )),
        _buildCardWithLabel('Green Theme', CardWidget(
          card: CardModel(cardId: 'demo_back_green', rank: '?', suit: '?', points: 0),
          dimensions: CardDimensions.getUnifiedDimensions(),
          config: CardDisplayConfig.forDrawPile(),
          showBack: true,
        )),
        _buildCardWithLabel('Small Size', CardWidget(
          card: CardModel(cardId: 'demo_back_small', rank: '?', suit: '?', points: 0),
          dimensions: CardDimensions.getDimensions(CardSize.small),
          config: CardDisplayConfig.forDrawPile(),
          showBack: true,
        )),
        _buildCardWithLabel('Large Size', CardWidget(
          card: CardModel(cardId: 'demo_back_large', rank: '?', suit: '?', points: 0),
          dimensions: CardDimensions.getDimensions(CardSize.large),
          config: CardDisplayConfig.forDrawPile(),
          showBack: true,
        )),
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
    final dimensions = CardDimensions.getUnifiedDimensions();

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildCardWithLabel('Normal', CardWidget(
          card: card,
          dimensions: dimensions,
          config: CardDisplayConfig.forMyHand(),
        )),
        _buildCardWithLabel('Selectable', CardWidget(
          card: card,
          dimensions: dimensions,
          config: CardDisplayConfig.forMyHand(),
          isSelected: false,
        )),
        _buildCardWithLabel('Selected', CardWidget(
          card: card,
          dimensions: dimensions,
          config: CardDisplayConfig.forMyHand(),
          isSelected: true,
        )),
        _buildCardWithLabel('Interactive Back', CardWidget(
          card: CardModel(cardId: 'demo_back_interactive', rank: '?', suit: '?', points: 0),
          dimensions: dimensions,
          config: CardDisplayConfig.forMyHand(),
          showBack: true,
          isSelected: true,
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

    final dimensions = CardDimensions.getUnifiedDimensions();
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: specialCards.map((card) => _buildCardWithLabel(
        '${card.displayText}\n(${card.specialPower})',
        CardWidget(
          card: card,
          dimensions: dimensions,
          config: CardDisplayConfig(
            showSpecialPower: true,
            showPoints: true,
          ),
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
    final dimensions = CardDimensions.getUnifiedDimensions();

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildCardWithLabel('Face Up', CardWidget(
          card: card,
          dimensions: dimensions,
          config: CardDisplayConfig.forMyHand(),
        )),
        _buildCardWithLabel('Face Down', CardWidget(
          card: card.copyWith(isFaceDown: true),
          dimensions: dimensions,
          config: CardDisplayConfig.forMyHand(),
        )),
        _buildCardWithLabel('Show Back', CardWidget(
          card: card,
          dimensions: dimensions,
          config: CardDisplayConfig.forMyHand(),
          showBack: true,
        )),
        _buildCardWithLabel('Card Back Widget', CardWidget(
          card: CardModel(cardId: 'demo_back_widget', rank: '?', suit: '?', points: 0),
          dimensions: dimensions,
          config: CardDisplayConfig.forMyHand(),
          showBack: true,
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
