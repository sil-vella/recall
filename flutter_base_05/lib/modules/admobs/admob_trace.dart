import 'package:flutter/foundation.dart';

/// Console-only traces for AdMob debugging (`flutter run` / Xcode / Logcat).
/// No-op on web and in non-debug builds.
void admobTrace(String tag, String message) {
  if (kIsWeb || !kDebugMode) return;
  debugPrint('[AdMob/$tag] $message');
}
