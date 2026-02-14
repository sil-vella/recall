import 'package:flutter/material.dart';
import '../../../../core/00_base/screen_base.dart';
import '../../../../utils/consts/theme_consts.dart';

class GameRulesScreen extends BaseScreen {
  const GameRulesScreen({Key? key}) : super(key: key);

  @override
  BaseScreenState<GameRulesScreen> createState() => _GameRulesScreenState();

  @override
  String computeTitle(BuildContext context) => 'Game Rules';
}

class _GameRulesScreenState extends BaseScreenState<GameRulesScreen> {
  @override
  Widget buildContent(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: AppPadding.defaultPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main Goal and Gameplay Section
                _buildMainGoalSection(context),
                
                const SizedBox(height: 24),
                
                // Card Points Section
                _buildCardPointsSection(context),
                
                const SizedBox(height: 24),
                
                // Special Powers Section
                _buildSpecialPowersSection(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainGoalSection(BuildContext context) {
    const content = '''**Main Goal:**
Clear all cards from your hand or end the game with the least points possible.

**Gameplay:**
• Tap the draw pile to draw a card
• Select a card from your hand to play (**Clear and collect mode** - excluding collection cards)
• Play cards with same rank as last played card (out of turn)
• Queens let you peek at face down cards from any player's hand, including your own.
• Jacks let you swap any 2 cards from any player's hand, including your own (**Clear and collect mode** - Including collection cards)

• **Clear and collect mode** - Collect cards from discard pile if they match your collection rank. Collecting all 4 cards of your rank wins the game.


**Final Round:**
If you think you have the least points during your turn, you can call **final round** after you play your card. This will trigger the final round - this was your final round so you won't play again.

**Winning:**
• Player with **no cards** wins
• Player with **least points** wins
• If same points, player with **least cards** wins
• If same points and same cards, player who **called final round** wins

• **Clear and collect mode** - The player that collects all 4 cards of their rank wins the game.''';

    return Container(
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.casinoBorderColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎯 How to Play Dutch',
            style: AppTextStyles.headingMedium().copyWith(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildMarkdownText(content),
        ],
      ),
    );
  }

  Widget _buildCardPointsSection(BuildContext context) {
    return Container(
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.casinoBorderColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '💯 Card Points System',
            style: AppTextStyles.headingMedium().copyWith(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildCardPointsList(),
        ],
      ),
    );
  }

  Widget _buildCardPointsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCardPointItem('Numbered Cards (2-10)', 'Points equal to card number'),
        const SizedBox(height: 8),
        _buildCardPointItem('Ace Cards', '1 point'),
        const SizedBox(height: 8),
        _buildCardPointItem('Queens & Jacks', '10 points'),
        const SizedBox(height: 8),
        _buildCardPointItem('Kings (All)', '10 points'),
        const SizedBox(height: 8),
        _buildCardPointItem('Joker Cards', '0 points'),
      ],
    );
  }

  Widget _buildCardPointItem(String cardType, String points) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• ',
          style: AppTextStyles.bodyMedium(
            color: AppColors.textPrimary,
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTextStyles.bodyMedium(
                color: AppColors.textPrimary,
              ),
              children: [
                TextSpan(
                  text: cardType,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ': '),
                TextSpan(
                  text: points,
                  style: TextStyle(
                    color: AppColors.accentColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialPowersSection(BuildContext context) {
    const queenContent = '''👑 **Queen Power Activated**

When you play a Queen, you have a chance to peek at any **face down card** from any player's hand, including your own.

Tap a card from any hand to reveal it.''';

    const jackContent = '''🃏 **Jack Power Activated**

You can swap any **2 cards** from any hand, including your own.

** For Dutch: Clear and Collect mode **
Jack swap also enables you to swap out **collection cards** from any hand. Swapped out collection cards are now regular playable cards.

**Important:** If you swap out the last collection card, that player no longer have a collection.''';

    return Container(
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.casinoBorderColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🃏 Special Powers',
            style: AppTextStyles.headingMedium().copyWith(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Queen Power - Peek at a Card',
            style: AppTextStyles.bodyLarge(
              color: AppColors.accentColor,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildMarkdownText(queenContent),
          const SizedBox(height: 16),
          Text(
            'Jack Power - Swap Cards',
            style: AppTextStyles.bodyLarge(
              color: AppColors.accentColor,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildMarkdownText(jackContent),
        ],
      ),
    );
  }

  Widget _buildMarkdownText(String text) {
    // Simple markdown parsing for bold (**text**) and bullet points
    final lines = text.split('\n');
    final List<Widget> widgets = [];
    
    for (final line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      
      // Check for bold text (**text**)
      final boldRegex = RegExp(r'\*\*(.+?)\*\*');
      final matches = boldRegex.allMatches(line);
      
      if (matches.isEmpty) {
        // No bold text, just regular text
        widgets.add(
          Text(
            line,
            style: AppTextStyles.bodyMedium(
              color: AppColors.textPrimary,
            ).copyWith(height: 1.5),
          ),
        );
      } else {
        // Has bold text
        final List<TextSpan> spans = [];
        int lastIndex = 0;
        
        for (final match in matches) {
          // Add text before the match
          if (match.start > lastIndex) {
            spans.add(TextSpan(
              text: line.substring(lastIndex, match.start),
              style: AppTextStyles.bodyMedium(
                color: AppColors.textPrimary,
              ),
            ));
          }
          
          // Add bold text
          spans.add(TextSpan(
            text: match.group(1),
            style: AppTextStyles.bodyMedium(
              color: AppColors.textPrimary,
            ).copyWith(fontWeight: FontWeight.bold),
          ));
          
          lastIndex = match.end;
        }
        
        // Add remaining text
        if (lastIndex < line.length) {
          spans.add(TextSpan(
            text: line.substring(lastIndex),
            style: AppTextStyles.bodyMedium(
              color: AppColors.textPrimary,
            ),
          ));
        }
        
        widgets.add(
          RichText(
            text: TextSpan(children: spans),
          ),
        );
      }
      
      widgets.add(const SizedBox(height: 4));
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}
