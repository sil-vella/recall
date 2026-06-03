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
            'subtype': 'app_update',
            'user_read': false,
            'data': {'target_version': '2.0.21'},
          },
          currentAppVersion: '2.0.20',
          currentRoutePath: '/',
        ),
        isTrue,
      );
    });

    test('shows version-gated update when user_read is true', () {
      expect(
        shouldShowInstantModalMessage(
          {
            'type': 'instant',
            'subtype': 'app_update',
            'user_read': true,
            'data': {'target_version': '2.0.21'},
          },
          currentAppVersion: '2.0.20',
          currentRoutePath: '/',
        ),
        isTrue,
      );
    });

    test('hides app update on lobby route', () {
      expect(
        shouldShowInstantModalMessage(
          {
            'type': 'instant',
            'subtype': 'app_update',
            'data': {'target_version': '2.0.21'},
          },
          currentAppVersion: '2.0.20',
          currentRoutePath: '/dutch/lobby',
        ),
        isFalse,
      );
    });

    test('hides non-version instant when user_read is true', () {
      expect(
        shouldShowInstantModalMessage(
          {
            'type': 'instant',
            'user_read': true,
            'subtype': 'welcome',
          },
          currentAppVersion: '2.0.20',
        ),
        isFalse,
      );
    });

    test('hides customize_promo on lobby route', () {
      expect(
        shouldShowInstantModalMessage(
          {
            'type': 'instant',
            'subtype': 'customize_promo',
            'user_read': false,
          },
          currentAppVersion: '2.0.20',
          currentRoutePath: '/dutch/lobby',
        ),
        isFalse,
      );
    });

    test('shows customize_promo on home route', () {
      expect(
        shouldShowInstantModalMessage(
          {
            'type': 'instant',
            'subtype': 'customize_promo',
            'user_read': false,
          },
          currentAppVersion: '2.0.20',
          currentRoutePath: '/',
        ),
        isTrue,
      );
    });

    test('shows welcome on any route', () {
      expect(
        shouldShowInstantModalMessage(
          {
            'type': 'instant',
            'subtype': 'welcome',
            'user_read': false,
          },
          currentAppVersion: '2.0.20',
          currentRoutePath: '/dutch/lobby',
        ),
        isTrue,
      );
    });
  });

  group('isInstantModalHostScreen', () {
    test('accepts home and account paths', () {
      expect(isInstantModalHostScreen('/'), isTrue);
      expect(isInstantModalHostScreen('/account'), isTrue);
      expect(isInstantModalHostScreen('/dutch/lobby'), isFalse);
    });
  });

  group('effectiveInstantModalSubtype', () {
    test('infers customize_promo from deeplink when subtype missing', () {
      expect(
        effectiveInstantModalSubtype({
          'data': {
            'deeplink': {'path': '/dutch-customize', 'item_id': 'card_back_ember'},
          },
        }),
        'customize_promo',
      );
    });
  });

  group('includeGlobalInInstantModalMerge', () {
    test('includes version-gated global when read', () {
      expect(
        includeGlobalInInstantModalMerge({
          'type': 'instant',
          'user_read': true,
          'data': {'target_version': '2.0.21'},
        }),
        isTrue,
      );
    });

    test('excludes read welcome global', () {
      expect(
        includeGlobalInInstantModalMerge({
          'type': 'instant',
          'user_read': true,
          'subtype': 'welcome',
        }),
        isFalse,
      );
    });
  });

  tearDown(AppVersionHelper.resetCacheForTests);
}
