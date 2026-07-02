import 'package:flutter/material.dart';

import '../../../core/managers/navigation_manager.dart';
import '../../dutch_game/screens/promotion/dutch_achievement_celebration_screen.dart';
import '../../dutch_game/utils/dutch_achievement_catalog.dart';
import '../../dutch_game/utils/dutch_game_helpers.dart';

const String kSubtypeAchievementUnlock = 'dutch_achievement_unlock';

/// True when [message] should open [DutchAchievementCelebrationScreen] instead of a generic instant modal.
bool isAchievementUnlockNotification(Map<String, dynamic> message) {
  final subtype = message['subtype']?.toString() ?? '';
  if (subtype == kSubtypeAchievementUnlock) return true;
  final data = message['data'];
  if (data is Map) {
    final event = data['event']?.toString() ?? '';
    final achId = data['achievement_id']?.toString() ?? '';
    return event == 'dutch_achievement' && achId.isNotEmpty;
  }
  return false;
}

class AchievementUnlockPartition {
  const AchievementUnlockPartition(this.achievementUnlocks, this.otherMessages);

  final List<Map<String, dynamic>> achievementUnlocks;
  final List<Map<String, dynamic>> otherMessages;
}

AchievementUnlockPartition partitionAchievementUnlockMessages(
  List<Map<String, dynamic>> messages,
) {
  final achievement = <Map<String, dynamic>>[];
  final other = <Map<String, dynamic>>[];
  for (final m in messages) {
    if (isAchievementUnlockNotification(m)) {
      achievement.add(m);
    } else {
      other.add(m);
    }
  }
  return AchievementUnlockPartition(achievement, other);
}

String achievementIdFromNotification(Map<String, dynamic> message) {
  final data = message['data'];
  if (data is Map && data['achievement_id'] != null) {
    return data['achievement_id'].toString();
  }
  return '';
}

/// Shows fullscreen achievement celebration(s), then marks each notification read.
Future<void> drainAchievementUnlockNotifications(
  BuildContext context, {
  required List<Map<String, dynamic>> messages,
  required Future<void> Function(String messageId) onMarkAsRead,
}) async {
  if (messages.isEmpty) return;
  for (final message in messages) {
    final navCtx = NavigationManager().navigatorKey.currentContext ?? context;
    if (!navCtx.mounted) return;
    final id = message['id']?.toString() ?? '';
    final achId = achievementIdFromNotification(message);
    final title = message['title']?.toString().trim() ??
        (achId.isEmpty ? 'Achievement unlocked' : DutchAchievementCatalog.displayTitle(achId));
    final entry = achId.isEmpty ? null : DutchAchievementEntry.byId(achId);
    final body = message['body']?.toString().trim() ?? entry?.description ?? '';
    await Navigator.of(navCtx, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => DutchAchievementCelebrationScreen(
          achievementId: achId.isEmpty ? null : achId,
          achievementTitle: title,
          achievementDescription: body,
        ),
      ),
    );
    if (id.isNotEmpty) {
      await onMarkAsRead(id);
    }
  }
  await DutchGameHelpers.fetchAndUpdateUserDutchGameData();
}
