import 'package:dutch/modules/dutch_game/utils/dutch_direct_share_channel.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_share_helper.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_share_method.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_share_moment.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_share_package_names.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_share_platform.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_share_template_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testStore = 'https://example.com/app';

  tearDown(() {
    DutchDirectShareChannel.testShareHandler = null;
    DutchDirectShareChannel.testIsInstalledHandler = null;
    DutchDirectShareChannel.testResolveTikTokHandler = null;
  });

  group('DutchShareTemplateCatalog', () {
    test('defines facebook and tiktok for each moment', () {
      for (final moment in DutchShareMoment.values) {
        final platforms = DutchShareTemplateCatalog.platformsFor(moment);
        expect(platforms, contains(DutchSharePlatform.facebook));
        expect(platforms, contains(DutchSharePlatform.tiktok));
      }
    });

    test('win facebook uses image and store link', () {
      final t = DutchShareTemplateCatalog.templateFor(
        moment: DutchShareMoment.win,
        platform: DutchSharePlatform.facebook,
      );
      expect(t, isNotNull);
      expect(t!.assetPath, 'assets/share/win/facebook.webp');
      expect(t.mediaKind.name, 'image');
      expect(t.textKind.name, 'storeLink');
    });

    test('win tiktok uses video and caption', () {
      final t = DutchShareTemplateCatalog.templateFor(
        moment: DutchShareMoment.win,
        platform: DutchSharePlatform.tiktok,
      );
      expect(t, isNotNull);
      expect(t!.assetPath, 'assets/share/win/tiktok.mp4');
      expect(t.mediaKind.name, 'video');
      expect(t.textKind.name, 'tiktokCaption');
    });
  });

  group('DutchShareHelper.shareTextFor', () {
    test('facebook text is store URL only', () {
      expect(
        DutchShareHelper.shareTextFor(
          textKind: DutchShareTextKind.storeLink,
          storeUrlOverride: testStore,
        ),
        testStore,
      );
    });

    test('tiktok caption includes store URL', () {
      final text = DutchShareHelper.shareTextFor(
        textKind: DutchShareTextKind.tiktokCaption,
        storeUrlOverride: testStore,
      );
      expect(text, contains(testStore));
      expect(text, contains('Play Dutch Card Game'));
    });
  });

  group('DutchSharePackageNames', () {
    test('facebook package matches Android manifest query', () {
      expect(
        DutchSharePackageNames.packageFor(DutchSharePlatform.facebook),
        'com.facebook.katana',
      );
    });

    test('supports direct android for facebook and tiktok', () {
      expect(
        DutchSharePackageNames.supportsDirectAndroidShare(
          DutchSharePlatform.facebook,
        ),
        isTrue,
      );
      expect(
        DutchSharePackageNames.supportsDirectAndroidShare(
          DutchSharePlatform.tiktok,
        ),
        isTrue,
      );
    });

    test('tiktok package list matches Kotlin handler order', () {
      expect(
        DutchSharePackageNames.tiktokPackages,
        [
          'com.zhiliaoapp.musically',
          'com.ss.android.ugc.trill',
        ],
      );
    });
  });

  group('DutchDirectShareChannel test hooks', () {
    test('resolvePackageForPlatform returns facebook when installed', () async {
      DutchDirectShareChannel.testIsInstalledHandler = (pkg) async {
        return pkg == DutchSharePackageNames.facebook;
      };
      final resolved = await DutchDirectShareChannel.resolvePackageForPlatform(
        DutchSharePlatform.facebook,
      );
      expect(resolved, DutchSharePackageNames.facebook);
    });

    test('resolvePackageForPlatform uses tiktok resolver', () async {
      DutchDirectShareChannel.testResolveTikTokHandler = () async {
        return DutchSharePackageNames.tiktokTrill;
      };
      final resolved = await DutchDirectShareChannel.resolvePackageForPlatform(
        DutchSharePlatform.tiktok,
      );
      expect(resolved, DutchSharePackageNames.tiktokTrill);
    });

    test('shareToApp returns appNotInstalled from test handler', () async {
      DutchDirectShareChannel.testShareHandler =
          ({required packageName, required filePath, required mimeType, text}) async {
        return DutchDirectShareStatus.appNotInstalled;
      };
      final status = await DutchDirectShareChannel.shareToApp(
        packageName: DutchSharePackageNames.facebook,
        filePath: '/tmp/x.png',
        mimeType: 'image/png',
        text: testStore,
      );
      expect(status, DutchDirectShareStatus.appNotInstalled);
    });
  });

  group('DutchShareMethod', () {
    test('defines analytics share_method values', () {
      expect(DutchShareMethod.directAndroid, 'direct_android');
      expect(DutchShareMethod.sharePlus, 'share_plus');
      expect(DutchShareMethod.linkOnly, 'link_only');
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
