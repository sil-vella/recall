/// In-memory gameplay rule profiles (Flutter client — loaded from init-data prefs).
class GameplayProfilesStore {
  GameplayProfilesStore._();

  static const String defaultProfileId = 'classic';

  static const Map<String, dynamic> _builtinClassic = {
    'id': 'classic',
    'profile_id': 'classic',
    'label': 'Classic Dutch',
    'description': 'Standard rules — no collection.',
    'flags': {
      'clear_and_collect': false,
      'same_rank_out_of_turn': true,
      'queen_peek': true,
      'jack_swap': true,
      'dutch_call': true,
      'discard_take_allowed': true,
    },
    'deal': {'cards_per_hand': 4, 'initial_peek_count': 2},
    'timers': <String, dynamic>{},
    'deck': {'source': 'standard'},
    'scoring': {'red_king_points': 10},
    'win_conditions': {
      'empty_hand': true,
      'lowest_points_after_dutch': true,
      'four_of_a_kind_collection': false,
    },
  };

  static Map<String, Map<String, dynamic>> _profilesById = {
    defaultProfileId: Map<String, dynamic>.from(_builtinClassic),
  };
  static String? _cachedRevision;

  static String? get cachedRevision => _cachedRevision;

  static void applyDocument(Map<String, dynamic>? doc, {String? revision}) {
    if (doc == null || doc.isEmpty) return;
    final profilesRaw = doc['profiles'];
    if (profilesRaw is! Map) return;
    final next = <String, Map<String, dynamic>>{};
    profilesRaw.forEach((key, val) {
      if (val is! Map) return;
      final pid = key.toString().trim();
      if (pid.isEmpty) return;
      next[pid] = Map<String, dynamic>.from(val);
    });
    if (next.isEmpty) return;
    _profilesById = next;
    final rev = revision?.trim();
    if (rev != null && rev.isNotEmpty) _cachedRevision = rev;
  }

  static void updateRevisionOnly(String revision) {
    final rev = revision.trim();
    if (rev.isNotEmpty) _cachedRevision = rev;
  }

  static Map<String, dynamic> resolveProfile(String? profileId) {
    final pid = (profileId ?? '').trim().isEmpty
        ? defaultProfileId
        : profileId!.trim();
    final row = _profilesById[pid];
    if (row != null) return Map<String, dynamic>.from(row);
    return Map<String, dynamic>.from(
      _profilesById[defaultProfileId] ?? _builtinClassic,
    );
  }

  static Map<String, dynamic> buildSnapshotForProfile(String? profileId) =>
      resolveProfile(profileId);
}
