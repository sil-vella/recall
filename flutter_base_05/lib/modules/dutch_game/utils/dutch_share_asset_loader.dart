import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'dutch_share_platform.dart';
import 'dutch_share_template.dart';

/// Copies a Flutter asset bundle file to a temp path for [share_plus].
class DutchShareAssetLoader {
  DutchShareAssetLoader._();

  static Future<File?> copyAssetToTempFile(String assetPath) async {
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) return null;

      final dot = assetPath.lastIndexOf('.');
      final ext = dot >= 0 ? assetPath.substring(dot) : '';
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/dutch_share_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  static String? mimeTypeForTemplate(DutchShareTemplate template) {
    final path = template.assetPath.toLowerCase();
    switch (template.mediaKind) {
      case DutchShareMediaKind.image:
        if (path.endsWith('.png')) return 'image/png';
        if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
          return 'image/jpeg';
        }
        if (path.endsWith('.webp')) return 'image/webp';
        return 'image/*';
      case DutchShareMediaKind.video:
        if (path.endsWith('.mp4')) return 'video/mp4';
        if (path.endsWith('.mov')) return 'video/quicktime';
        return 'video/*';
    }
  }
}
