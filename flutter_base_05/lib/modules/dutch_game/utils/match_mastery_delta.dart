/// Per-match mastery from leftover points, then leftover cards.
/// Mirrors `python_base_04/core/modules/dutch_game/mastery.py` → `match_mastery_delta`.
const int kMasteryPointCap = 40;
const int kMasteryCardCap = 4;
const int kMasteryPointWeight = 10;
const int kMasteryScaleDivisor = 2;
const int kMasteryBothJokersFull = 504;

/// Mastery added for one player's finish. Never negative.
int matchMasteryDelta({required int endPoints, required int endCards}) {
  var points = endPoints;
  var cards = endCards;
  if (points < 0) points = 0;
  if (cards < 0) cards = 0;
  final int raw;
  if (points == 0 && cards == 2) {
    raw = kMasteryBothJokersFull;
  } else {
    final clampedPoints = points > kMasteryPointCap ? kMasteryPointCap : points;
    final clampedCards = cards > kMasteryCardCap ? kMasteryCardCap : cards;
    raw = (kMasteryPointCap - clampedPoints) * kMasteryPointWeight +
        (kMasteryCardCap - clampedCards);
  }
  return raw ~/ kMasteryScaleDivisor;
}
