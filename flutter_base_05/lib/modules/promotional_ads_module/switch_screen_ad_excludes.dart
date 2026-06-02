import 'ad_registry.dart';

/// Paths that must not count toward interstitial navigation or show an interstitial on entry.
///
/// Always includes [bundledDefaults]; merges server `exclude_from_screen_change_count` when present.
abstract final class SwitchScreenAdExcludes {
  static const List<String> bundledDefaults = [
    '/dutch/game-play',
    '/coin-purchase',
    '/update-required',
    '/admin*',
  ];

  static List<String> resolve() {
    final fromRegistry =
        AdRegistry.instance.typeById('switch_screen')?.excludeFromScreenChangeCount ??
        const <String>[];
    return <String>{...bundledDefaults, ...fromRegistry}.toList();
  }
}
