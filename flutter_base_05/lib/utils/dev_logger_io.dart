import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

bool _customlogEnabled() {
  const s = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
  final fromDefine = s.toLowerCase().trim();
  if (fromDefine == '1' ||
      fromDefine == 'true' ||
      fromDefine == 'yes') {
    return true;
  }
  final v = Platform.environment['DUTCH_DEV_LOG']?.toLowerCase().trim();
  return v == '1' || v == 'true' || v == 'yes';
}

/// Writes via [debugPrint] so Android/iOS logs reach logcat / `flutter run` (not host stderr).
void customlog(String message) {
  if (!_customlogEnabled()) return;
  debugPrint('[dev] $message');
}
