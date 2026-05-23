import 'package:dutch/modules/dutch_game/backend_core/utils/dutch_rank_level_change_checker.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_share_helper.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_share_moment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testStore = 'https://example.com/app';

  group('DutchShareHelper.buildWinPayload', () {
    test('includes outcome and store URL', () {
      final p = DutchShareHelper.buildWinPayload(
        winnerMessage: 'Alice (Dutch Called)',
        storeUrlOverride: testStore,
      );
      expect(p.subject, 'I won in Dutch!');
      expect(p.text, contains('Alice (Dutch Called)'));
      expect(p.text, contains(testStore));
      expect(p.text, contains('Play Dutch Card Game'));
    });

    test('uses generic body when winner message empty', () {
      final p = DutchShareHelper.buildWinPayload(
        winnerMessage: '',
        storeUrlOverride: testStore,
      );
      expect(p.text, contains('I just won a match'));
      expect(p.text, contains(testStore));
    });
  });

  group('DutchShareHelper.buildLevelUpPayload', () {
    test('includes level transition and wins', () {
      const change = DutchRankLevelChangeResult(
        hadBeforeSnapshot: true,
        rankChanged: false,
        levelChanged: true,
        storedRankTrend: StoredTrend.same,
        storedLevelTrend: StoredTrend.progression,
        matcherTrend: MatcherTrend.same,
        levelBefore: 2,
        levelAfter: 3,
        winsAfter: 12,
      );
      final p = DutchShareHelper.buildLevelUpPayload(
        change: change,
        storeUrlOverride: testStore,
      );
      expect(p.subject, 'Level up in Dutch!');
      expect(p.text, contains('Level 2 → 3'));
      expect(p.text, contains('12 wins'));
      expect(p.text, contains(testStore));
    });
  });

  group('DutchShareHelper.buildRankUpPayload', () {
    test('capitalizes rank names and includes store URL', () {
      const change = DutchRankLevelChangeResult(
        hadBeforeSnapshot: true,
        rankChanged: true,
        levelChanged: false,
        storedRankTrend: StoredTrend.progression,
        storedLevelTrend: StoredTrend.same,
        matcherTrend: MatcherTrend.progression,
        rankBefore: 'silver',
        rankAfter: 'gold',
      );
      final p = DutchShareHelper.buildRankUpPayload(
        change: change,
        storeUrlOverride: testStore,
      );
      expect(p.subject, 'Rank up in Dutch!');
      expect(p.text, contains('Rank Silver → Gold'));
      expect(p.text, contains(testStore));
    });
  });

  group('DutchShareHelper.buildPayload', () {
    test('dispatches by moment', () {
      final win = DutchShareHelper.buildPayload(
        moment: DutchShareMoment.win,
        winnerMessage: 'Test',
        storeUrlOverride: testStore,
      );
      expect(win.subject, 'I won in Dutch!');

      const change = DutchRankLevelChangeResult(
        hadBeforeSnapshot: true,
        rankChanged: false,
        levelChanged: true,
        storedRankTrend: StoredTrend.same,
        storedLevelTrend: StoredTrend.progression,
        matcherTrend: MatcherTrend.same,
        levelBefore: 1,
        levelAfter: 2,
      );
      final level = DutchShareHelper.buildPayload(
        moment: DutchShareMoment.levelUp,
        change: change,
        storeUrlOverride: testStore,
      );
      expect(level.subject, 'Level up in Dutch!');
    });
  });

  group('DutchShareMoment.analyticsValue', () {
    test('uses snake_case for GA4', () {
      expect(DutchShareMoment.win.analyticsValue, 'win');
      expect(DutchShareMoment.levelUp.analyticsValue, 'level_up');
      expect(DutchShareMoment.rankUp.analyticsValue, 'rank_up');
    });
  });
}
