/// One registered promotional ad (linked to a type).
class AdRegistration {
  AdRegistration({
    required this.id,
    required this.adTypeId,
    required this.link,
    this.title,
    this.imageFile,
    this.videoFile,
    this.networkImageUrl,
    this.networkVideoUrl,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  /// Legacy asset root when not using network URLs ([imageFile], [videoFile]).
  static const String advertsAssetDir = 'assets/adverts/';

  final String id;
  final String adTypeId;
  final String link;
  final String? title;

  /// File name (or path under [advertsAssetDir]) for an image asset.
  final String? imageFile;

  /// File name (or path under [advertsAssetDir]) for a video asset.
  final String? videoFile;

  /// When set (server-driven ads), prefer this URL for the image instead of [imageAssetPath].
  final String? networkImageUrl;

  /// When set (server-driven ads), prefer this URL for video instead of [videoAssetPath].
  final String? networkVideoUrl;

  final Map<String, dynamic> extra;

  /// Full Flutter asset path for [imageFile], or null when using [networkImageUrl].
  String? get imageAssetPath =>
      (networkImageUrl != null && networkImageUrl!.isNotEmpty) ? null : _resolveAssetPath(imageFile);

  /// Full Flutter asset path for [videoFile], or null when using [networkVideoUrl].
  String? get videoAssetPath =>
      (networkVideoUrl != null && networkVideoUrl!.isNotEmpty) ? null : _resolveAssetPath(videoFile);

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
        if (networkImageUrl != null && networkImageUrl!.isNotEmpty) 'image_network': networkImageUrl,
        if (networkVideoUrl != null && networkVideoUrl!.isNotEmpty) 'video_network': networkVideoUrl,
        if (imageAssetPath != null) 'image_asset': imageAssetPath,
        if (videoAssetPath != null) 'video_asset': videoAssetPath,
        ...extra,
      };

  static AdRegistration fromYamlMap(
    Map<dynamic, dynamic> m, {
    String? remoteMediaBaseUrl,
  }) {
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

    String? netImg;
    String? netVid;
    if (remoteMediaBaseUrl != null && remoteMediaBaseUrl.isNotEmpty) {
      final base = remoteMediaBaseUrl.replaceAll(RegExp(r'/$'), '');
      if (imageFile != null && imageFile.isNotEmpty) {
        netImg = '$base/$imageFile';
      }
      if (videoFile != null && videoFile.isNotEmpty) {
        netVid = '$base/$videoFile';
      }
    }

    return AdRegistration(
      id: id,
      adTypeId: typeId,
      link: link,
      title: title,
      imageFile: (imageFile != null && imageFile.isNotEmpty) ? imageFile : null,
      videoFile: (videoFile != null && videoFile.isNotEmpty) ? videoFile : null,
      networkImageUrl: netImg,
      networkVideoUrl: netVid,
      extra: extra,
    );
  }
}
