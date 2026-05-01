import 'package:flutter/widgets.dart';

import 'dutch_anim_runtime.dart';

/// Collects hand-slot and pile rects (anchor-relative) for [DutchAnimRuntime.mergeLayout].
class DutchAnimLayoutReporter {
  DutchAnimLayoutReporter._();

  /// [slotKeysByPath] keys: `"playerId|handIndex"` → GlobalKey on that slot.
  static Map<String, dynamic> captureHandSlots(
    GlobalKey anchorKey,
    Map<String, GlobalKey> slotKeysByPath,
  ) {
    final out = <String, dynamic>{};
    for (final e in slotKeysByPath.entries) {
      final parts = e.key.split('|');
      if (parts.length != 2) continue;
      final playerId = parts[0];
      final indexStr = parts[1];
      final r = DutchAnimRuntime.rectRelativeToAnchor(e.value, anchorKey);
      if (r == null) continue;
      out.putIfAbsent(playerId, () => <String, dynamic>{});
      (out[playerId] as Map<String, dynamic>)[indexStr] = r;
    }
    return out;
  }

  static Map<String, dynamic> capturePiles(
    GlobalKey anchorKey, {
    required GlobalKey drawPileKey,
    required GlobalKey discardPileKey,
  }) {
    final piles = <String, dynamic>{};
    final draw = DutchAnimRuntime.rectRelativeToAnchor(drawPileKey, anchorKey);
    if (draw != null) piles['draw'] = draw;
    final discard = DutchAnimRuntime.rectRelativeToAnchor(discardPileKey, anchorKey);
    if (discard != null) piles['discard'] = discard;
    return piles;
  }
}
