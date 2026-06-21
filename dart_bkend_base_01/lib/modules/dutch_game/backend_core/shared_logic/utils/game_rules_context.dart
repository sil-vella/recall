/// Resolved gameplay rule snapshot read from [game_state.gameplay_rules].
class GameRulesContext {
  GameRulesContext(Map<String, dynamic> snapshot)
      : _snapshot = Map<String, dynamic>.from(snapshot);

  final Map<String, dynamic> _snapshot;

  String get profileId =>
      (_snapshot['profile_id'] ?? _snapshot['id'] ?? 'classic').toString();

  Map<String, dynamic> get flags {
    final raw = _snapshot['flags'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return const {};
  }

  Map<String, dynamic> get deal {
    final raw = _snapshot['deal'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return const {};
  }

  Map<String, dynamic> get timers {
    final raw = _snapshot['timers'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return const {};
  }

  Map<String, dynamic> get deck {
    final raw = _snapshot['deck'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return const {'source': 'standard'};
  }

  Map<String, dynamic> get scoring {
    final raw = _snapshot['scoring'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return const {'red_king_points': 10};
  }

  Map<String, dynamic> get winConditions {
    final raw = _snapshot['win_conditions'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return const {};
  }

  bool _flag(String key, {required bool defaultValue}) {
    final raw = flags[key];
    if (raw is bool) return raw;
    if (raw == null) return defaultValue;
    final s = raw.toString().trim().toLowerCase();
    if (s == '1' || s == 'true' || s == 'yes') return true;
    if (s == '0' || s == 'false' || s == 'no') return false;
    return defaultValue;
  }

  bool _win(String key, {required bool defaultValue}) {
    final raw = winConditions[key];
    if (raw is bool) return raw;
    if (raw == null) return defaultValue;
    final s = raw.toString().trim().toLowerCase();
    if (s == '1' || s == 'true' || s == 'yes') return true;
    if (s == '0' || s == 'false' || s == 'no') return false;
    return defaultValue;
  }

  bool get clearAndCollect => _flag('clear_and_collect', defaultValue: false);

  bool get sameRankOutOfTurn =>
      _flag('same_rank_out_of_turn', defaultValue: true);

  bool get queenPeekEnabled => _flag('queen_peek', defaultValue: true);

  bool get jackSwapEnabled => _flag('jack_swap', defaultValue: true);

  bool get dutchCallEnabled => _flag('dutch_call', defaultValue: true);

  bool get discardTakeAllowed =>
      _flag('discard_take_allowed', defaultValue: true);

  int get cardsPerHand {
    final raw = deal['cards_per_hand'];
    if (raw is int) return raw < 1 ? 4 : raw;
    final parsed = int.tryParse('$raw');
    return parsed == null || parsed < 1 ? 4 : parsed;
  }

  int get initialPeekCount {
    final raw = deal['initial_peek_count'];
    if (raw is int) return raw < 0 ? 2 : raw;
    final parsed = int.tryParse('$raw');
    return parsed == null || parsed < 0 ? 2 : parsed;
  }

  String get deckSource =>
      (deck['source'] ?? 'standard').toString().trim().toLowerCase();

  int get redKingPoints {
    final raw = scoring['red_king_points'];
    if (raw is int) return raw;
    return int.tryParse('$raw') ?? 10;
  }

  bool get emptyHandWin => _win('empty_hand', defaultValue: true);

  bool get lowestPointsAfterDutchWin =>
      _win('lowest_points_after_dutch', defaultValue: true);

  bool get fourOfAKindCollectionWin =>
      _win('four_of_a_kind_collection', defaultValue: clearAndCollect);

  Map<String, dynamic> toSnapshot() => Map<String, dynamic>.from(_snapshot);

  static GameRulesContext fromGameState(Map<String, dynamic>? gameState) {
    if (gameState == null) {
      return GameRulesContext(_legacyFallback(gameState));
    }
    final rules = gameState['gameplay_rules'];
    if (rules is Map<String, dynamic>) {
      return GameRulesContext(Map<String, dynamic>.from(rules));
    }
    if (rules is Map) {
      return GameRulesContext(
        Map<String, dynamic>.from(rules.map((k, v) => MapEntry(k.toString(), v))),
      );
    }
    return GameRulesContext(_legacyFallback(gameState));
  }

  static Map<String, dynamic> _legacyFallback(Map<String, dynamic>? gameState) {
    final isCC = gameState?['isClearAndCollect'] == true;
    return {
      'profile_id': gameState?['match_class'] ?? 'classic',
      'flags': {
        'clear_and_collect': isCC,
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
        'four_of_a_kind_collection': isCC,
      },
    };
  }
}
