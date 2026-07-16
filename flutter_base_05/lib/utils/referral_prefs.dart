import '../core/services/shared_preferences.dart';

/// SharedPreferences key for campaign referral codes awaiting / already queued for backend sync.
const String kPendingReferralCodesKey = 'pending_referral_codes';

class ReferralPrefs {
  ReferralPrefs._();

  static String normalizeCode(String raw) => raw.trim().toUpperCase();

  static Future<SharedPrefManager> _prefs() async {
    final sharedPref = SharedPrefManager();
    await sharedPref.initialize();
    return sharedPref;
  }

  static Future<List<String>> getPendingCodes() async {
    final sharedPref = await _prefs();
    final list = sharedPref.getStringList(kPendingReferralCodesKey);
    final out = <String>[];
    final seen = <String>{};
    for (final raw in list) {
      final code = normalizeCode(raw);
      if (code.isEmpty || seen.contains(code)) continue;
      seen.add(code);
      out.add(code);
    }
    return out;
  }

  /// Append [rawCode] if not already present. Returns normalized code or null if empty.
  static Future<String?> appendCode(String rawCode) async {
    final code = normalizeCode(rawCode);
    if (code.isEmpty) return null;
    final sharedPref = await _prefs();
    final list = List<String>.from(sharedPref.getStringList(kPendingReferralCodesKey));
    final normalized = list.map(normalizeCode).where((c) => c.isNotEmpty).toList();
    if (!normalized.contains(code)) {
      normalized.add(code);
      await sharedPref.setStringList(kPendingReferralCodesKey, normalized);
    } else {
      await sharedPref.setStringList(kPendingReferralCodesKey, normalized);
    }
    return code;
  }

  /// Remove codes that the server accepted or permanently rejected.
  static Future<void> removeCodes(Iterable<String> codes) async {
    final toRemove = codes.map(normalizeCode).where((c) => c.isNotEmpty).toSet();
    if (toRemove.isEmpty) return;
    final sharedPref = await _prefs();
    final remaining = sharedPref
        .getStringList(kPendingReferralCodesKey)
        .map(normalizeCode)
        .where((c) => c.isNotEmpty && !toRemove.contains(c))
        .toList();
    await sharedPref.setStringList(kPendingReferralCodesKey, remaining);
  }
}
