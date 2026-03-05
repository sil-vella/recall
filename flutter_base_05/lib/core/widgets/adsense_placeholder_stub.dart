import 'package:flutter/material.dart';

/// Stub for non-web: no AdSense registration or placeholder.
void registerAdSenseViewFactories() {}

/// Stub: no AdSense slots on non-web.
bool get hasTopAdSlot => false;
bool get hasBottomAdSlot => false;

/// Stub: no banner on non-web (AdMob is used via BannerAdModule instead).
Widget buildAdSensePlaceholder(String slot) => const SizedBox.shrink();
