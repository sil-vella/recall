/// Power Card Manager
///
/// This module manages all power cards in the Recall game.
/// It loads power card classes and provides access to them.

import 'queen_peek.dart';

class PowerCardManager {
  /// Manages all power cards in the game
  
  final dynamic gameState;
  Map<String, Type> powerCards = {};

  PowerCardManager(this.gameState) {
    _registerPowerCards();
  }

  void _registerPowerCards() {
    /// Register all available power cards
    powerCards = {
      "queen_peek": QueenPeek,
      // Add more power cards here as they are created
      // "jack_switch": JackSwitch,
      // "joker_wild": JokerWild,
      // etc.
    };
  }
}
