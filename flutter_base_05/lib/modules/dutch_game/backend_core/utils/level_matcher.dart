import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../utils/consts/config.dart';

/// Room **game table** tier: titles, fees, gates, styles — backed by declarative catalog
/// (offline tier colors + persisted server JSON from get-user-stats; back art from URLs / disk cache).
/// Sibling [special_events] rows describe special-match presets (stable string [id]s, not tier levels).
///
/// This is the room's `game_level`, not the user's progression level in `modules.dutch_game`.
class LevelMatcher {
  LevelMatcher._();

  /// Increments whenever [applyTableTiersDocument] applies a declarative catalog (prefs or API response).
  /// Quick Join and other widgets can listen so [special_events] appear after async hydration.
  static final ValueNotifier<int> catalogChangeVersion = ValueNotifier<int>(0);

  static void _touchCatalogConsumers() {
    catalogChangeVersion.value++;
  }

  static const String _builtinJson = r'''{"schema_version":1,"special_events":[],"tiers":[
{"level":1,"title":"Home Table","coin_fee":25,"min_user_level":1,"style":{"felt_hex":"#4E8065","spotlight_hex":"#FFD4A3"}},
{"level":2,"title":"Local Table","coin_fee":50,"min_user_level":2,"style":{"felt_hex":"#514E80","spotlight_hex":"#FFD4A3"}},
{"level":3,"title":"Town Table","coin_fee":100,"min_user_level":3,"style":{"felt_hex":"#994C59","spotlight_hex":"#FFD4A3"}},
{"level":4,"title":"City Table","coin_fee":200,"min_user_level":4,"style":{"felt_hex":"#734E80","spotlight_hex":"#FFD4A3"}}]}''';

  static Map<int, Map<String, dynamic>> _tablesConfig = {};
  static List<int> _levelOrder = [];
  /// Declarative special-event / match rows (distinct string [id]s, not tier levels).
  static List<Map<String, dynamic>> _specialEvents = [];

  /// Cached full-bleed graphics downloaded from CDN, absolute paths.
  static final Map<int, String> _localGraphicPathByLevel = {};
  static final Map<String, String> _localGraphicPathByEventId = {};

  static final RegExp _eventIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  static Map<int, Map<String, dynamic>> _parseLegacyDefineMap(Map<dynamic, dynamic> decoded) {
    final out = <int, Map<String, dynamic>>{};
    decoded.forEach((k, v) {
      final lvl = int.tryParse(k.toString());
      if (lvl == null || v is! Map) return;
      final title = (v['title'] ?? '').toString().trim();
      final fee = int.tryParse((v['coin_fee'] ?? '').toString());
      final minUserLevel = int.tryParse((v['min_user_level'] ?? lvl).toString());
      if (title.isEmpty || fee == null || minUserLevel == null) return;
      out[lvl] = Map<String, dynamic>.from({
        'title': title,
        'coin_fee': fee,
        'min_user_level': minUserLevel,
      });
    });
    return out;
  }

  static void _rebuildLegacyOrderFromKeys() {
    _levelOrder = _tablesConfig.keys.toList()..sort();
    for (final e in _tablesConfig.entries) {
      if (e.value['style'] == null) {
        e.value['style'] = _defaultStyleFallbackForLevel(e.key);
      }
    }
  }

  /// When tiers lack `style`, use same palette as bundled fallback (graphics come from API URL + cache).
  static Map<String, dynamic> _defaultStyleFallbackForLevel(int level) {
    String feltHex;
    switch (level) {
      case 2:
        feltHex = '#514E80';
        break;
      case 3:
        feltHex = '#994C59';
        break;
      case 4:
        feltHex = '#734E80';
        break;
      case 1:
      default:
        feltHex = '#4E8065';
        break;
    }
    return {
      'felt_hex': feltHex,
      'spotlight_hex': '#FFD4A3',
    };
  }

  static void _applyNormalizedTiers(Map<String, dynamic> doc) {
    final tiersRaw = doc['tiers'];
    if (tiersRaw is! List) {
      return;
    }
    final nextConfig = <int, Map<String, dynamic>>{};
    final order = <int>[];
    for (final raw in tiersRaw) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final lvlRaw = m['level'];
      final lvl = lvlRaw is int ? lvlRaw : int.tryParse('$lvlRaw');
      if (lvl == null || lvl < 1) continue;
      final title = (m['title'] ?? '').toString().trim();
      final feeRaw = m['coin_fee'];
      final fee = feeRaw is int ? feeRaw : int.tryParse('$feeRaw');
      final minUr = m['min_user_level'];
      final minU = minUr is int ? minUr : int.tryParse('${minUr ?? lvl}') ?? lvl;
      if (title.isEmpty || fee == null || fee < 1 || minU < 1) continue;
      Map<String, dynamic>? styleMap;
      final rsStyle = m['style'];
      if (rsStyle is Map) {
        styleMap = Map<String, dynamic>.from(rsStyle);
      } else {
        styleMap = _defaultStyleFallbackForLevel(lvl);
      }
      nextConfig[lvl] = {
        'title': title,
        'coin_fee': fee,
        'min_user_level': minU,
        'style': styleMap,
      };
      order.add(lvl);
    }
    _tablesConfig = nextConfig;
    _levelOrder = order;
    _purgeStaleGraphicOverrides();
  }

  static void _applySpecialEvents(Map<String, dynamic> doc) {
    // Omitting ``special_events`` from a merged doc must not wipe a previously hydrated list
    // (backward compatibility with stale prefs / partial payloads).
    if (!doc.containsKey('special_events')) {
      return;
    }
    final raw = doc['special_events'];
    if (raw is! List) {
      _specialEvents = [];
      _localGraphicPathByEventId.clear();
      return;
    }
    final next = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id =
          ((m['id'] ?? m['event_id']) ?? '').toString().trim();
      if (id.isEmpty || !_eventIdPattern.hasMatch(id) || seen.contains(id)) {
        continue;
      }
      final title = (m['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      seen.add(id);
      next.add(m);
    }
    _specialEvents = next;
    _localGraphicPathByEventId.removeWhere((id, _) => !seen.contains(id));
  }

  static void _purgeStaleGraphicOverrides() {
    final keep = Set<int>.from(_tablesConfig.keys);
    _localGraphicPathByLevel.removeWhere((k, _) => !keep.contains(k));
  }

  /// Replace runtime catalog ([levelOrder] preserves server array order).
  static void applyTableTiersDocument(Map<String, dynamic> doc, {bool clearDownloadedGraphics = true}) {
    if (clearDownloadedGraphics) {
      _localGraphicPathByLevel.clear();
      _localGraphicPathByEventId.clear();
    }
    final incoming = Map<String, dynamic>.from(doc);
    _applyNormalizedTiers(incoming);
    if (_levelOrder.isEmpty) {
      _applyNormalizedTiers(jsonDecode(_builtinJson) as Map<String, dynamic>);
    }
    _applySpecialEvents(incoming);
    _touchCatalogConsumers();
  }

  /// Optional override at build time: `--dart-define=DUTCH_TABLES_JSON=...` legacy map keyed by `"1"`..`"4"`.
  static void seedFromDartDefineIfPresent() {
    final raw = Config.dutchTablesJson.trim();
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded.containsKey('tiers')) {
        applyTableTiersDocument(decoded, clearDownloadedGraphics: true);
      } else if (decoded is Map) {
        final legacy = _parseLegacyDefineMap(Map<dynamic, dynamic>.from(decoded));
        if (legacy.isEmpty) return;
        _tablesConfig = {
          for (final e in legacy.entries)
            e.key: {
              ...e.value,
              'style': _defaultStyleFallbackForLevel(e.key),
            },
        };
        _rebuildLegacyOrderFromKeys();
        _localGraphicPathByLevel.clear();
        _specialEvents = [];
        _localGraphicPathByEventId.clear();
      }
    } catch (_) {}
  }

  static void resetToBuiltin() {
    applyTableTiersDocument(jsonDecode(_builtinJson) as Map<String, dynamic>);
  }

  /// Load bundled + dart-define layering (dart-define wins when parseable).
  static void ensureHydratedMinimal() {
    if (_tablesConfig.isNotEmpty) return;
    applyTableTiersDocument(jsonDecode(_builtinJson) as Map<String, dynamic>);
    seedFromDartDefineIfPresent();
  }

  /// After downloading a tier back-graphic into a local absolute path.
  static void setLocalGraphicPath(int level, String absolutePath) {
    if (absolutePath.isEmpty) {
      _localGraphicPathByLevel.remove(level);
      return;
    }
    _localGraphicPathByLevel[level] = absolutePath;
  }

  static String? localGraphicPathForLevel(int level) => _localGraphicPathByLevel[level];

  static List<Map<String, dynamic>> get specialEvents {
    ensureHydratedMinimal();
    return List<Map<String, dynamic>>.unmodifiable(_specialEvents);
  }

  static Map<String, dynamic>? specialEventRowById(String rawId) {
    ensureHydratedMinimal();
    final id = rawId.trim();
    if (id.isEmpty || !_eventIdPattern.hasMatch(id)) return null;
    for (final row in _specialEvents) {
      final rid = (row['id'] ?? row['event_id'] ?? '').toString().trim();
      if (rid == id) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  /// Shallow copy of ``metadata.end_match_modal`` for end-of-match UI (may include server-injected URLs).
  static Map<String, dynamic>? endMatchModalSnapshotForSpecialEventId(String rawId) {
    final row = specialEventRowById(rawId);
    if (row == null) return null;
    final meta = row['metadata'];
    if (meta is! Map) return null;
    final em = meta['end_match_modal'];
    if (em is! Map) return null;
    return Map<String, dynamic>.from(em.map((k, v) => MapEntry(k.toString(), v)));
  }

  static void setLocalEventGraphicPath(String eventId, String absolutePath) {
    final id = eventId.trim();
    if (id.isEmpty || !_eventIdPattern.hasMatch(id)) {
      return;
    }
    if (absolutePath.isEmpty) {
      _localGraphicPathByEventId.remove(id);
      return;
    }
    _localGraphicPathByEventId[id] = absolutePath;
  }

  static String? localGraphicPathForEvent(String eventId) {
    final id = eventId.trim();
    return _localGraphicPathByEventId[id];
  }

  /// `style` map for tier, merged with fallback.
  static Map<String, dynamic> styleForLevel(int level) {
    ensureHydratedMinimal();
    final row = _tablesConfig[level];
    final st = row?['style'];
    if (st is Map<String, dynamic>) return st;
    if (st is Map) return Map<String, dynamic>.from(st);
    return _defaultStyleFallbackForLevel(level);
  }

  static Map<int, String> get levelToTitleMap => {
        for (final e in _tablesConfig.entries) e.key: e.value['title'] as String,
      };

  static Map<int, int> get levelToCoinFeeMap => {
        for (final e in _tablesConfig.entries) e.key: e.value['coin_fee'] as int,
      };

  static Map<int, int> get tableLevelToMinUserLevelMap => {
        for (final e in _tablesConfig.entries) e.key: e.value['min_user_level'] as int,
      };

  static List<int> get levelOrder {
    ensureHydratedMinimal();
    return List<int>.unmodifiable(_levelOrder);
  }

  static int get minConfiguredTableLevel =>
      levelOrder.isEmpty ? 1 : levelOrder.reduce((a, b) => a < b ? a : b);

  static int get maxConfiguredTableLevel =>
      levelOrder.isEmpty ? 4 : levelOrder.reduce((a, b) => a > b ? a : b);

  static String levelToTitle(int? level, {String? defaultTitle}) {
    ensureHydratedMinimal();
    if (level == null) {
      return defaultTitle ?? '';
    }
    return levelToTitleMap[level] ?? defaultTitle ?? '';
  }

  static int? titleToLevel(String? title) {
    ensureHydratedMinimal();
    if (title == null || title.isEmpty) {
      return null;
    }
    final normalized = title.trim().toLowerCase();
    for (final entry in levelToTitleMap.entries) {
      if (entry.value.toLowerCase() == normalized) {
        return entry.key;
      }
    }
    return null;
  }

  static int levelToCoinFee(int? level, {int? defaultFee}) {
    ensureHydratedMinimal();
    if (level == null) {
      return defaultFee ?? 0;
    }
    return levelToCoinFeeMap[level] ?? defaultFee ?? 0;
  }

  static int tableLevelToCoinFee(int? roomTableLevel, {int? defaultFee}) {
    return levelToCoinFee(roomTableLevel, defaultFee: defaultFee);
  }

  static int tableLevelToRequiredUserLevel(int? roomTableLevel, {int? defaultLevel}) {
    ensureHydratedMinimal();
    if (roomTableLevel == null) {
      return defaultLevel ?? 1;
    }
    return tableLevelToMinUserLevelMap[roomTableLevel] ?? defaultLevel ?? 1;
  }

  static bool isValidLevel(int? level) {
    ensureHydratedMinimal();
    return level != null && levelToTitleMap.containsKey(level);
  }

  static List<String> get allTitles => levelOrder.map((l) => levelToTitleMap[l]!).toList();
}
