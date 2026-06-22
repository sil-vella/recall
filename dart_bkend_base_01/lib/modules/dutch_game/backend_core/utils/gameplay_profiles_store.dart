import 'dart:convert';
import 'dart:io';

import 'package:dart_game_server/utils/dev_logger.dart';
import '../../../../utils/config.dart';

const bool LOGGING_SWITCH = false;

/// In-memory gameplay rule profiles from declarative JSON (Python SSOT mirror).
class GameplayProfilesStore {
  GameplayProfilesStore._();

  static const String defaultProfileId = 'classic';

  static const String _builtinJson = r'''{"schema_version":1,"profiles":{"classic":{"id":"classic","label":"Classic Dutch","description":"Standard rules — no collection.","flags":{"clear_and_collect":false,"same_rank_out_of_turn":true,"queen_peek":true,"jack_swap":true,"dutch_call":true,"discard_take_allowed":true},"deal":{"cards_per_hand":4,"initial_peek_count":2},"timers":{},"deck":{"source":"standard"},"scoring":{"red_king_points":10},"win_conditions":{"empty_hand":true,"lowest_points_after_dutch":true,"four_of_a_kind_collection":false}}}}''';

  static Map<String, Map<String, dynamic>> _profilesById = {};
  static bool _loaded = false;
  static String? _cachedRevision;

  static String? get cachedRevision => _cachedRevision;

  static void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    _tryLoadDeclarativeFile();
    if (_profilesById.isEmpty) {
      _applyDocument(Map<String, dynamic>.from(jsonDecode(_builtinJson) as Map));
    }
  }

  static List<String> _configCandidatePaths() {
    final out = <String>[];
    void add(String? p) {
      if (p == null) return;
      final t = p.trim();
      if (t.isEmpty || out.contains(t)) return;
      out.add(t);
    }

    add(Config.DUTCH_GAMEPLAY_PROFILES_PATH.trim());
    add(_joinPath('.', ['config', 'gameplay_profiles.json']));

    try {
      var dir = File.fromUri(Platform.script).absolute.parent;
      for (var i = 0; i < 16; i++) {
        add(_joinPath(dir.path, ['config', 'gameplay_profiles.json']));
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    } catch (_) {}

    try {
      var cwd = Directory.current.absolute;
      for (var i = 0; i < 10; i++) {
        add(_joinPath(cwd.path, ['config', 'gameplay_profiles.json']));
        add(_joinPath(cwd.path, ['dart_bkend_base_01', 'config', 'gameplay_profiles.json']));
        final parent = cwd.parent;
        if (parent.path == cwd.path) break;
        cwd = parent;
      }
    } catch (_) {}

    return out;
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

  static void _tryLoadDeclarativeFile() {
    for (final path in _configCandidatePaths()) {
      try {
        final f = File(path);
        if (!f.existsSync()) continue;
        final raw = f.readAsStringSync();
        final doc = jsonDecode(raw);
        if (doc is Map<String, dynamic>) {
          _applyDocument(doc);
          if (_profilesById.isNotEmpty) {
            if (LOGGING_SWITCH) {
              customlog(
                'GameplayProfilesStore: loaded ${_profilesById.length} profiles from $path',
              );
            }
            return;
          }
        }
      } catch (_) {
        continue;
      }
    }
  }

  static Map<String, dynamic> _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> override,
  ) {
    final out = Map<String, dynamic>.from(base);
    override.forEach((key, val) {
      final existing = out[key];
      if (val is Map && existing is Map) {
        out[key] = _deepMerge(
          Map<String, dynamic>.from(existing),
          Map<String, dynamic>.from(val),
        );
      } else {
        out[key] = val;
      }
    });
    return out;
  }

  static Map<String, dynamic> _applyDefaults(Map<String, dynamic> resolved) {
    final out = Map<String, dynamic>.from(resolved);
    final flags = Map<String, dynamic>.from(
      out['flags'] is Map ? Map<String, dynamic>.from(out['flags'] as Map) : {},
    );
    flags.putIfAbsent('clear_and_collect', () => false);
    flags.putIfAbsent('same_rank_out_of_turn', () => true);
    flags.putIfAbsent('queen_peek', () => true);
    flags.putIfAbsent('jack_swap', () => true);
    flags.putIfAbsent('dutch_call', () => true);
    flags.putIfAbsent('discard_take_allowed', () => true);
    out['flags'] = flags;

    final deal = Map<String, dynamic>.from(
      out['deal'] is Map ? Map<String, dynamic>.from(out['deal'] as Map) : {},
    );
    deal.putIfAbsent('cards_per_hand', () => 4);
    deal.putIfAbsent('initial_peek_count', () => 2);
    out['deal'] = deal;

    final deck = Map<String, dynamic>.from(
      out['deck'] is Map ? Map<String, dynamic>.from(out['deck'] as Map) : {},
    );
    deck.putIfAbsent('source', () => 'standard');
    out['deck'] = deck;

    final scoring = Map<String, dynamic>.from(
      out['scoring'] is Map ? Map<String, dynamic>.from(out['scoring'] as Map) : {},
    );
    scoring.putIfAbsent('red_king_points', () => 10);
    out['scoring'] = scoring;

    final win = Map<String, dynamic>.from(
      out['win_conditions'] is Map
          ? Map<String, dynamic>.from(out['win_conditions'] as Map)
          : {},
    );
    win.putIfAbsent('empty_hand', () => true);
    win.putIfAbsent('lowest_points_after_dutch', () => true);
    win.putIfAbsent(
      'four_of_a_kind_collection',
      () => flags['clear_and_collect'] == true,
    );
    out['win_conditions'] = win;
    out.putIfAbsent('timers', () => <String, dynamic>{});
    return out;
  }

  static Map<String, dynamic> _resolveChain(
    String profileId,
    Map<String, Map<String, dynamic>> rawProfiles, [
    Set<String>? visiting,
  ]) {
    final row = rawProfiles[profileId];
    if (row == null) {
      throw StateError('Unknown gameplay profile: $profileId');
    }
    visiting ??= <String>{};
    if (visiting.contains(profileId)) {
      throw StateError('Circular extends chain at $profileId');
    }
    visiting.add(profileId);
    final parentId = row['extends']?.toString().trim();
    if (parentId != null && parentId.isNotEmpty) {
      final parent = _resolveChain(parentId, rawProfiles, visiting);
      final merged = _deepMerge(parent, Map<String, dynamic>.from(row));
      merged['id'] = profileId;
      merged['profile_id'] = profileId;
      merged.remove('extends');
      return merged;
    }
    final out = Map<String, dynamic>.from(row);
    out['id'] = profileId;
    out['profile_id'] = profileId;
    out.remove('extends');
    return out;
  }

  static void applyDocument(Map<String, dynamic>? doc, {String? revision}) {
    _applyDocument(doc, revision: revision);
  }

  static void _applyDocument(Map<String, dynamic>? doc, {String? revision}) {
    if (doc == null || doc.isEmpty) return;
    final profilesRaw = doc['profiles'];
    if (profilesRaw is! Map) return;

    final rawProfiles = <String, Map<String, dynamic>>{};
    profilesRaw.forEach((key, val) {
      if (val is! Map) return;
      final pid = key.toString().trim();
      if (pid.isEmpty) return;
      rawProfiles[pid] = Map<String, dynamic>.from(val);
    });

    if (!rawProfiles.containsKey(defaultProfileId)) return;

    final resolved = <String, Map<String, dynamic>>{};
    for (final pid in rawProfiles.keys) {
      resolved[pid] = _applyDefaults(_resolveChain(pid, rawProfiles));
    }
    _profilesById = resolved;

    final rev = revision?.trim();
    if (rev != null && rev.isNotEmpty) {
      _cachedRevision = rev;
    }
    if (LOGGING_SWITCH) {
      customlog(
        'GameplayProfilesStore.applyDocument: profile_count=${resolved.length} '
        'revision=${rev ?? _cachedRevision ?? '(none)'}',
      );
    }
  }

  static void updateRevisionOnly(String revision) {
    final rev = revision.trim();
    if (rev.isNotEmpty) _cachedRevision = rev;
  }

  static Map<String, dynamic> resolveProfile(String? profileId) {
    _ensureLoaded();
    final pid = (profileId ?? '').trim().isEmpty
        ? defaultProfileId
        : profileId!.trim();
    final row = _profilesById[pid];
    if (row == null) {
      return Map<String, dynamic>.from(_profilesById[defaultProfileId]!);
    }
    return Map<String, dynamic>.from(row);
  }

  static String? gameplayProfileIdForSpecialEvent(String? specialEventId) {
    if (specialEventId == null || specialEventId.trim().isEmpty) return null;
    // Lazy import avoided — caller passes row when available.
    return null;
  }

  static Map<String, dynamic> buildSnapshotForProfile(String? profileId) {
    final resolved = resolveProfile(profileId);
    return Map<String, dynamic>.from(resolved);
  }

  static void reloadFromDisk() {
    _loaded = false;
    _profilesById = {};
    _ensureLoaded();
    if (LOGGING_SWITCH) {
      customlog(
        'GameplayProfilesStore.reloadFromDisk: profile_count=${_profilesById.length} '
        'revision=${_cachedRevision ?? '(none)'}',
      );
    }
  }
}
