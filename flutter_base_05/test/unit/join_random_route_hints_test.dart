import 'package:flutter_test/flutter_test.dart';

import 'package:dutch/modules/dutch_game/screens/lobby_room/widgets/join_random_game_widget.dart';

void main() {
  group('joinRandomEventCarouselIndexForRouteHints', () {
    test('resolves cards_night from declarative catalog id', () {
      final entries = [
        JoinRandomEventEntry({'id': 'dutch_explorer', 'title': 'Dutch Explorer'}),
        JoinRandomEventEntry({'id': 'cards_night', 'title': 'Cards Night'}),
      ];
      final idx = joinRandomEventCarouselIndexForRouteHints(
        entries,
        eventId: 'cards_night',
      );
      expect(idx, 1);
    });

    test('returns null when event_id is unknown', () {
      final entries = [
        JoinRandomEventEntry({'id': 'cards_night', 'title': 'Cards Night'}),
      ];
      expect(
        joinRandomEventCarouselIndexForRouteHints(entries, eventId: 'missing_event'),
        isNull,
      );
    });
  });
}
