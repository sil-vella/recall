import 'package:flutter/material.dart';
import '../../../utils/modal_template_widget.dart';

/// Rules Modal Widget for Dutch Room
/// 
/// This widget displays the game rules and overview as a modal overlay.
/// It's shown when the "View Rules" button is pressed in the dutch room.
class RulesModalWidget extends StatelessWidget {
  const RulesModalWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ModalTemplateWidget(
      title: 'Dutch Game Rules',
      content: _buildRulesContent(),
      icon: Icons.rule,
      onClose: () => Navigator.of(context).pop(),
      customContent: _buildCustomContent(context),
    );
  }

  /// Show the rules modal using Flutter's official showDialog method
  static Future<void> show(BuildContext context) {
    return ModalTemplateWidget.show(
      context: context,
      title: 'Dutch Game Rules',
      content: _buildRulesContent(),
      icon: Icons.rule,
      customContent: _buildCustomContent(context),
    );
  }

  static String _buildRulesContent() {
    return '''🎯 OBJECTIVE
Finish with no cards OR have the fewest points when someone calls "Dutch".

🃏 CARD VALUES
• Numbered cards (2-10): Points equal to card number
• Ace: 1 point
• Queens & Jacks: 10 points
• Kings (Black): 10 points
• Joker & Red King: 0 points

🎮 HOW TO PLAY
1. **Initial Peek**: Look at 2 of your 4 cards (10 seconds)
2. **Your Turn**: Draw a card from draw pile or discard pile
3. **Play or Keep**: Play a card to discard pile or keep it in hand
4. **Next Player**: Turn passes to the next player
5. **Call Dutch**: When you think you can win, call "Dutch"

🃏 SPECIAL CARDS
• **Queens**: Let you peek at any opponent's card
• **Jacks**: Let you swap any two cards between players
• **Jokers**: 0 points - very valuable!
• **Red King**: 0 points - very valuable!

🏆 WINNING
• **Immediate Win**: First player to have no cards
• **After Dutch**: Lowest points wins
• **Tie Breaker**: Fewer cards wins
• **Dutch Caller**: Wins ties if involved

💡 STRATEGY TIPS
• Get rid of high-value cards first
• Remember cards you've seen
• Watch what others discard
• Use special cards strategically
• Call "Dutch" when you're confident

🎯 PRACTICE MODE
• Play against AI opponents
• Learn the game at your own pace
• No time pressure (if timer is off)
• Get helpful instructions during play
• Perfect for learning the game!''';
  }

  static Widget _buildCustomContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            context,
            '🎯 Objective',
            'Finish with no cards OR have the fewest points when someone calls "Dutch".',
          ),
          
          const SizedBox(height: 20),
          
          _buildSection(
            context,
            '🃏 Card Values',
            '''• Numbered cards (2-10): Points equal to card number
• Ace: 1 point
• Queens & Jacks: 10 points
• Kings (Black): 10 points
• Joker & Red King: 0 points''',
          ),
          
          const SizedBox(height: 20),
          
          _buildSection(
            context,
            '🎮 How to Play',
            '''1. **Initial Peek**: Look at 2 of your 4 cards (10 seconds)
2. **Your Turn**: Draw a card from draw pile or discard pile
3. **Play or Keep**: Play a card to discard pile or keep it in hand
4. **Next Player**: Turn passes to the next player
5. **Call Dutch**: When you think you can win, call "Dutch"''',
          ),
          
          const SizedBox(height: 20),
          
          _buildSection(
            context,
            '🃏 Special Cards',
            '''• **Queens**: Let you peek at any opponent's card
• **Jacks**: Let you swap any two cards between players
• **Jokers**: 0 points - very valuable!
• **Red King**: 0 points - very valuable!''',
          ),
          
          const SizedBox(height: 20),
          
          _buildSection(
            context,
            '🏆 Winning',
            '''• **Immediate Win**: First player to have no cards
• **After Dutch**: Lowest points wins
• **Tie Breaker**: Fewer cards wins
• **Dutch Caller**: Wins ties if involved''',
          ),
          
          const SizedBox(height: 20),
          
          _buildSection(
            context,
            '💡 Strategy Tips',
            '''• Get rid of high-value cards first
• Remember cards you've seen
• Watch what others discard
• Use special cards strategically
• Call "Dutch" when you're confident''',
          ),
          
          const SizedBox(height: 20),
          
          _buildSection(
            context,
            '🎯 Dutch Mode',
            '''• Play against AI opponents
• Learn the game at your own pace
• No time pressure (if timer is off)
• Get helpful instructions during play
• Perfect for learning the game!''',
          ),
        ],
      ),
    );
  }
  
  static Widget _buildSection(BuildContext context, String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
