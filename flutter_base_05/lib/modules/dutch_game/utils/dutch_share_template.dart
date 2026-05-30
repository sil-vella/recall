import 'dutch_share_platform.dart';

/// One bundled asset + share-sheet text recipe for a moment and platform.
class DutchShareTemplate {
  const DutchShareTemplate({
    required this.assetPath,
    required this.mediaKind,
    required this.textKind,
  });

  /// Flutter asset path (drop files under `assets/share/` — see [DutchShareTemplateCatalog]).
  final String assetPath;
  final DutchShareMediaKind mediaKind;
  final DutchShareTextKind textKind;
}
