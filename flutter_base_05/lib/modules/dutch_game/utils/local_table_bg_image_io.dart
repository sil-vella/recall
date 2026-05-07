import 'dart:io';

import 'package:flutter/material.dart';

bool localTableBackGraphicCached(String absolutePath) {
  if (absolutePath.isEmpty) return false;
  return File(absolutePath).existsSync();
}

/// Full-bleed table back-graphic from filesystem (Android/iOS/desktop only).
Widget localTableBgImageFile(String absolutePath, {BoxFit fit = BoxFit.cover}) {
  final f = File(absolutePath);
  if (!f.existsSync()) {
    return const SizedBox.shrink();
  }
  return Image.file(
    f,
    fit: fit,
    errorBuilder: (context, _, __) => const SizedBox.shrink(),
  );
}
