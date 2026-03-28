import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Helpers for matching route destinations to YAML exclude patterns.
///
/// Prefer [RouteSettings.name] (GoRouter usually sets this to the location path). If it is
/// empty, falls back to [GoRouter.state] from the route's navigator context.

/// Normalizes a route name for comparison: leading slash, no trailing slash (except `/`),
/// strips query; extracts path from `http(s)` URLs.
String normalizeRoutePath(String raw) {
  var t = raw.trim();
  if (t.startsWith('http')) {
    final u = Uri.tryParse(t);
    if (u != null && u.path.isNotEmpty) {
      t = u.path;
    }
  }
  final q = t.indexOf('?');
  if (q >= 0) {
    t = t.substring(0, q);
  }
  if (!t.startsWith('/')) {
    t = '/$t';
  }
  if (t.length > 1 && t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

/// Best-effort path for the destination of [route] (for exclude lists).
String? destinationPathForRoute(Route<dynamic> route) {
  final n = route.settings.name;
  if (n != null && n.isNotEmpty) {
    return n;
  }
  final ctx = route.navigator?.context;
  if (ctx != null && ctx.mounted) {
    try {
      return GoRouterState.of(ctx).uri.path;
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Returns true if [routeName] matches any entry in [patterns].
///
/// - Exact: `/account` matches only `/account`.
/// - Prefix: pattern ending with `*` (e.g. `/dutch*`) matches `/dutch` and `/dutch/...`.
bool routeMatchesExcludeList(String? routeName, List<String> patterns) {
  if (routeName == null || routeName.isEmpty || patterns.isEmpty) {
    return false;
  }
  final path = normalizeRoutePath(routeName);
  for (final p in patterns) {
    final pat = p.trim();
    if (pat.isEmpty) {
      continue;
    }
    if (pat.endsWith('*')) {
      final prefixRaw = pat.substring(0, pat.length - 1).trim();
      if (prefixRaw.isEmpty) {
        continue;
      }
      final prefix = normalizeRoutePath(prefixRaw);
      if (path == prefix || path.startsWith('$prefix/')) {
        return true;
      }
    } else {
      if (path == normalizeRoutePath(pat)) {
        return true;
      }
    }
  }
  return false;
}

/// True if [route]'s destination path matches any exclude [patterns].
bool routeDestinationMatchesExcludeList(Route<dynamic> route, List<String> patterns) {
  return routeMatchesExcludeList(destinationPathForRoute(route), patterns);
}
