import 'package:package_info_plus/package_info_plus.dart';

import '../../../utils/consts/config.dart';

/// Installed app version (from [PackageInfo], fallback [Config.appVersion]).
class AppVersionHelper {
  AppVersionHelper._();

  static String? _cached;

  static Future<String> resolve() async {
    if (_cached != null && _cached!.isNotEmpty) return _cached!;
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      if (v.isNotEmpty) {
        _cached = v;
        return v;
      }
    } catch (_) {}
    _cached = Config.appVersion.trim().isNotEmpty ? Config.appVersion.trim() : '0.0.0';
    return _cached!;
  }

  /// Clears cache (tests only).
  static void resetCacheForTests() {
    _cached = null;
  }
}

/// Parses `major.minor.patch` (ignores `+build` suffix if present).
List<int> parseSemanticVersion(String version) {
  var s = version.trim();
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  final parts = <int>[];
  for (final token in s.split('.')) {
    final t = token.trim();
    if (t.isEmpty) break;
    final n = int.tryParse(t);
    if (n == null) break;
    parts.add(n);
  }
  if (parts.isEmpty) return [0];
  return parts;
}

/// Negative if [a] < [b], zero if equal, positive if [a] > [b].
int compareSemanticVersions(String a, String b) {
  final ta = parseSemanticVersion(a);
  final tb = parseSemanticVersion(b);
  final len = ta.length > tb.length ? ta.length : tb.length;
  for (var i = 0; i < len; i++) {
    final va = i < ta.length ? ta[i] : 0;
    final vb = i < tb.length ? tb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}
