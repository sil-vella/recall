import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/managers/navigation_manager.dart';
import '../../../utils/consts/config.dart';

/// Sentinel for [Map] `data.deeplink` (or `data.deeplink_path`): client opens the OS store listing.
const String kNotificationDeeplinkStoreLink = 'store_link';

/// True when [value] is the store-link sentinel (case-insensitive).
bool isNotificationStoreLinkDeeplink(String? value) {
  return value?.trim().toLowerCase() == kNotificationDeeplinkStoreLink;
}

/// Play Store or App Store URL from [Config], matching share/copy behaviour.
String resolveStoreListingUrl() {
  if (!kIsWeb && Platform.isIOS) {
    final ios = Config.appStoreUrl.trim();
    if (ios.isNotEmpty) return ios;
  }
  return Config.playStoreUrl.trim();
}

/// Opens the platform store listing in an external browser/app.
Future<bool> tryLaunchStoreListing() async {
  final url = resolveStoreListingUrl();
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || !await canLaunchUrl(uri)) return false;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
  return true;
}

/// Handles `data.deeplink` / `data.deeplink_path` == [kNotificationDeeplinkStoreLink].
Future<bool> tryHandleNotificationData(Map<String, dynamic> data) async {
  final deeplink = data['deeplink'];
  if (deeplink is String && isNotificationStoreLinkDeeplink(deeplink)) {
    return tryLaunchStoreListing();
  }
  final pathFlat = data['deeplink_path']?.toString();
  if (isNotificationStoreLinkDeeplink(pathFlat)) {
    return tryLaunchStoreListing();
  }
  return false;
}

/// In-app navigation and external URLs from notification [message] `data` (globals and per-user).
Future<void> handleNotificationMessageDeeplink(Map<String, dynamic> message) async {
  final data = message['data'];
  if (data is! Map) return;
  final map = Map<String, dynamic>.from(data);

  if (await tryHandleNotificationData(map)) return;

  String? path;
  Map<String, dynamic>? query;

  final rawDeeplink = map['deeplink'];
  if (rawDeeplink is Map) {
    final m = Map<String, dynamic>.from(rawDeeplink);
    path = (m.remove('path') ?? m.remove('route'))?.toString().trim();
    query = m.map((k, v) => MapEntry(k.toString(), v));
  } else if (rawDeeplink is String) {
    final link = rawDeeplink.trim();
    if (link.startsWith('http')) {
      final uri = Uri.tryParse(link);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (link.startsWith('/')) {
      final uri = Uri.parse('https://_._$link');
      path = uri.path;
      if (uri.queryParameters.isNotEmpty) {
        query = Map<String, dynamic>.from(uri.queryParameters);
      }
    }
  }

  if (path == null || path.isEmpty) {
    final flat = map['deeplink_path']?.toString().trim();
    if (flat != null && flat.isNotEmpty) {
      path = flat;
    }
    final dqFlat = map['deeplink_query'];
    if (dqFlat is Map && dqFlat.isNotEmpty) {
      query ??= {};
      dqFlat.forEach((k, v) {
        query![k.toString()] = v;
      });
    }
  }

  final extra = map['deeplink_query'];
  if (extra is Map && extra.isNotEmpty) {
    query ??= {};
    extra.forEach((k, v) {
      query![k.toString()] = v;
    });
  }

  if (path == null || path.isEmpty) return;
  if (!path.startsWith('/')) return;

  NavigationManager().navigateTo(
    path,
    parameters: query?.map((k, v) => MapEntry(k, v?.toString() ?? '')),
  );
}

/// Response-button CTA: store sentinel, global deeplink, or REST (caller handles REST).
Future<bool> tryHandleNotificationMessageCta(Map<String, dynamic> message) async {
  final data = message['data'];
  if (data is Map && await tryHandleNotificationData(Map<String, dynamic>.from(data))) {
    return true;
  }
  if (message['origin']?.toString() == 'global') {
    await handleNotificationMessageDeeplink(message);
    return true;
  }
  return false;
}
