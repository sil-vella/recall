import 'dutch_share_platform.dart';

/// Android package names for direct share intents (mirrors [DutchDirectShareHandler.kt]).
class DutchSharePackageNames {
  DutchSharePackageNames._();

  static const String facebook = 'com.facebook.katana';
  static const String tiktokMusically = 'com.zhiliaoapp.musically';
  static const String tiktokTrill = 'com.ss.android.ugc.trill';

  static const List<String> tiktokPackages = [
    tiktokMusically,
    tiktokTrill,
  ];

  static String packageFor(DutchSharePlatform platform) {
    switch (platform) {
      case DutchSharePlatform.facebook:
        return facebook;
      case DutchSharePlatform.tiktok:
        return tiktokMusically;
    }
  }

  /// Whether hybrid routing may use Android direct intent for this platform.
  static bool supportsDirectAndroidShare(DutchSharePlatform platform) {
    switch (platform) {
      case DutchSharePlatform.facebook:
      case DutchSharePlatform.tiktok:
        return true;
    }
  }
}
