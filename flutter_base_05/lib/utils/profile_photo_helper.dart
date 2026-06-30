import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Bundled avatar when the user has not uploaded a profile photo (Android 12 splash icon).
const String kDefaultProfilePictureAsset = 'assets/images/splash_android12_icon.png';

bool isBundledProfilePictureAsset(String? value) {
  final trimmed = value?.trim();
  return trimmed != null &&
      trimmed.isNotEmpty &&
      trimmed.startsWith('assets/');
}

bool isRemoteProfilePictureUrl(String? value) {
  final trimmed = value?.trim();
  return trimmed != null &&
      trimmed.isNotEmpty &&
      !isBundledProfilePictureAsset(trimmed);
}

/// Value for login state / SharedPreferences when no server picture exists.
String resolveProfilePictureStoredValue(String? remoteOrStored) {
  if (isRemoteProfilePictureUrl(remoteOrStored)) {
    return remoteOrStored!.trim();
  }
  return kDefaultProfilePictureAsset;
}

/// Splits a stored login value into network URL vs bundled asset for [DutchAvatar].
ProfilePictureDisplay resolveProfilePictureDisplay(
  String? stored, {
  String? cacheBustVersion,
}) {
  final resolved = resolveProfilePictureStoredValue(stored);
  if (isBundledProfilePictureAsset(resolved)) {
    return ProfilePictureDisplay(assetPath: resolved);
  }
  var url = resolved;
  final version = cacheBustVersion?.trim();
  if (version != null && version.isNotEmpty) {
    url =
        '$url${url.contains('?') ? '&' : '?'}v=${Uri.encodeQueryComponent(version)}';
  }
  return ProfilePictureDisplay(imageUrl: url);
}

class ProfilePictureDisplay {
  const ProfilePictureDisplay({this.imageUrl, this.assetPath});

  final String? imageUrl;
  final String? assetPath;
}

/// Matches server default [AVATAR_MAX_UPLOAD_BYTES] (5 MiB).
const int kProfileAvatarMaxUploadBytes = 5242880;

/// Fits image inside this box; aspect ratio preserved (same semantics as server `thumbnail(w,h)`).
const int kProfileAvatarMaxEdgePx = 100;

/// Decode, resize to fit inside [kProfileAvatarMaxEdgePx]×[kProfileAvatarMaxEdgePx], encode JPEG.
Uint8List? prepareProfilePhotoForUpload(Uint8List raw) {
  if (raw.isEmpty) return null;
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  var work = decoded;
  if (work.width > kProfileAvatarMaxEdgePx || work.height > kProfileAvatarMaxEdgePx) {
    if (work.width >= work.height) {
      work = img.copyResize(work, width: kProfileAvatarMaxEdgePx, interpolation: img.Interpolation.linear);
    } else {
      work = img.copyResize(work, height: kProfileAvatarMaxEdgePx, interpolation: img.Interpolation.linear);
    }
  }
  return Uint8List.fromList(img.encodeJpg(work, quality: 85));
}
