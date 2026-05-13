import 'dart:io';

/// Host-side paths (repo `global.log`, `.vscode/generated/...`) only exist on the
/// machine running `flutter run`. On Android/iOS those paths are wrong and env from
/// the IDE is usually absent, so mirroring is desktop-only.
bool get _wfCanMirrorToHostPaths {
  return Platform.isMacOS || Platform.isLinux || Platform.isWindows;
}

String _wfTimestamp() {
  final d = DateTime.now();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p2(d.month)}-${p2(d.day)} ${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)}';
}

void _appendGlobal(String line) {
  if (!_wfCanMirrorToHostPaths) return;
  final g = Platform.environment['WFGLOBALOG_GLOBAL_LOG'];
  final src = Platform.environment['WFGLOBALOG_SOURCE'];
  if (g == null || g.isEmpty || src == null || src.isEmpty) return;
  try {
    final out = '${_wfTimestamp()} [$src] $line\n';
    File(g).writeAsStringSync(out, mode: FileMode.append, flush: true);
  } catch (_) {}
}

/// Appends [line] to capture file and (when set) repo [global.log] via env.
void mirrorLogLineToCapture(String line) {
  if (!_wfCanMirrorToHostPaths) return;
  final p = Platform.environment['WFGLOBALOG_CAPTURE_FILE'];
  if (p != null && p.isNotEmpty) {
    try {
      File(p).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
  _appendGlobal(line);
}
