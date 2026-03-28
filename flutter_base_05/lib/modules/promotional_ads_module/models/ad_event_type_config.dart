/// Config for one ad event type (placement + rules).
class AdEventTypeConfig {
  AdEventTypeConfig({
    required this.id,
    required this.hookName,
    required this.selectionStrategy,
    this.delayBeforeSkipSeconds,
  });

  final String id;
  final String hookName;

  /// `round_robin` | `weighted` | `single_active` — only round_robin implemented.
  final String selectionStrategy;

  /// For interstitial-style types (e.g. switch screen): seconds before Skip is enabled.
  final int? delayBeforeSkipSeconds;

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
    return AdEventTypeConfig(
      id: id,
      hookName: hookName,
      selectionStrategy: strategy.isEmpty ? 'round_robin' : strategy,
      delayBeforeSkipSeconds: delay,
    );
  }
}
