/// Player turn phases for clear UI state management
enum PlayerTurnPhase {
  waiting,           // Not my turn
  mustDraw,          // My turn - must draw from pile first
  hasDrawnCard,      // Drew card - must place it or play from hand
  canPlay,           // Can play any card (normal turn)
  outOfTurn,         // Can play matching cards out of turn
  recallOpportunity, // Can call recall after playing
}

/// Player actions for centralized handling and tutorial integration
enum PlayerAction {
  drawFromDeck,      // Draw card from deck
  takeFromDiscard,   // Take card from discard pile
  playCard,          // Play selected card from hand
  replaceWithDrawn,  // Replace hand card with drawn card
  placeDrawnAndPlay, // Place drawn card and play it
  callRecall,        // Call recall
  playOutOfTurn,     // Play card out of turn
  selectCard,        // Select a card (for tutorial tracking)
  startMatch,        // Start the match
}
