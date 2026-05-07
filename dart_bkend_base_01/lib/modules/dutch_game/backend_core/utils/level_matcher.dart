import 'dart:convert';
import 'dart:io';

import '../../../../utils/config.dart';

/// Room table tier — fees/titles/min user level loaded from declarative JSON (Flutter catalog parity).
/// Optional [special_events] entries describe special-match presets (stable string [id]s).
///
/// Resolution: [Config.DUTCH_TABLE_TIERS_PATH], [config/table_tiers.json] from cwd / script parents /
/// monorepo [dart_bkend_base_01/config], then builtin JSON, then optional [Config.DUTCH_TABLES_JSON] overlay.
class LevelMatcher {
  LevelMatcher._();

  /// Builtin tiers + one special event so `_resolveSpecialEventForRoomCreation` works when no JSON file is found.
  static const String _builtinJson = r'''{"schema_version":1,"special_events":[
{"id":"winter_duels","title":"Winter Duels","coin_fee":50,"min_user_level":2,
"metadata":{"end_match_modal":{"text":"You won 100 coins!"}}}],"tiers":[
{"level":1,"title":"Home Table","coin_fee":25,"min_user_level":1},
{"level":2,"title":"Local Table","coin_fee":50,"min_user_level":2},
{"level":3,"title":"Town Table","coin_fee":100,"min_user_level":3},
{"level":4,"title":"City Table","coin_fee":200,"min_user_level":4}]}''';

  static Map<int, Map<String, dynamic>> _tablesConfig = {};
  static List<int> _levelOrder = [];
  static List<Map<String, dynamic>> _specialEvents = [];
  static final RegExp _eventIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');
  static bool _loaded = false;
  /// True after a doc applied `special_events` as an **empty** JSON array (explicit "no events").
  static bool _specialEventsExplicitlyEmptyInDoc = false;

  static void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    _tryLoadDeclarativeFile();
    if (_levelOrder.isEmpty) {
      _applyDocument(Map<String, dynamic>.from(jsonDecode(_builtinJson) as Map));
    } else if (_specialEvents.isEmpty && !_specialEventsExplicitlyEmptyInDoc) {
      // Tier-only file (no `special_events` key) left _specialEvents empty — merge builtin events only.
      final built = Map<String, dynamic>.from(jsonDecode(_builtinJson) as Map);
      _applySpecialEvents(built);
    }
    _applyEnvOverlay();
  }

  static String _joinPath(String root, List<String> segments) {
    var s = root.endsWith(Platform.pathSeparator)
        ? root.substring(0, root.length - 1)
        : root;
    for (final seg in segments) {
      s += Platform.pathSeparator + seg;
    }
    return s;
  }

  /// Resolves [config/table_tiers.json] from env, cwd, script tree, and monorepo layout (Docker / `dart run` cwd varies).
  static List<String> _configTableTiersCandidatePaths() {
    final out = <String>[];
    void add(String? p) {
      if (p == null) return;
      final t = p.trim();
      if (t.isEmpty || out.contains(t)) return;
      out.add(t);
    }

    add(Config.DUTCH_TABLE_TIERS_PATH.trim());
    add(_joinPath('.', ['config', 'table_tiers.json']));

    try {
      var dir = File.fromUri(Platform.script).absolute.parent;
      for (var i = 0; i < 16; i++) {
        add(_joinPath(dir.path, ['config', 'table_tiers.json']));
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    } catch (_) {}

    try {
      var cwd = Directory.current.absolute;
      for (var i = 0; i < 10; i++) {
        add(_joinPath(cwd.path, ['config', 'table_tiers.json']));
        add(_joinPath(cwd.path, ['dart_bkend_base_01', 'config', 'table_tiers.json']));
        final parent = cwd.parent;
        if (parent.path == cwd.path) break;
        cwd = parent;
      }
    } catch (_) {}

    return out;
  }

  static void _tryLoadDeclarativeFile() {
    for (final path in _configTableTiersCandidatePaths()) {
      try {
        final f = File(path);
        if (!f.existsSync()) continue;
        final raw = f.readAsStringSync();
        final doc = jsonDecode(raw);
        if (doc is Map<String, dynamic>) {
          _applyDocument(doc);
          if (_levelOrder.isNotEmpty || _specialEvents.isNotEmpty) {
            return;
          }
        }
      } catch (_) {
        continue;
      }
    }
  }

  static void _applySpecialEvents(Map<String, dynamic> doc) {
    // Omitting `special_events` must not wipe a list loaded from file or builtin (Flutter parity).
    if (!doc.containsKey('special_events')) {
      return;
    }
    final raw = doc['special_events'];
    if (raw is! List) {
      _specialEvents = [];
      _specialEventsExplicitlyEmptyInDoc = false;
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
    _specialEventsExplicitlyEmptyInDoc = raw.isEmpty;
  }

  static void _applyDocument(Map<String, dynamic> doc) {
    _applySpecialEvents(doc);
    final tiersRaw = doc['tiers'];
    if (tiersRaw is! List) return;
    final next = <int, Map<String, dynamic>>{};
    final order = <int>[];
    for (final ti in tiersRaw) {
      if (ti is! Map) continue;
      final m = Map<String, dynamic>.from(ti);
      final lvlRaw = m['level'];
      final lvl = lvlRaw is int ? lvlRaw : int.tryParse('$lvlRaw');
      if (lvl == null || lvl < 1) continue;
      final title = (m['title'] ?? '').toString().trim();
      final feeRaw = m['coin_fee'];
      final fee = feeRaw is int ? feeRaw : int.tryParse('$feeRaw');
      final minUr = m['min_user_level'];
      final minU =
          minUr is int ? minUr : int.tryParse('${minUr ?? lvl}') ?? lvl;
      if (title.isEmpty || fee == null || fee < 1 || minU < 1) continue;
      final row = <String, dynamic>{
        'title': title,
        'coin_fee': fee,
        'min_user_level': minU,
      };
      next[lvl] = row;
      if (!order.contains(lvl)) {
        order.add(lvl);
      }
    }
    if (next.isNotEmpty) {
      _tablesConfig = next;
      _levelOrder = order;
    }
  }

  static void _applyEnvOverlay() {
    final raw = Config.DUTCH_TABLES_JSON.trim();
    if (raw.isEmpty) return;
    Map<String, dynamic>? decoded;
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) {
        decoded = d;
      } else if (d is Map) {
        decoded = Map<String, dynamic>.from(d);
      }
    } catch (_) {
      return;
    }
    if (decoded == null) return;
    if (decoded.containsKey('tiers')) {
      _applyDocument(decoded);
      return;
    }
    // Legacy tier map only: do not clear [special_events] already loaded from file / builtin.
    decoded.forEach((k, v) {
      final lvl = int.tryParse(k.toString());
      if (lvl == null || v is! Map) return;
      final title = (v['title'] ?? '').toString().trim();
      final fee = int.tryParse((v['coin_fee'] ?? '').toString());
      final minU = int.tryParse((v['min_user_level'] ?? lvl).toString());
      if (title.isEmpty || fee == null || minU == null) return;
      _tablesConfig[lvl] = {
        'title': title,
        'coin_fee': fee,
        'min_user_level': minU,
      };
      if (!_levelOrder.contains(lvl)) {
        _levelOrder.add(lvl);
      }
      _levelOrder.sort();
    });
  }

  static Map<int, String> get levelToTitleMap {
    _ensureLoaded();
    return {for (final e in _tablesConfig.entries) e.key: e.value['title'] as String};
  }

  static Map<int, int> get levelToCoinFeeMap {
    _ensureLoaded();
    return {
      for (final e in _tablesConfig.entries) e.key: e.value['coin_fee'] as int,
    };
  }

  static Map<int, int> get tableLevelToMinUserLevelMap {
    _ensureLoaded();
    return {
      for (final e in _tablesConfig.entries) e.key: e.value['min_user_level'] as int,
    };
  }

  static List<int> get levelOrder {
    _ensureLoaded();
    return List<int>.unmodifiable(_levelOrder);
  }

  static List<Map<String, dynamic>> get specialEvents {
    _ensureLoaded();
    return List<Map<String, dynamic>>.unmodifiable(_specialEvents);
  }

  /// Full ``special_events`` catalog row for [rawId], or null when missing / invalid id.
  static Map<String, dynamic>? specialEventRowById(String rawId) {
    _ensureLoaded();
    final id = rawId.trim();
    if (id.isEmpty || !_eventIdPattern.hasMatch(id)) return null;
    for (final row in _specialEvents) {
      final rid = (row['id'] ?? row['event_id'] ?? '').toString().trim();
      if (rid == id) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  /// Room ``game_level`` tier for a catalog special-event row (``game_level`` field, else coin_fee tier match).
  /// Aligns with Flutter [resolvedGameLevelForSpecialEvent].
  static int resolvedGameTableLevelForSpecialEvent(Map<String, dynamic> raw) {
    _ensureLoaded();
    final gl = raw['game_level'];
    final glInt = gl is int ? gl : int.tryParse('$gl');
    if (glInt != null && glInt >= 1 && isValidLevel(glInt)) {
      return glInt;
    }
    final cf = raw['coin_fee'];
    final fee = cf is int ? cf : int.tryParse('$cf');
    if (fee != null && fee >= 0) {
      for (final lvl in levelOrder) {
        if (levelToCoinFee(lvl) == fee) return lvl;
      }
    }
    return levelOrder.isNotEmpty ? levelOrder.first : 1;
  }

  /// Shallow snapshot of ``metadata.end_match_modal`` for ``game_state`` (e.g. end-of-match UI).
  static Map<String, dynamic>? endMatchModalSnapshotForSpecialEventId(String rawId) {
    final row = specialEventRowById(rawId);
    if (row == null) return null;
    final meta = row['metadata'];
    if (meta is! Map) return null;
    final em = meta['end_match_modal'];
    if (em is! Map) return null;
    return Map<String, dynamic>.from(
      em.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  static String levelToTitle(int? level, {String? defaultTitle}) {
    _ensureLoaded();
    if (level == null) {
      return defaultTitle ?? '';
    }
    return levelToTitleMap[level] ?? defaultTitle ?? '';
  }

  static int? titleToLevel(String? title) {
    _ensureLoaded();
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
    _ensureLoaded();
    if (level == null) {
      return defaultFee ?? 0;
    }
    return levelToCoinFeeMap[level] ?? defaultFee ?? 0;
  }

  static int tableLevelToCoinFee(int? roomTableLevel, {int? defaultFee}) {
    return levelToCoinFee(roomTableLevel, defaultFee: defaultFee);
  }

  static int tableLevelToRequiredUserLevel(int? roomTableLevel,
      {int? defaultLevel}) {
    _ensureLoaded();
    if (roomTableLevel == null) {
      return defaultLevel ?? 1;
    }
    return tableLevelToMinUserLevelMap[roomTableLevel] ?? defaultLevel ?? 1;
  }

  static bool isValidLevel(int? level) {
    _ensureLoaded();
    return level != null && levelToTitleMap.containsKey(level);
  }

  static List<String> get allTitles =>
      levelOrder.map((l) => levelToTitleMap[l]!).toList();
}
