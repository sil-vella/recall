import 'package:flutter_test/flutter_test.dart';

import 'package:dutch/modules/notifications_module/utils/notification_message_cta.dart';

void main() {
  group('isNotificationStoreLinkDeeplink', () {
    test('matches store_link sentinel case-insensitively', () {
      expect(isNotificationStoreLinkDeeplink('store_link'), isTrue);
      expect(isNotificationStoreLinkDeeplink('STORE_LINK'), isTrue);
      expect(isNotificationStoreLinkDeeplink(' store_link '), isTrue);
      expect(isNotificationStoreLinkDeeplink('https://play.google.com'), isFalse);
      expect(isNotificationStoreLinkDeeplink(null), isFalse);
    });
  });

  group('tryHandleNotificationData', () {
    test('returns false for non-store deeplinks without launching', () async {
      final handled = await tryHandleNotificationData({
        'deeplink': '/dutch/lobby',
      });
      expect(handled, isFalse);
    });
  });
}
