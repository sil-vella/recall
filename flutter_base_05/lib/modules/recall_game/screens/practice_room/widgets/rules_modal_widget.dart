import 'package:flutter/material.dart';

/// Rules Modal Widget for Practice Room
/// 
/// This widget displays the game rules and overview as a modal overlay.
/// It's shown when the "View Rules" button is pressed in the practice room.
class RulesModalWidget extends StatelessWidget {
  const RulesModalWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54, // Semi-transparent background
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          constraints: const BoxConstraints(
            maxWidth: 600,
            maxHeight: 700,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with title and close button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.rule,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Recall Game Rules',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: Theme.of(context).primaryColor,
                      tooltip: 'Close rules',
                    ),
                  ],
                ),
              ),
              
              // Content area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSection(
                        context,
                        '🎯 Objective',
                        'Finish with no cards OR have the fewest points when someone calls "Recall".',
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
5. **Call Recall**: When you think you can win, call "Recall"''',
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
• **After Recall**: Lowest points wins
• **Tie Breaker**: Fewer cards wins
• **Recall Caller**: Wins ties if involved''',
                      ),
                      
                      const SizedBox(height: 20),
                      
                      _buildSection(
                        context,
                        '💡 Strategy Tips',
                        '''• Get rid of high-value cards first
• Remember cards you've seen
• Watch what others discard
• Use special cards strategically
• Call "Recall" when you're confident''',
                      ),
                      
                      const SizedBox(height: 20),
                      
                      _buildSection(
                        context,
                        '🎯 Practice Mode',
                        '''• Play against AI opponents
• Learn the game at your own pace
• No time pressure (if timer is off)
• Get helpful instructions during play
• Perfect for learning the game!''',
                      ),
                    ],
                  ),
                ),
              ),
              
              // Footer with close button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSection(BuildContext context, String title, String content) {
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
