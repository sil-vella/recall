import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

bool _customlogEnabled() {
  const s = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
  final fromDefine = s.toLowerCase().trim();
  if (fromDefine == '1' ||
      fromDefine == 'true' ||
      fromDefine == 'yes') {
    return true;
  }
  return kDebugMode;
}

void customlog(String message) {
  if (!_customlogEnabled()) return;
  debugPrint('[dev] $message');
}
