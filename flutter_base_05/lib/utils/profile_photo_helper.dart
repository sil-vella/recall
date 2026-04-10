import 'dart:typed_data';

import 'package:image/image.dart' as img;

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
