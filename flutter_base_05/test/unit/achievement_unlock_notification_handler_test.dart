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
}
