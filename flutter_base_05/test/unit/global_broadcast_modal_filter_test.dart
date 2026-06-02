import 'package:flutter_test/flutter_test.dart';

import 'package:dutch/modules/notifications_module/utils/app_version_helper.dart';
import 'package:dutch/modules/notifications_module/utils/global_broadcast_modal_filter.dart';

void main() {
  group('compareSemanticVersions', () {
    test('orders patch versions', () {
      expect(compareSemanticVersions('2.0.20', '2.0.21'), lessThan(0));
      expect(compareSemanticVersions('2.0.21', '2.0.20'), greaterThan(0));
      expect(compareSemanticVersions('2.0.20', '2.0.20'), 0);
    });
  });

  group('shouldShowInstantModalMessage', () {
    test('hides app update when installed version meets target', () {
      expect(
        shouldShowInstantModalMessage(
          {
            'type': 'instant',
            'data': {'target_version': '2.0.21'},
          },
          currentAppVersion: '2.0.21',
        ),
        isFalse,
      );
    });

    test('shows app update when installed version is older', () {
      expect(
        shouldShowInstantModalMessage(
          {
            'type': 'instant',
            'user_read': false,
            'data': {'target_version': '2.0.21'},
          },
          currentAppVersion: '2.0.20',
        ),
        isTrue,
      );
    });

    test('hides when user_read is true', () {
      expect(
        shouldShowInstantModalMessage(
          {
            'type': 'instant',
            'user_read': true,
            'data': {'target_version': '2.0.21'},
          },
          currentAppVersion: '2.0.20',
        ),
        isFalse,
      );
    });
  });

  tearDown(AppVersionHelper.resetCacheForTests);
}
