import 'package:dart_game_server/utils/dev_logger.dart';
import '../services/game_registry.dart';
import 'gameplay_profiles_store.dart';
import 'level_matcher.dart';

const bool LOGGING_SWITCH = false;

/// Resolves declarative gameplay profiles for special events and match start.
class GameplayProfileResolver {
  GameplayProfileResolver._();

  static String defaultProfileId() => GameplayProfilesStore.defaultProfileId;

  static String? profileIdForSpecialEvent(String? specialEventId) {
    if (specialEventId == null || specialEventId.trim().isEmpty) return null;
    final row = LevelMatcher.specialEventRowById(specialEventId.trim());
    if (row == null) return null;
    final raw = row['gameplay_profile_id'];
    if (raw == null || raw.toString().trim().isEmpty) {
      return defaultProfileId();
    }
    return raw.toString().trim();
  }

  static Map<String, dynamic> resolveSnapshot({
    String? profileId,
    String? specialEventId,
  }) {
    final fromEvent = profileIdForSpecialEvent(specialEventId);
    final pid = (profileId ?? fromEvent ?? defaultProfileId()).trim();
    return GameplayProfilesStore.buildSnapshotForProfile(pid);
  }

  static Map<String, int> mergeTimerConfig(Map<String, dynamic> profileSnapshot) {
    final base = Map<String, int>.from(
      ServerGameStateCallbackImpl.getAllTimerValues(),
    );
    final timers = profileSnapshot['timers'];
    if (timers is Map) {
      timers.forEach((key, value) {
        final k = key.toString();
        if (value is int) {
          base[k] = value;
        } else {
          final parsed = int.tryParse('$value');
          if (parsed != null) base[k] = parsed;
        }
      });
    }
    return base;
  }

  static void reloadCatalogsFromDisk() {
    LevelMatcher.reloadFromDisk();
    GameplayProfilesStore.reloadFromDisk();
    if (LOGGING_SWITCH) {
      customlog(
        'GameplayProfileResolver.reloadCatalogsFromDisk: '
        'profiles_revision=${GameplayProfilesStore.cachedRevision ?? '(none)'}',
      );
    }
  }
}
