/// One-off verification: known own card matching opponent-known rank is skipped
/// unless dump is allowed (expert dumpProb=0 → never dump when safe exists).
///
/// Run from dart_bkend_base_01:
///   DUTCH_DEV_LOG=1 dart run tool/verify_play_opponent_rank_skip.dart
import 'package:dart_game_server/modules/dutch_game/backend_core/shared_logic/utils/computer_player_factory.dart';
import 'package:dart_game_server/modules/dutch_game/utils/platform/computer_player_config_parser.dart';

Future<void> main() async {
  final config = await ComputerPlayerConfig.fromFile(
    'lib/modules/dutch_game/config/computer_player_config.yaml',
  );
  final factory = ComputerPlayerFactory(config);

  const selfId = 'comp_self';
  const oppId = 'comp_opp';
  const riskyAce = 'card_ace_self';
  const safeTen = 'card_ten_self';
  const oppAce = 'card_ace_opp';

  final currentPlayer = <String, dynamic>{
    'id': selfId,
    'name': 'CPU',
    'difficulty': 'expert',
    'hand': [
      {'cardId': riskyAce, 'rank': 'ace', 'suit': 'hearts', 'points': 1},
      {'cardId': safeTen, 'rank': '10', 'suit': 'clubs', 'points': 10},
    ],
    'collection_rank_cards': <dynamic>[],
    'known_cards': {
      selfId: {
        riskyAce: {
          'cardId': riskyAce,
          'rank': 'ace',
          'suit': 'hearts',
          'points': 1,
          'handIndex': 0,
        },
        safeTen: {
          'cardId': safeTen,
          'rank': '10',
          'suit': 'clubs',
          'points': 10,
          'handIndex': 1,
        },
      },
      oppId: {
        oppAce: {
          'cardId': oppAce,
          'rank': 'ace',
          'suit': 'spades',
          'points': 1,
          'handIndex': 2,
        },
      },
    },
  };

  final gameState = <String, dynamic>{
    'currentPlayer': currentPlayer,
    'players': [currentPlayer],
    'discardPile': [
      {'cardId': 'card_discard', 'rank': '2', 'suit': 'diamonds', 'points': 2},
    ],
    'timerConfig': {'playing_card': 15},
  };

  final available = [riskyAce, safeTen];
  var dumpedRisky = 0;
  var pickedSafe = 0;
  const trials = 40;

  for (var i = 0; i < trials; i++) {
    final decision = factory.getPlayCardDecision('expert', gameState, List<String>.from(available));
    final cardId = decision['card_id']?.toString();
    if (cardId == riskyAce) dumpedRisky++;
    if (cardId == safeTen) pickedSafe++;
  }

  final dumpProb = config.getDumpSameRankAsKnownOpponentProbability('expert');
  print('dumpProb(expert)=$dumpProb trials=$trials pickedSafe=$pickedSafe dumpedRisky=$dumpedRisky');

  if (dumpProb != 0.0) {
    throw StateError('Expected expert dumpProb=0.0, got $dumpProb');
  }
  if (dumpedRisky != 0) {
    throw StateError('Expert dumped risky ace $dumpedRisky/$trials times (expected 0)');
  }
  if (pickedSafe != trials) {
    throw StateError('Expected always safe ten, got pickedSafe=$pickedSafe');
  }
  print('OK: expert never dumped known ace matching opponent-known ace when safe known existed');
}
