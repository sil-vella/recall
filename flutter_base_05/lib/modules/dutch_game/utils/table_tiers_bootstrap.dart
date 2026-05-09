import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../tools/logging/logger.dart';
import '../backend_core/utils/level_matcher.dart';

/// Persists declarative Dutch table tiers from [get-user-stats] and caches table back-graphics locally from `back_graphic_url`.
///
/// Efficient path: bundled `GET /userauth/dutch/get-user-stats` only sends full `table_tiers` JSON when
/// `client_table_tiers_revision` is missing/stale — otherwise Flutter reuses prefs + skips large payload.
class TableTiersBootstrap {
  TableTiersBootstrap._();

  static const bool LOGGING_SWITCH = true;

  static const String prefRevisionKey = 'dutch_table_tiers_revision';
  static const String prefDocKey = 'dutch_table_tiers_doc_json';

  static final Logger _logger = Logger();

  /// Hydrate catalog from prefs before any authenticated stats call so cold starts use cached tiers.
  static Future<void> hydrateFromPrefsBeforeStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefDocKey)?.trim();
      if (raw == null || raw.isEmpty) {
        LevelMatcher.ensureHydratedMinimal();
        return;
      }
      final doc = jsonDecode(raw);
      if (doc is Map<String, dynamic>) {
        final typed = Map<String, dynamic>.from(doc);
        LevelMatcher.applyTableTiersDocument(typed, clearDownloadedGraphics: false);
        final rev = prefs.getString(prefRevisionKey) ?? '';
        if (!kIsWeb && rev.isNotEmpty) {
          await _ensureDownloadedGraphicFiles(typed, rev);
        }
      } else {
        LevelMatcher.ensureHydratedMinimal();
      }
    } catch (_) {
      LevelMatcher.ensureHydratedMinimal();
    }
  }

  static Future<String?> getStoredRevisionForApi() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getString(prefRevisionKey)?.trim();
    return (r != null && r.isNotEmpty) ? r : null;
  }

  /// Process top-level envelope from `/userauth/dutch/get-user-stats`.
  static Future<void> mergeStatsEnvelope(Map<String, dynamic> envelope) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final revision = envelope['table_tiers_revision']?.toString().trim();
      final payload = envelope['table_tiers'];
      if (payload != null && payload is Map<String, dynamic>) {
        final doc = Map<String, dynamic>.from(payload);
        LevelMatcher.applyTableTiersDocument(doc, clearDownloadedGraphics: true);
        final serialized = jsonEncode(doc);
        if (revision != null && revision.isNotEmpty) {
          await prefs.setString(prefRevisionKey, revision);
        }
        await prefs.setString(prefDocKey, serialized);
        if (!kIsWeb && revision != null && revision.isNotEmpty) {
          await _ensureDownloadedGraphicFiles(doc, revision);
        }
        return;
      }
      if (revision != null && revision.isNotEmpty) {
        await prefs.setString(prefRevisionKey, revision);
      }
      if (!kIsWeb && revision != null && revision.isNotEmpty) {
        final rawStored = prefs.getString(prefDocKey);
        if (rawStored != null && rawStored.isNotEmpty) {
          try {
            final doc = jsonDecode(rawStored);
            if (doc is Map<String, dynamic>) {
              await _ensureDownloadedGraphicFiles(Map<String, dynamic>.from(doc), revision);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      if (LOGGING_SWITCH) {
        _logger.warning('TableTiersBootstrap: mergeStatsEnvelope skip: $e');
      }
    }
  }

  static Future<void> _ensureDownloadedGraphicFiles(
    Map<String, dynamic> doc,
    String revisionVersion,
  ) async {
    final dir = await getApplicationSupportDirectory();
    final cacheRoot = Directory('${dir.path}/dutch_table_tiers_graphics/$revisionVersion');
    await cacheRoot.create(recursive: true);

    final client = http.Client();
    try {
      final tiers = doc['tiers'];
      if (tiers is List) {
        for (final ti in tiers) {
          if (ti is! Map) continue;
          final m = Map<String, dynamic>.from(ti);
          final lvl = m['level'];
          final level = lvl is int ? lvl : int.tryParse('$lvl');
          if (level == null) continue;
          final style = m['style'];
          if (style is! Map) {
            LevelMatcher.setLocalGraphicPath(level, '');
            continue;
          }
          final url = style['back_graphic_url']?.toString().trim() ?? '';
          if (url.isEmpty ||
              !(url.startsWith('https://') || url.startsWith('http://'))) {
            LevelMatcher.setLocalGraphicPath(level, '');
            continue;
          }
          var ext = '.bin';
          final segs = Uri.parse(url).pathSegments;
          if (segs.isNotEmpty) {
            final tail = segs.last;
            final dot = tail.lastIndexOf('.');
            if (dot > 0 && dot < tail.length - 1) {
              ext = tail.substring(dot);
            }
          }
          final file = File('${cacheRoot.path}/level_$level$ext');
          try {
            if (!file.existsSync() || file.lengthSync() == 0) {
              final rsp = await client.get(Uri.parse(url));
              if (rsp.statusCode >= 400) {
                continue;
              }
              await file.parent.create(recursive: true);
              await file.writeAsBytes(rsp.bodyBytes);
            }
            if (file.existsSync() && file.lengthSync() > 0) {
              LevelMatcher.setLocalGraphicPath(level, file.absolute.path);
            }
          } catch (_) {
            /* keep network / felt fallback */
          }
        }
      }
      final events = doc['special_events'];
      if (events is List) {
        for (final ev in events) {
          if (ev is! Map) continue;
          final m = Map<String, dynamic>.from(ev);
          final eidRaw = ((m['id'] ?? m['event_id']) ?? '').toString().trim();
          if (eidRaw.isEmpty) continue;
          final style = m['style'];
          if (style is! Map) {
            LevelMatcher.setLocalEventGraphicPath(eidRaw, '');
            continue;
          }
          final url = style['back_graphic_url']?.toString().trim() ?? '';
          if (url.isEmpty ||
              !(url.startsWith('https://') || url.startsWith('http://'))) {
            LevelMatcher.setLocalEventGraphicPath(eidRaw, '');
            continue;
          }
          var ext = '.bin';
          final segs = Uri.parse(url).pathSegments;
          if (segs.isNotEmpty) {
            final tail = segs.last;
            final dot = tail.lastIndexOf('.');
            if (dot > 0 && dot < tail.length - 1) {
              ext = tail.substring(dot);
            }
          }
          final safeSeg = _safeCacheSegment(eidRaw);
          final file = File('${cacheRoot.path}/event_$safeSeg$ext');
          try {
            if (!file.existsSync() || file.lengthSync() == 0) {
              final rsp = await client.get(Uri.parse(url));
              if (rsp.statusCode >= 400) {
                continue;
              }
              await file.parent.create(recursive: true);
              await file.writeAsBytes(rsp.bodyBytes);
            }
            if (file.existsSync() && file.lengthSync() > 0) {
              LevelMatcher.setLocalEventGraphicPath(eidRaw, file.absolute.path);
            }
          } catch (_) {
            /* keep network / felt fallback */
          }

          // Additional declarative special-event assets for no-app-update visuals/media.
          final meta = m['metadata'];
          final styleMap = Map<String, dynamic>.from(style);
          final metaMap = meta is Map ? Map<String, dynamic>.from(meta) : <String, dynamic>{};
          await _cacheEventAuxAsset(
            client: client,
            cacheRoot: cacheRoot,
            eventId: eidRaw,
            assetKey: 'overlay_image_url',
            url: styleMap['overlay_image_url']?.toString(),
          );
          await _cacheEventAuxAsset(
            client: client,
            cacheRoot: cacheRoot,
            eventId: eidRaw,
            assetKey: 'banner_image_url',
            url: metaMap['banner_image_url']?.toString(),
          );
          await _cacheEventAuxAsset(
            client: client,
            cacheRoot: cacheRoot,
            eventId: eidRaw,
            assetKey: 'intro_video_url',
            url: metaMap['intro_video_url']?.toString(),
          );
          await _cacheEventAuxAsset(
            client: client,
            cacheRoot: cacheRoot,
            eventId: eidRaw,
            assetKey: 'audio_url',
            url: metaMap['audio_url']?.toString(),
          );
        }
      }
    } finally {
      client.close();
    }
  }

  static Future<void> _cacheEventAuxAsset({
    required http.Client client,
    required Directory cacheRoot,
    required String eventId,
    required String assetKey,
    required String? url,
  }) async {
    final resolvedUrl = (url ?? '').trim();
    if (resolvedUrl.isEmpty ||
        !(resolvedUrl.startsWith('https://') || resolvedUrl.startsWith('http://'))) {
      return;
    }
    var ext = '.bin';
    try {
      final segs = Uri.parse(resolvedUrl).pathSegments;
      if (segs.isNotEmpty) {
        final tail = segs.last;
        final dot = tail.lastIndexOf('.');
        if (dot > 0 && dot < tail.length - 1) {
          ext = tail.substring(dot);
        }
      }
    } catch (_) {}
    final safeSeg = _safeCacheSegment(eventId);
    final safeAsset = _safeCacheSegment(assetKey);
    final file = File('${cacheRoot.path}/event_${safeSeg}_${safeAsset}$ext');
    try {
      if (!file.existsSync() || file.lengthSync() == 0) {
        final rsp = await client.get(Uri.parse(resolvedUrl));
        if (rsp.statusCode >= 400) {
          return;
        }
        await file.parent.create(recursive: true);
        await file.writeAsBytes(rsp.bodyBytes);
      }
    } catch (_) {
      // Ignore optional-asset cache failures; runtime can still use remote URL.
    }
  }

  static String _safeCacheSegment(String raw) {
    final s = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return s.isEmpty ? 'x' : s;
  }
}
