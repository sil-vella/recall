/// Social destination for celebration share templates.
enum DutchSharePlatform {
  facebook,
  tiktok,
}

extension DutchSharePlatformLabels on DutchSharePlatform {
  String get label {
    switch (this) {
      case DutchSharePlatform.facebook:
        return 'Facebook';
      case DutchSharePlatform.tiktok:
        return 'TikTok';
    }
  }

  String get analyticsValue => name;
}

/// Bundled media type for a share template.
enum DutchShareMediaKind {
  image,
  video,
}

/// How accompanying share-sheet text is built for a template.
enum DutchShareTextKind {
  /// Store download URL only (e.g. Facebook link text).
  storeLink,

  /// Short caption including the store URL (e.g. TikTok).
  tiktokCaption,
}
