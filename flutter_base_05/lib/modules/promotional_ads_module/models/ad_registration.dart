/// One registered promotional ad (linked to a type).
class AdRegistration {
  AdRegistration({
    required this.id,
    required this.adTypeId,
    required this.link,
    this.title,
    this.imageFile,
    this.videoFile,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  /// Root for YAML-relative media paths ([imageFile], [videoFile]).
  static const String advertsAssetDir = 'assets/adverts/';

  final String id;
  final String adTypeId;
  final String link;
  final String? title;

  /// File name (or path under [advertsAssetDir]) for an image asset.
  final String? imageFile;

  /// File name (or path under [advertsAssetDir]) for a video asset.
  final String? videoFile;
  final Map<String, dynamic> extra;

  /// Full Flutter asset path for [imageFile], or null.
  String? get imageAssetPath => _resolveAssetPath(imageFile);

  /// Full Flutter asset path for [videoFile], or null.
  String? get videoAssetPath => _resolveAssetPath(videoFile);

  static String? _resolveAssetPath(String? name) {
    if (name == null) {
      return null;
    }
    final t = name.trim();
    if (t.isEmpty) {
      return null;
    }
    if (t.startsWith('assets/')) {
      return t;
    }
    return '$advertsAssetDir$t';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'ad_type_id': adTypeId,
        'link': link,
        if (title != null) 'title': title,
        if (imageAssetPath != null) 'image_asset': imageAssetPath,
        if (videoAssetPath != null) 'video_asset': videoAssetPath,
        ...extra,
      };

  static AdRegistration fromYamlMap(Map<dynamic, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final typeId = m['ad_type_id']?.toString() ?? '';
    final link = m['link']?.toString() ?? '';
    final title = m['title']?.toString();
    final imageFile = m['image']?.toString().trim();
    final videoFile = m['video']?.toString().trim();
    final extra = <String, dynamic>{};
    m.forEach((k, v) {
      final key = k.toString();
      if (key == 'id' ||
          key == 'ad_type_id' ||
          key == 'link' ||
          key == 'title' ||
          key == 'image' ||
          key == 'video') {
        return;
      }
      extra[key] = v;
    });
    return AdRegistration(
      id: id,
      adTypeId: typeId,
      link: link,
      title: title,
      imageFile: (imageFile != null && imageFile.isNotEmpty) ? imageFile : null,
      videoFile: (videoFile != null && videoFile.isNotEmpty) ? videoFile : null,
      extra: extra,
    );
  }
}
