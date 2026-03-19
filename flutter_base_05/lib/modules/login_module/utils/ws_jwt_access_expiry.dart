import 'dart:convert';

/// Reads JWT payload without verifying the signature.
/// Used only to inspect [exp] so WebSocket auth can refresh before Python rejects the access token.
class WsJwtAccessExpiry {
  WsJwtAccessExpiry._();

  static Map<String, dynamic>? readJwtPayloadMap(String jwt) {
    final parts = jwt.trim().split('.');
    if (parts.length != 3) return null;
    try {
      var segment = parts[1];
      final mod = segment.length % 4;
      if (mod == 2) {
        segment += '==';
      } else if (mod == 3) {
        segment += '=';
      } else if (mod == 1) {
        return null;
      }
      final jsonStr = utf8.decode(base64Url.decode(segment));
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// `true` if token is past [exp] or within [within] of [exp] (UTC).
  /// `false` if payload cannot be read (caller should fall back to existing logic).
  static bool isJwtExpiredOrNearExpiry(
    String jwt, {
    Duration within = const Duration(minutes: 2),
  }) {
    final payload = readJwtPayloadMap(jwt);
    if (payload == null) return false;
    final exp = payload['exp'];
    int? expSec;
    if (exp is int) {
      expSec = exp;
    } else if (exp is num) {
      expSec = exp.toInt();
    }
    if (expSec == null) return false;
    final expiryUtc = DateTime.fromMillisecondsSinceEpoch(expSec * 1000, isUtc: true);
    final thresholdUtc = expiryUtc.subtract(within);
    final nowUtc = DateTime.now().toUtc();
    return !nowUtc.isBefore(thresholdUtc);
  }
}
