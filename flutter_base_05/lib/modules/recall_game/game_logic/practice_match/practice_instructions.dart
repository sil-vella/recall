/// Practice Game Instructions
///
/// This file contains all the instruction messages for the practice game mode.
/// It provides a centralized location for all instructional content that helps
/// players learn the Recall game mechanics.

class PracticeInstructions {
  /// Game phase instructions - shown based on current game phase
  /// Note: Keys use frontend phase names (after mapping from backend)
  static const Map<String, Map<String, String>> gamePhaseInstructions = {
    'setup': {
      'title': 'Game Rules',
      'content': '''🔍 Game Rules

Game Rules

🎯 WHAT TO DO:
• Tap any 2 cards to peek at them
• Choose the cards you want to see
• You can't change your selection once made
• After 10 seconds, the game will start automatically

💡 STRATEGY TIPS:
• Look at your highest value cards first
• Check for special cards (Queens, Jacks, Kings)
• Remember what you see for later turns

⏰ TIMER: 10 seconds remaining...''',
    },
    'playing': {
      'title': 'Game in Progress',
      'content': '''🎮 GAME IN PROGRESS

The game is now active! Follow the instructions for your current action:

🃏 YOUR TURN:
• Draw a card from draw pile or discard pile
• Play a card to the discard pile
• Use special card powers when available

💡 REMEMBER:
• Goal: Get rid of high-value cards
• Keep low-value cards (Aces, 2s, 3s)
• Watch what opponents are doing
• Plan your strategy carefully

🎯 WINNING:
• First to empty hand wins
• Or lowest points when "Recall" is called

⏰ Take your time and think strategically!''',
    },
  };

  /// Player status instructions - shown based on current player status
  static const Map<String, Map<String, String>> playerStatusInstructions = {
    'initial_peek': {
      'title': 'Initial Peek - Choose Your Cards',
      'content': '''🔍 PEEK AT YOUR CARDS

You have 10 seconds to look at 2 of your 4 cards!

🎯 HOW TO PEEK:
• Tap any 2 cards in your hand
• The cards will flip to show their values
• Choose wisely - you can't change your selection

💡 WHAT TO LOOK FOR:
• High-value cards (10+ points) to avoid
• Special cards (Queens, Jacks, Kings) for powers
• Low-value cards (Aces, 2s, 3s) to keep

⏰ HURRY! Timer is running...''',
    },
    'drawing_card': {
      'title': 'Draw a Card',
      'content': '''🃏 DRAW A CARD

Choose where to draw from:

📦 DRAW PILE (Face Down):
• Draw a random card from the deck
• No one knows what you got
• Safe but unpredictable

🗑️ DISCARD PILE (Face Up):
• Take the top card everyone can see
• You know exactly what you're getting
• Others can see what you took

💡 STRATEGY:
• Draw pile: When you want surprise cards
• Discard pile: When you see a good card you want

⏰ Choose quickly!''',
    },
    'playing_card': {
      'title': 'Play a Card',
      'content': '''🎯 PLAY A CARD

Choose a card to play to the discard pile:

🃏 CARD SELECTION:
• Tap any card in your hand to play it
• The card will go to the discard pile
• Other players can see what you played

💡 STRATEGY:
• Get rid of high-value cards first (10+ points)
• Keep low-value cards for later (Aces, 2s, 3s)
• Watch what others are discarding
• Plan your moves carefully

🎮 SPECIAL CARDS:
• Queens: Let you peek at opponent's cards
• Jacks: Let you swap cards with opponents
• Kings: Worth 10 points (avoid if possible)
• Use special powers strategically!

⏰ Choose quickly! Timer is running...''',
    },
  };

  /// Get instruction by game phase
  static Map<String, String>? getGamePhaseInstruction(String phase) {
    return gamePhaseInstructions[phase];
  }

  /// Get instruction by player status
  static Map<String, String>? getPlayerStatusInstruction(String status) {
    return playerStatusInstructions[status];
  }

  /// Check if a game phase instruction exists
  static bool hasGamePhaseInstruction(String phase) {
    return gamePhaseInstructions.containsKey(phase);
  }

  /// Check if a player status instruction exists
  static bool hasPlayerStatusInstruction(String status) {
    return playerStatusInstructions.containsKey(status);
  }
}
