import 'package:flutter/foundation.dart';

/// Console-only traces for AdMob debugging (`flutter run` / Xcode / Logcat).
/// Unlike [dbg]/[dbgAdMob], this is **not** gated on `VERBOSE_DEV_LOGS` or `ADMOB_DEBUG_LOGS`.
void admobTrace(String tag, String message) {
  if (kIsWeb || !kDebugMode) return;
  debugPrint('[AdMob/$tag] $message');
}
