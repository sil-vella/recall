import 'package:flutter_test/flutter_test.dart';
import 'package:dutch/modules/dutch_game/utils/achievements_catalog_store.dart';

void main() {
  test('displayTitle uses catalog then humanizes', () {
    AchievementsCatalogStore.applyDocument({
      'schema_version': 1,
      'achievements': [
        {
          'id': 'win_streak_2',
          'title': 'Hot hand',
          'description': 'Win 2 matches in a row.',
          'unlock': {'type': 'win_streak', 'min': 2},
        },
      ],
    });

    expect(AchievementsCatalogStore.displayTitle('win_streak_2'), 'Hot hand');
    expect(AchievementsCatalogStore.displayTitle('unknown_foo_bar'), 'Unknown Foo Bar');
  });
}
