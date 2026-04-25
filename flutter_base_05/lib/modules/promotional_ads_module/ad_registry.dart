import 'models/ad_event_type_config.dart';
import 'models/ad_registration.dart';

/// In-memory registry: types by id, ads by type, round-robin cursors.
class AdRegistry {
  AdRegistry._();

  static final AdRegistry instance = AdRegistry._();

  final Map<String, AdEventTypeConfig> _typesById = {};
  final Map<String, List<AdRegistration>> _adsByTypeId = {};
  final Map<String, int> _roundRobinIndex = {};

  void clear() {
    _typesById.clear();
    _adsByTypeId.clear();
    _roundRobinIndex.clear();
  }

  void registerType(AdEventTypeConfig config) {
    _typesById[config.id] = config;
    _adsByTypeId.putIfAbsent(config.id, () => []);
  }

  void registerAd(AdRegistration ad) {
    _adsByTypeId.putIfAbsent(ad.adTypeId, () => []);
    _adsByTypeId[ad.adTypeId]!.add(ad);
  }

  AdEventTypeConfig? typeById(String id) => _typesById[id];

  AdEventTypeConfig? typeByHookName(String hookName) {
    for (final t in _typesById.values) {
      if (t.hookName == hookName) {
        return t;
      }
    }
    return null;
  }

  /// Next ad for [typeId] using round-robin (only strategy implemented).
  AdRegistration? pickNextForType(String typeId) {
    final cfg = _typesById[typeId];
    if (cfg == null) {
      return null;
    }
    if (cfg.selectionStrategy != 'round_robin') {
      // Reserved: fall back to round-robin until implemented.
    }
    final list = _adsByTypeId[typeId];
    if (list == null || list.isEmpty) {
      return null;
    }
    final i = _roundRobinIndex[typeId] ?? 0;
    final ad = list[i % list.length];
    _roundRobinIndex[typeId] = i + 1;
    return ad;
  }

  /// Randomize the ad order for each type once per app load.
  ///
  /// This keeps runtime selection as round-robin, but starts from a randomized
  /// order so users do not always see the same first ad after app restart.
  void shuffleAdsPerType() {
    for (final entry in _adsByTypeId.entries) {
      entry.value.shuffle();
      _roundRobinIndex[entry.key] = 0;
    }
  }
}
