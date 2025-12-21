/// Game Instructions Provider
/// 
/// Provides contextual instructions based on game phase and player status.
/// Used when showInstructions flag is enabled in practice mode.
class GameInstructionsProvider {
  /// Instruction key constants
  static const String KEY_INITIAL = 'initial';
  static const String KEY_INITIAL_PEEK = 'initial_peek';
  static const String KEY_DRAWING_CARD = 'drawing_card';
  static const String KEY_PLAYING_CARD = 'playing_card';
  static const String KEY_QUEEN_PEEK = 'queen_peek';
  static const String KEY_JACK_SWAP = 'jack_swap';
  static const String KEY_SAME_RANK_WINDOW = 'same_rank_window';

  /// Get initial instructions (shown when game hasn't started yet)
  static Map<String, dynamic> getInitialInstructions() {
    return {
      'key': KEY_INITIAL,
      'title': 'Welcome to Cleco!',
      'content': '''🎯 **How to Play Cleco**

**Objective:**
Finish with no cards OR have the fewest points when someone calls "Cleco".

**Card Values:**
• Numbered cards (2-10): Points equal to card number
• Ace: 1 point
• Queens & Jacks: 10 points
• Kings (Black): 10 points
• Joker & Red King: 0 points (very valuable!)

**Game Flow:**
1. **Initial Peek**: Look at 2 of your 4 cards
2. **Your Turn**: Draw a card, then play a card
3. **Special Cards**: Queens let you peek, Jacks let you swap cards
4. **Same Rank**: Play matching cards out of turn
5. **Call Cleco**: When you think you can win!

**Strategy:** Get rid of high-value cards first to minimize your points!

You'll get helpful instructions as you play. You can mark any instruction as "Understood, don't show again" if you don't need to see it anymore.''',
    };
  }

  /// Get instructions for a given game phase and player status
  /// 
  /// [gamePhase] - Current game phase (waiting, initial_peek, playing, etc.)
  /// [playerStatus] - Current player status (drawing_card, playing_card, initial_peek, etc.)
  /// [isMyTurn] - Whether it's the current user's turn
  /// 
  /// Returns a map with 'key', 'title', 'content', and optionally 'hasDemonstration' keys, or null if no instructions for this state
  static Map<String, dynamic>? getInstructions({
    required String gamePhase,
    String? playerStatus,
    bool isMyTurn = false,
  }) {
    // Handle initial peek phase
    if (gamePhase == 'initial_peek' || playerStatus == 'initial_peek') {
      return {
        'key': KEY_INITIAL_PEEK,
        'title': 'Initial Peek Phase',
        'content': '''🎯 **Initial Peek Phase**

You have 4 cards face down. You can peek at **2 of them**.

**How to peek:**
1. Tap on a card to flip it and see its value
2. Choose which 2 cards you want to peek at
3. After peeking at 2 cards, you'll need to decide which rank you want to collect

**Strategy Tip:** Choose cards that help you decide which rank to collect. Low-value cards (Aces, 2s, 3s) or special cards (Jokers, Red Kings) are often good choices!

**Card Values:**
• Numbered cards (2-10): Points equal to card number
• Ace: 1 point
• Queens & Jacks: 10 points
• Kings (Black): 10 points
• Joker & Red King: 0 points (very valuable!)''',
        'hasDemonstration': true,
      };
    }

    // Handle drawing card status
    if (playerStatus == 'drawing_card' && isMyTurn) {
      return {
        'key': KEY_DRAWING_CARD,
        'title': 'Your Turn - Draw a Card',
        'content': '''🎯 **Draw a Card**

It's your turn! You need to draw a card first.

**Options:**
1. **Draw from Draw Pile** (face down) - Tap the draw pile to draw a random card
2. **Take from Discard Pile** (face up) - Tap the top card of the discard pile to take it

**Strategy Tips:**
• Taking from discard pile reveals information to opponents
• Draw pile is random - you won't know what you get
• Consider what opponents might need based on what they've discarded

After drawing, you'll choose whether to play the drawn card or one from your hand.''',
        'hasDemonstration': true,
      };
    }

    // Handle playing card status
    if (playerStatus == 'playing_card' && isMyTurn) {
      return {
        'key': KEY_PLAYING_CARD,
        'title': 'Your Turn - Play a Card',
        'hasDemonstration': true,
        'content': '''🎯 **Play a Card**

You've drawn a card. Now choose what to play:

**Options:**
1. **Play the drawn card** - Discard it to the discard pile
2. **Play a card from your hand** - Choose a card from your hand to discard

**Card Values (Points):**
• Numbered cards (2-10): Points equal to card number
• Ace: 1 point
• Queens & Jacks: 10 points
• Kings (Black): 10 points
• Joker & Red King: 0 points (very valuable - keep these!)

**Special Cards:**
• **Queens**: When played, let you peek at any opponent's card
• **Jacks**: When played, let you swap any two cards between players

**Strategy:** Get rid of high-value cards first to minimize your points!''',
      };
    }

    // Handle queen peek status
    if (playerStatus == 'queen_peek' && isMyTurn) {
      return {
        'key': KEY_QUEEN_PEEK,
        'title': 'Queen Power - Peek at a Card',
        'hasDemonstration': true,
        'content': '''👑 **Queen Power Activated**

You played a Queen! You can now peek at any opponent's card.

**How to use:**
1. Tap on an opponent's card to see its value
2. This information will help you make better decisions
3. The peeked card will be revealed to you

**Strategy Tip:** Use this to see what high-value cards opponents have, or to check if they're collecting a specific rank!''',
      };
    }

    // Handle jack swap status
    if (playerStatus == 'jack_swap' && isMyTurn) {
      return {
        'key': KEY_JACK_SWAP,
        'title': 'Jack Power - Swap Cards',
        'content': '''🃏 **Jack Power Activated**

You played a Jack! You can now swap any two cards between players.

**How to use:**
1. Select the first card (from any player, including yourself)
2. Select the second card (from any player, including yourself)
3. The two cards will be swapped

**Strategy Tips:**
• Swap high-value cards from opponents to yourself
• Give opponents high-value cards you don't want
• Swap cards to help you collect a specific rank
• You can swap your own cards to reorganize your hand!''',
      };
    }

    // Handle same rank window
    if (gamePhase == 'same_rank_window') {
      return {
        'key': KEY_SAME_RANK_WINDOW,
        'title': 'Same Rank Window',
        'content': '''⚡ **Same Rank Window**

A card was just played! If you have a card with the **same rank** (number/face), you can play it **out of turn**!

**How it works:**
• Match the rank of the card just played
• You can play before the next player's turn
• Rank matching ignores card color (e.g., red 5 matches black 5)

**Example:** If a 7 was just played, you can play any 7 (red or black) immediately!

**Strategy:** Use this to get rid of cards quickly, especially high-value ones!''',
      };
    }

    // Default: no instructions for this state
    return null;
  }

  /// Get instruction key for a given state
  /// Returns the key identifier for the instruction, or null if no instruction exists
  static String? getInstructionKey({
    required String gamePhase,
    String? playerStatus,
    bool isMyTurn = false,
  }) {
    final instructions = getInstructions(
      gamePhase: gamePhase,
      playerStatus: playerStatus,
      isMyTurn: isMyTurn,
    );
    return instructions?['key'];
  }

  /// Check if instructions should be shown for a given state
  /// 
  /// Instructions should be shown when:
  /// - showInstructions flag is true
  /// - Game phase or player status has changed to a state with instructions
  /// - The instruction hasn't been marked as "don't show again"
  static bool shouldShowInstructions({
    required bool showInstructions,
    required String gamePhase,
    String? playerStatus,
    bool isMyTurn = false,
    String? previousPhase,
    String? previousStatus,
    Map<String, bool>? dontShowAgain,
  }) {
    // Don't show if instructions are disabled
    if (!showInstructions) {
      return false;
    }

    // Get instruction key for current state
    String? instructionKey;
    
    // Show if phase changed to a state with instructions
    if (gamePhase != previousPhase) {
      instructionKey = getInstructionKey(
        gamePhase: gamePhase,
        playerStatus: playerStatus,
        isMyTurn: isMyTurn,
      );
      if (instructionKey != null) {
        // Check if user has marked this instruction as "don't show again"
        if (dontShowAgain?[instructionKey] == true) {
          return false;
        }
        return true;
      }
    }

    // Show if status changed to a state with instructions
    if (playerStatus != previousStatus) {
      instructionKey = getInstructionKey(
        gamePhase: gamePhase,
        playerStatus: playerStatus,
        isMyTurn: isMyTurn,
      );
      if (instructionKey != null) {
        // Check if user has marked this instruction as "don't show again"
        if (dontShowAgain?[instructionKey] == true) {
          return false;
        }
        return true;
      }
    }

    // Show if turn status changed and we have instructions for current state
    // (This handles the case where phase/status is same but isMyTurn changed)
    instructionKey = getInstructionKey(
      gamePhase: gamePhase,
      playerStatus: playerStatus,
      isMyTurn: isMyTurn,
    );
    
    if (instructionKey != null) {
      // Check if user has marked this instruction as "don't show again"
      if (dontShowAgain?[instructionKey] == true) {
        return false;
      }
      return true;
    }
    
    return false;
  }
}
