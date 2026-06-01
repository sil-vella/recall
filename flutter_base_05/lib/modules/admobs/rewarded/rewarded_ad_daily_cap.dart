import '../../../core/services/shared_preferences.dart';
import '../../../utils/consts/config.dart';

/// Client-side daily limit for rewarded ads (UTC calendar day). Server still credits coins via claim API.
abstract final class RewardedAdDailyCap {
  static const String _utcDayKey = 'rewarded_ad_claims_utc_date';
  static const String _countKey = 'rewarded_ad_claims_utc_count';

  static int get dailyCap => Config.admobRewardedDailyCap;

  static String _utcDayString() {
    final u = DateTime.now().toUtc();
    final m = u.month.toString().padLeft(2, '0');
    final d = u.day.toString().padLeft(2, '0');
    return '${u.year}-$m-$d';
  }

  static int claimsUsedToday(SharedPrefManager pref) {
    final storedDay = pref.getString(_utcDayKey) ?? '';
    if (storedDay != _utcDayString()) {
      return 0;
    }
    return pref.getInt(_countKey) ?? 0;
  }

  static int remainingToday(SharedPrefManager pref) {
    final left = dailyCap - claimsUsedToday(pref);
    return left < 0 ? 0 : left;
  }

  static bool canClaimToday(SharedPrefManager pref) => remainingToday(pref) > 0;

  static Future<void> recordClaim(SharedPrefManager pref) async {
    final day = _utcDayString();
    final used = claimsUsedToday(pref);
    await pref.setString(_utcDayKey, day);
    await pref.setInt(_countKey, used + 1);
  }
}
