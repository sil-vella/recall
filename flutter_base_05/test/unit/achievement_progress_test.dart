import 'package:flutter_test/flutter_test.dart';
import 'package:dutch/modules/dutch_game/utils/achievement_progress.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_achievement_catalog.dart';

void main() {
  test('total_wins progress from stats', () {
    const entry = DutchAchievementEntry(
      id: 'centurion',
      title: 'Centurion',
      description: 'Win 100 matches.',
      unlock: {'type': 'total_wins', 'min': 100},
    );
    final p = achievementProgressFor(
      entry: entry,
      unlocked: false,
      stats: {'wins': 42},
    );
    expect(p, isNotNull);
    expect(p!.current, 42);
    expect(p.required, 100);
    expect(p.label, 'Total wins');
  });

  test('event_win progress uses special_event_wins map', () {
    const entry = DutchAchievementEntry(
      id: 'cards_night_winner',
      title: 'Cards Night',
      description: 'Win Cards Night.',
      unlock: {
        'type': 'event_win',
        'special_event_id': 'cards_night',
        'min': 3,
      },
    );
    final p = achievementProgressFor(
      entry: entry,
      unlocked: false,
      stats: {
        'special_event_wins': {'cards_night': 2},
      },
    );
    expect(p!.current, 2);
    expect(p.required, 3);
  });

  test('unlocked achievements hide progress', () {
    const entry = DutchAchievementEntry(
      id: 'first_blood',
      title: 'First victory',
      description: 'Win once.',
      unlock: {'type': 'total_wins', 'min': 1},
    );
    expect(
      achievementProgressFor(
        entry: entry,
        unlocked: true,
        stats: {'wins': 10},
      ),
      isNull,
    );
  });
}
