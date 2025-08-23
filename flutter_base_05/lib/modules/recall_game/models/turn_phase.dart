/// Player turn phases for clear UI state management
enum PlayerTurnPhase {
  waiting,           // Not my turn
  mustDraw,          // My turn - must draw from pile first
  hasDrawnCard,      // Drew card - must place it or play from hand
  canPlay,           // Can play any card (normal turn)
  outOfTurn,         // Can play matching cards out of turn
  recallOpportunity, // Can call recall after playing
}
