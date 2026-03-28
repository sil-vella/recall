/// Config for one ad event type (placement + rules).
class AdEventTypeConfig {
  AdEventTypeConfig({
    required this.id,
    required this.hookName,
    required this.selectionStrategy,
    this.delayBeforeSkipSeconds,
    this.showAfterScreenChanges,
    this.excludeFromScreenChangeCount = const [],
    this.bannerSwitch,
  });

  final String id;
  final String hookName;

  /// `round_robin` | `weighted` | `single_active` — only round_robin implemented.
  final String selectionStrategy;

  /// For interstitial-style types (e.g. switch screen): seconds before Skip is enabled.
  final int? delayBeforeSkipSeconds;

  /// For [id] `switch_screen`: how many qualifying [PageRoute] navigations before
  /// showing the interstitial (then the internal counter resets). Default 3 when unset.
  final int? showAfterScreenChanges;

  /// Paths that do not increment the screen-change counter when navigated **to** (see YAML).
  final List<String> excludeFromScreenChangeCount;

  /// YAML key `switch`. For `bottom_banner_promo`: `sponsors` (YAML strip) or `admob` (AdMob / AdSense).
  final String? bannerSwitch;

  static AdEventTypeConfig fromYamlMap(Map<dynamic, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final hookName = m['hook_name']?.toString() ?? '';
    final strategy = (m['selection_strategy']?.toString() ?? 'round_robin').trim();
    final delayStr = m['delay_before_skip_seconds'];
    int? delay;
    if (delayStr != null) {
      if (delayStr is int) {
        delay = delayStr;
      } else {
        delay = int.tryParse(delayStr.toString());
      }
    }
    final showAfterStr = m['show_after_screen_changes'];
    int? showAfter;
    if (showAfterStr != null) {
      if (showAfterStr is int) {
        showAfter = showAfterStr;
      } else {
        showAfter = int.tryParse(showAfterStr.toString());
      }
    }
    final excludeRaw = m['exclude_from_screen_change_count'];
    final excludeList = <String>[];
    if (excludeRaw is List) {
      for (final e in excludeRaw) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) {
          excludeList.add(s);
        }
      }
    }
    final switchRaw = m['switch'];
    String? bannerSwitch;
    if (switchRaw != null) {
      final t = switchRaw.toString().trim();
      if (t.isNotEmpty) {
        bannerSwitch = t;
      }
    }
    return AdEventTypeConfig(
      id: id,
      hookName: hookName,
      selectionStrategy: strategy.isEmpty ? 'round_robin' : strategy,
      delayBeforeSkipSeconds: delay,
      showAfterScreenChanges: showAfter,
      excludeFromScreenChangeCount: excludeList,
      bannerSwitch: bannerSwitch,
    );
  }
}
