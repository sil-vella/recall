import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

bool _devLogEnabled() {
  const s = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
  final fromDefine = s.toLowerCase().trim();
  if (fromDefine == '1' ||
      fromDefine == 'true' ||
      fromDefine == 'yes') {
    return true;
  }
  return kDebugMode;
}

void devLog(String message) {
  if (!_devLogEnabled()) return;
  debugPrint('[dev] $message');
}
