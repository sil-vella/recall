import 'package:flutter_test/flutter_test.dart';
import 'package:dutch/modules/dutch_game/backend_core/services/game_state_frontend_filter.dart';

void main() {
  test('filterGameStateForFrontend keeps last two pile cards and full counts', () {
    final draw = List.generate(
      5,
      (i) => {'cardId': 'd$i', 'suit': '?', 'rank': '?', 'points': 0},
    );
    final discard = [
      {'cardId': 'c0', 'suit': 'hearts', 'rank': '2', 'points': 2},
      {'cardId': 'c1', 'suit': 'spades', 'rank': '3', 'points': 3},
      {'cardId': 'c2', 'suit': 'clubs', 'rank': '4', 'points': 4},
    ];
    final filtered = filterGameStateForFrontend({
      'originalDeck': [{'cardId': 'x'}],
      'drawPile': draw,
      'discardPile': discard,
    });

    expect(filtered.containsKey('originalDeck'), isFalse);
    expect(filtered['drawPileCount'], 5);
    expect(filtered['discardPileCount'], 3);
    expect((filtered['drawPile'] as List).length, 2);
    expect((filtered['drawPile'] as List).last['cardId'], 'd4');
    expect((filtered['discardPile'] as List).length, 2);
    expect((filtered['discardPile'] as List).last['cardId'], 'c2');
  });
}
