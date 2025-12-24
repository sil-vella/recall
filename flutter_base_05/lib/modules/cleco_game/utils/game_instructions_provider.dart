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
  static const String KEY_COLLECTION_CARD = 'collection_card';

  /// Get initial instructions (shown when game hasn't started yet)
  static Map<String, dynamic> getInitialInstructions() {
    return {
      'key': KEY_INITIAL,
      'title': 'Welcome to Cleco!',
      'content': '''🎯 **How to Play Cleco**

**Main Goal:**
Clear all cards **OR** Collect all 4 cards of your rank. Hence **Cle Co** = **Cleco**.

**Gameplay:**
• Tap the draw pile to draw a card
• Select a card from your hand to play (excluding collection card)
• Collect cards from discard pile if they match your collection rank
• Play cards with same rank as last played card (out of turn)
• Queens let you peek at face down cards
• Jacks let you swap any 2 cards, including collection cards

**Final Round:**
If you think you have the least points during your turn, you can call **final round** just before you play a card. This will trigger the final round - this was your final round so you won't play again.

**Winning:**
• Player with **no cards** wins
• Player that collects all 4 cards of their rank wins
• Player with **least points** wins
• If same points, player with **least cards** wins
• If same points and same cards, player who **called final round** wins

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

Tap on any **2 cards** from your hand to reveal them.

The **lowest rank** among the revealed cards will automatically be selected as your collection rank.''',
        'hasDemonstration': true,
      };
    }

    // Handle drawing card status
    if (playerStatus == 'drawing_card' && isMyTurn) {
      return {
        'key': KEY_DRAWING_CARD,
        'title': 'Your Turn - Draw a Card',
        'content': '''🎯 **Draw a Card**

Tap the **draw pile** to draw a card to your hand.''',
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

Select a card from your hand to play, including the newly drawn card, but **excluding the collection card**.''',
      };
    }

    // Handle queen peek status
    if (playerStatus == 'queen_peek' && isMyTurn) {
      return {
        'key': KEY_QUEEN_PEEK,
        'title': 'Queen Power - Peek at a Card',
        'hasDemonstration': true,
        'content': '''👑 **Queen Power Activated**

You have a chance to peek at any **face down card** from any player's hand, including your own.''',
      };
    }

    // Handle jack swap status
    // Note: isMyTurn check removed - jack swap can be activated during same rank plays
    // When playerStatus is 'jack_swap', it means the player has the power regardless of turn
    if (playerStatus == 'jack_swap') {
      return {
        'key': KEY_JACK_SWAP,
        'title': 'Jack Power - Swap Cards',
        'hasDemonstration': true,
        'content': '''🃏 **Jack Power Activated**

You can swap any **2 cards** from any hand, including your own.

Jack swap also enables you to swap out **collection cards** from any hand. You can swap your collection cards with another card from your own hand.

**Important:** If you swap out the last collection card, you no longer have a collection and the swapped out card is now playable. Same applies to opponents' hands.''',
      };
    }

    // Handle collection card (triggered separately on 5th same rank window)
    // Check this FIRST before same_rank_window to ensure it takes precedence
    if (gamePhase == 'same_rank_window' && playerStatus == 'collection_card') {
      return {
        'key': KEY_COLLECTION_CARD,
        'title': 'Collection Cards',
        'hasDemonstration': true,
        'content': '''📚 **Collection Cards**

You can collect cards from the **discard pile** if they are the same rank as your collection rank at any time, **except during same rank play**.

**Important:** Collecting all **4 cards** of your rank will win you the game, but keep in mind collection also adds points.''',
      };
    }

    // Handle same rank window
    if (gamePhase == 'same_rank_window') {
      return {
        'key': KEY_SAME_RANK_WINDOW,
        'title': 'Same Rank Window',
        'hasDemonstration': true,
        'content': '''⚡ **Same Rank Window**

If you know you have a card in hand with the **same rank** as the last played card, you can play it.

**Warning:** Attempting to play a wrong rank will get you a **penalty card**.''',
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
