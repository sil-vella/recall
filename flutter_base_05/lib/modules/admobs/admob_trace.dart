import 'package:flutter/foundation.dart';

/// Flip to `true` to print `[AdMob/…]` lines again (`flutter run` / logcat).
const bool kAdMobVerboseTrace = false;

/// Console-only traces for AdMob debugging. Off by default (see [kAdMobVerboseTrace]).
void admobTrace(String tag, String message) {
  if (kIsWeb || !kDebugMode || !kAdMobVerboseTrace) return;
  debugPrint('[AdMob/$tag] $message');
}
