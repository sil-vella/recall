import 'package:flutter/material.dart';

import '../managers/hooks_manager.dart';
import '../managers/state_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../modules/notifications_module/notifications_module.dart';
import '../../modules/dutch_game/managers/validated_event_emitter.dart';
import '../../modules/dutch_game/utils/dutch_game_helpers.dart';
import '../../modules/dutch_game/backend_core/utils/level_matcher.dart';

/// POST notification action, mark read, and fire [instant_message_response_success] for Dutch match invites.
Future<bool> submitInstantNotificationResponse({
  required ConnectionsApiModule api,
  NotificationsModule? mod,
  required String messageId,
  required String actionIdentifier,
  required BuildContext context,
  required Map<String, dynamic> messageRow,
}) async {
  try {
    final res = await api.sendPostRequest(
      '/userauth/notifications/response',
      {'message_id': messageId, 'action_identifier': actionIdentifier},
    ) as Map<String, dynamic>? ?? {};
    final ok = res['success'] == true;
    if (ok && context.mounted) {
      if (messageId.isNotEmpty && mod != null) {
        await mod.markAsRead([messageId]);
      }
      final msgId = messageRow['msg_id']?.toString() ?? '';
      HooksManager().triggerHookWithData('instant_message_response_success', {
        'context': context,
        'msg_id': msgId,
        'response': res,
        'message': messageRow,
      });
    }
    return ok;
  } catch (_) {
    return false;
  }
}

/// Accept / decline on a pending [instant_ws] rematch invite ([respond_via] == `rematch_ws` in message [data]).
/// Emits `rematch_accepted` or `rematch_declined` via [DutchGameEventEmitter] (includes `session_id` + `user_id` from transport).
Future<bool> submitRematchInviteResponse({
  required String actionIdentifier,
  required Map<String, dynamic> messageRow,
}) async {
  final data = messageRow['data'];
  if (data is! Map) return false;
  if (data['respond_via'] != 'rematch_ws') return false;

  final roomId = data['room_id']?.toString() ?? '';
  final gameId = data['game_id']?.toString() ?? roomId;
  if (roomId.isEmpty) return false;

  final aid = actionIdentifier.toLowerCase().trim();
  final String eventType;
  if (aid == 'rematch_accept') {
    final glRaw = data['game_level'];
    final effectiveLevel = glRaw is int
        ? glRaw
        : (glRaw is num
            ? glRaw.toInt()
            : int.tryParse(glRaw?.toString() ?? '') ?? 1);
    final coinReqRaw = data['is_coin_required'];
    final needsCoins = coinReqRaw is bool
        ? coinReqRaw
        : (coinReqRaw?.toString().toLowerCase() != 'false');
    if (needsCoins) {
      final ok = await DutchGameHelpers.checkCoinsRequirement(
        gameLevel: effectiveLevel,
        fetchFromAPI: true,
      );
      if (!ok) {
        final required = LevelMatcher.tableLevelToCoinFee(effectiveLevel, defaultFee: 25);
        final stash = <String, dynamic>{
          'room_id': roomId,
          'game_id': gameId,
          'game_level': effectiveLevel,
          'required_coins': required,
          'updatedAt': DateTime.now().toIso8601String(),
        };
        await DutchGameHelpers.stashLastCoinPurchaseContextAndShowBuyModal(
          stash: stash,
          requiredCoins: required,
        );
        // Close rematch invite dialog; buy modal is shown separately.
        return true;
      }
    }
    eventType = 'rematch_accepted';
  } else if (aid == 'rematch_decline') {
    eventType = 'rematch_declined';
  } else {
    return false;
  }

  try {
    await DutchGameEventEmitter.instance.emit(
      eventType: eventType,
      data: {
        'room_id': roomId,
        'game_id': gameId,
      },
    );
    final dg = StateManager().getModuleState<Map<String, dynamic>>('dutch_game') ?? {};
    final cur = dg['rematch_waiting_game_id']?.toString() ?? '';
    if (eventType == 'rematch_declined') {
      if (cur == roomId || cur == gameId) {
        StateManager().updateModuleState('dutch_game', {'rematch_waiting_game_id': ''});
      }
    } else if (eventType == 'rematch_accepted') {
      StateManager().updateModuleState('dutch_game', {'rematch_waiting_game_id': roomId});
    }
    return true;
  } catch (_) {
    return false;
  }
}
