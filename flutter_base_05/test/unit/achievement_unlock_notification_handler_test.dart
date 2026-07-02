import 'package:flutter_test/flutter_test.dart';
import 'package:dutch/modules/notifications_module/utils/achievement_unlock_notification_handler.dart';

void main() {
  group('isAchievementUnlockNotification', () {
    test('matches subtype dutch_achievement_unlock', () {
      expect(
        isAchievementUnlockNotification({
          'subtype': 'dutch_achievement_unlock',
          'data': {},
        }),
        isTrue,
      );
    });

    test('matches data.event dutch_achievement with achievement_id', () {
      expect(
        isAchievementUnlockNotification({
          'data': {
            'event': 'dutch_achievement',
            'achievement_id': 'lb_alltime_classic_first',
          },
        }),
        isTrue,
      );
    });

    test('rejects generic instant', () {
      expect(
        isAchievementUnlockNotification({
          'subtype': 'welcome',
          'title': 'Hello',
        }),
        isFalse,
      );
    });
  });

  group('partitionAchievementUnlockMessages', () {
    test('splits achievement unlocks from other instants', () {
      final partition = partitionAchievementUnlockMessages([
        {
          'id': '1',
          'subtype': 'dutch_achievement_unlock',
          'data': {'achievement_id': 'lb_monthly_classic_novice_first'},
        },
        {'id': '2', 'title': 'Invite'},
      ]);
      expect(partition.achievementUnlocks.length, 1);
      expect(partition.otherMessages.length, 1);
      expect(partition.achievementUnlocks.first['id'], '1');
    });
  });

  group('achievementUnlockMessagesToShow', () {
    tearDown(resetAchievementCelebrationSessionForTest);

    test('keeps one row per achievement id', () {
      final show = achievementUnlockMessagesToShow([
        {
          'id': 'n1',
          'data': {'achievement_id': 'lb_alltime_classic_top_50'},
        },
        {
          'id': 'n2',
          'data': {'achievement_id': 'lb_alltime_classic_top_50'},
        },
        {
          'id': 'n3',
          'data': {'achievement_id': 'lb_alltime_classic_top_10'},
        },
      ]);
      expect(show.length, 2);
      expect(show.map((m) => m['id']).toList(), ['n1', 'n3']);
    });
  });
}
