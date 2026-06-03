import 'package:package_info_plus/package_info_plus.dart';

import '../../../utils/consts/config.dart';
import '../../../utils/dev_logger.dart';

const String _loggingSwitchDevLog = String.fromEnvironment('DUTCH_DEV_LOG', defaultValue: '');
const bool LOGGING_SWITCH = _loggingSwitchDevLog == '1' ||
    _loggingSwitchDevLog == 'true' ||
    _loggingSwitchDevLog == 'TRUE' ||
    _loggingSwitchDevLog == 'yes' ||
    _loggingSwitchDevLog == 'YES';

/// Installed app version for update-modal gating: [PackageInfo] (pubspec / `--build-name`),
/// then [Config.appVersion] from dart-defines if PackageInfo is empty.
class AppVersionHelper {
  AppVersionHelper._();

  static String? _cached;

  static Future<String> resolve() async {
    if (_cached != null && _cached!.isNotEmpty) return _cached!;
    var pkgV = '';
    try {
      final info = await PackageInfo.fromPlatform();
      pkgV = info.version.trim();
    } catch (_) {}
    final cfgV = Config.appVersion.trim();
    if (pkgV.isNotEmpty) {
      _cached = pkgV;
    } else {
      _cached = cfgV.isNotEmpty ? cfgV : '0.0.0';
    }
    if (LOGGING_SWITCH) {
      customlog(
        'AppVersionHelper: modal gate uses installed=$_cached '
        '(PackageInfo=$pkgV dart-define APP_VERSION=$cfgV)',
      );
    }
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
