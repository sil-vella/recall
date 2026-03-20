import 'package:flutter/material.dart';

import '../managers/hooks_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';
import '../../modules/notifications_module/notifications_module.dart';

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
