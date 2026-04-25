import 'package:flutter/material.dart';

import '../../../../../core/managers/navigation_manager.dart';
import '../../../utils/modal_template_widget.dart';
import '../../../../../utils/consts/theme_consts.dart';

/// Full Dutch game rules in a scrollable body (same copy as the former [GameRulesScreen]).
class GameRulesModalBody extends StatelessWidget {
  const GameRulesModalBody({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMainGoalSection(),
        SizedBox(height: AppPadding.defaultPadding.top),
        _buildCardPointsSection(),
        SizedBox(height: AppPadding.defaultPadding.top),
        _buildSpecialPowersSection(),
      ],
    );
  }

  Widget _buildMainGoalSection() {
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
      width: double.infinity,
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.cardVariant,
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
          SizedBox(height: AppPadding.smallPadding.top),
          _buildMarkdownText(content),
        ],
      ),
    );
  }

  Widget _buildCardPointsSection() {
    return Container(
      width: double.infinity,
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.cardVariant,
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
          SizedBox(height: AppPadding.smallPadding.top),
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
        SizedBox(height: AppPadding.smallPadding.top / 2),
        _buildCardPointItem('Ace Cards', '1 point'),
        SizedBox(height: AppPadding.smallPadding.top / 2),
        _buildCardPointItem('Queens & Jacks', '10 points'),
        SizedBox(height: AppPadding.smallPadding.top / 2),
        _buildCardPointItem('Kings (All)', '10 points'),
        SizedBox(height: AppPadding.smallPadding.top / 2),
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
            color: AppColors.textOnCard,
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTextStyles.bodyMedium(
                color: AppColors.textOnCard,
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

  Widget _buildSpecialPowersSection() {
    const queenContent = '''👑 **Queen Power Activated**

When you play a Queen, you have a chance to peek at any **face down card** from any player's hand, including your own.

Tap a card from any hand to reveal it.''';

    const jackContent = '''🃏 **Jack Power Activated**

You can swap any **2 cards** from any hand, including your own.

** For Dutch: Clear and Collect mode **
Jack swap also enables you to swap out **collection cards** from any hand. Swapped out collection cards are now regular playable cards.

**Important:** If you swap out the last collection card, that player no longer have a collection.''';

    return Container(
      width: double.infinity,
      padding: AppPadding.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.cardVariant,
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
          SizedBox(height: AppPadding.smallPadding.top),
          Text(
            'Queen Power - Peek at a Card',
            style: AppTextStyles.bodyLarge(
              color: AppColors.accentColor,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: AppPadding.smallPadding.top / 2),
          _buildMarkdownText(queenContent),
          SizedBox(height: AppPadding.defaultPadding.top),
          Text(
            'Jack Power - Swap Cards',
            style: AppTextStyles.bodyLarge(
              color: AppColors.accentColor,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: AppPadding.smallPadding.top / 2),
          _buildMarkdownText(jackContent),
        ],
      ),
    );
  }

  Widget _buildMarkdownText(String text) {
    final lines = text.split('\n');
    final List<Widget> widgets = [];

    for (final line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(SizedBox(height: AppPadding.smallPadding.top / 2));
        continue;
      }

      final boldRegex = RegExp(r'\*\*(.+?)\*\*');
      final matches = boldRegex.allMatches(line);

      if (matches.isEmpty) {
        widgets.add(
          Text(
            line,
            style: AppTextStyles.bodyMedium(
              color: AppColors.textOnCard,
            ).copyWith(height: 1.5),
          ),
        );
      } else {
        final List<TextSpan> spans = [];
        int lastIndex = 0;

        for (final match in matches) {
          if (match.start > lastIndex) {
            spans.add(TextSpan(
              text: line.substring(lastIndex, match.start),
              style: AppTextStyles.bodyMedium(
                color: AppColors.textOnCard,
              ),
            ));
          }

          spans.add(TextSpan(
            text: match.group(1),
            style: AppTextStyles.bodyMedium(
              color: AppColors.textOnCard,
            ).copyWith(fontWeight: FontWeight.bold),
          ));

          lastIndex = match.end;
        }

        if (lastIndex < line.length) {
          spans.add(TextSpan(
            text: line.substring(lastIndex),
            style: AppTextStyles.bodyMedium(
              color: AppColors.textOnCard,
            ),
          ));
        }

        widgets.add(
          RichText(
            text: TextSpan(
              style: AppTextStyles.bodyMedium(color: AppColors.textOnCard),
              children: spans,
            ),
          ),
        );
      }

      widgets.add(SizedBox(height: AppPadding.smallPadding.top / 4));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

/// Presents game rules in the same style as learn-how [InstructionsWidget] (sized card + soft dim).
class DutchGameRulesDialog {
  DutchGameRulesDialog._();

  static const String _placeholderContent = ' ';

  /// Shows rules using root navigator when available (matches instructions modal).
  static Future<void> show(BuildContext context) {
    final rootCtx = NavigationManager().navigatorKey.currentContext;
    final dialogContext = rootCtx ?? context;

    return showDialog<void>(
      context: dialogContext,
      barrierDismissible: true,
      useRootNavigator: true,
      barrierColor:
          AppColors.black.withOpacity(AppOpacity.instructionsModalBarrier),
      builder: (BuildContext builderContext) {
        final sz = MediaQuery.sizeOf(builderContext);
        return ModalTemplateWidget(
          title: 'Game Rules',
          content: _placeholderContent,
          icon: Icons.help_outline,
          showCloseButton: false,
          showFooter: false,
          backgroundColor: AppColors.card,
          textColor: AppColors.textOnCard,
          headerColor: AppColors.primaryColor,
          headerForegroundColor: AppColors.white,
          fullScreen: false,
          transparentRouteBackground: true,
          maxWidth: sz.width * AppSizes.instructionsModalMaxWidthPercent,
          maxHeight: sz.height * AppSizes.instructionsModalMaxHeightPercent,
          customContent: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    top: AppPadding.defaultPadding.top,
                    left: AppPadding.defaultPadding.left,
                    right: AppPadding.defaultPadding.right,
                  ),
                  child: const GameRulesModalBody(),
                ),
              ),
              Container(
                padding: AppPadding.cardPadding,
                decoration: BoxDecoration(
                  color: AppColors.cardVariant,
                  borderRadius: AppBorderRadius.only(
                    bottomLeft: AppBorderRadius.large,
                    bottomRight: AppBorderRadius.large,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(builderContext).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textOnAccent,
                        backgroundColor: AppColors.accentColor,
                        padding: AppPadding.cardPadding,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppBorderRadius.smallRadius,
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: AppTextStyles.buttonText(
                          color: AppColors.textOnAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
