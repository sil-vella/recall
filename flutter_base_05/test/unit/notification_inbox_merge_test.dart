import 'package:flutter_test/flutter_test.dart';

import 'package:dutch/modules/notifications_module/utils/notification_inbox_merge.dart';

void main() {
  group('mergeGlobalAndApiInstantInbox', () {
    test('drops API row when same msg_id as global', () {
      final merged = mergeGlobalAndApiInstantInbox(
        globalUnreadInstant: [
          {
            'id': 'glob_aaa',
            'msg_id': 'global_welcome_v1',
            'title': 'Welcome to Dutch',
            'type': 'instant',
          },
        ],
        apiList: [
          {
            'id': 'mongo111',
            'msg_id': 'global_welcome_v1',
            'title': 'Welcome to Dutch',
            'type': 'instant',
          },
          {
            'id': 'glob_bbb',
            'msg_id': 'global_app_update_v1',
            'title': 'Update available',
            'type': 'instant',
          },
        ],
      );
      expect(merged.length, 2);
      expect(merged[0]['msg_id'], 'global_welcome_v1');
      expect(merged[0]['id'], 'glob_aaa');
      expect(merged[1]['msg_id'], 'global_app_update_v1');
    });
  });
}
