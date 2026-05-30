import 'dutch_share_moment.dart';
import 'dutch_share_platform.dart';
import 'dutch_share_template.dart';

/// SSOT for celebration share assets under `assets/share/`.
///
/// Drop your templates here (paths below). Each moment has per-platform files:
/// - **Facebook:** image + store link text only
/// - **TikTok:** video + caption (includes store URL)
///
/// ```
/// assets/share/win/facebook.webp
/// assets/share/win/tiktok.mp4
/// assets/share/level_up/facebook.webp
/// assets/share/level_up/tiktok.mp4
/// assets/share/rank_up/facebook.webp
/// assets/share/rank_up/tiktok.mp4
/// ```
class DutchShareTemplateCatalog {
  DutchShareTemplateCatalog._();

  static const Map<DutchShareMoment, Map<DutchSharePlatform, DutchShareTemplate>>
      _byMoment = {
    DutchShareMoment.win: {
      DutchSharePlatform.facebook: DutchShareTemplate(
        assetPath: 'assets/share/win/facebook.webp',
        mediaKind: DutchShareMediaKind.image,
        textKind: DutchShareTextKind.storeLink,
      ),
      DutchSharePlatform.tiktok: DutchShareTemplate(
        assetPath: 'assets/share/win/tiktok.mp4',
        mediaKind: DutchShareMediaKind.video,
        textKind: DutchShareTextKind.tiktokCaption,
      ),
    },
    DutchShareMoment.levelUp: {
      DutchSharePlatform.facebook: DutchShareTemplate(
        assetPath: 'assets/share/level_up/facebook.webp',
        mediaKind: DutchShareMediaKind.image,
        textKind: DutchShareTextKind.storeLink,
      ),
      DutchSharePlatform.tiktok: DutchShareTemplate(
        assetPath: 'assets/share/level_up/tiktok.mp4',
        mediaKind: DutchShareMediaKind.video,
        textKind: DutchShareTextKind.tiktokCaption,
      ),
    },
    DutchShareMoment.rankUp: {
      DutchSharePlatform.facebook: DutchShareTemplate(
        assetPath: 'assets/share/rank_up/facebook.webp',
        mediaKind: DutchShareMediaKind.image,
        textKind: DutchShareTextKind.storeLink,
      ),
      DutchSharePlatform.tiktok: DutchShareTemplate(
        assetPath: 'assets/share/rank_up/tiktok.mp4',
        mediaKind: DutchShareMediaKind.video,
        textKind: DutchShareTextKind.tiktokCaption,
      ),
    },
  };

  static List<DutchSharePlatform> platformsFor(DutchShareMoment moment) {
    final map = _byMoment[moment];
    if (map == null) return const [];
    return DutchSharePlatform.values.where(map.containsKey).toList();
  }

  static DutchShareTemplate? templateFor({
    required DutchShareMoment moment,
    required DutchSharePlatform platform,
  }) {
    return _byMoment[moment]?[platform];
  }
}
