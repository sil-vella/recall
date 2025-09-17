/// Base Power Card Class
///
/// This module defines the base class for all power cards in the Recall game.
/// Each power card extends this class and implements its own special logic.

abstract class BasePowerCard {
  /// Base class for all power cards
  
  final dynamic gameState;
  late final String cardName;

  BasePowerCard(this.gameState) {
    cardName = runtimeType.toString().toLowerCase();
  }

  Map<String, dynamic> updateDecks() {
    /// Update the draw and discard piles
    return {};
  }

  Map<String, dynamic> updateComputerPlayers() {
    /// Update computer player information
    /// purpose is to update the computer players' data like hand/known from other players/points etc etc by calling the player class methods
    return {};
  }
}
