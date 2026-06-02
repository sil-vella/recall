import 'package:flutter_test/flutter_test.dart';
import 'package:dutch/modules/dutch_game/utils/dutch_game_helpers.dart';
import 'package:dutch/modules/dutch_game/utils/game_ended_modal_pin.dart';
import 'package:dutch/modules/dutch_game/screens/game_play/widgets/messages_widget.dart';

void main() {
  group('shouldKeepEndGameModalVisible', () {
    test('stays pinned when endGameModalOpen is true even if isVisible flickers', () {
      expect(
        DutchGameHelpers.shouldKeepEndGameModalVisible({
          'endGameModalOpen': true,
          'gamePhase': 'playing',
          'messages': {'isVisible': false},
        }),
        isTrue,
      );
    });

    test('legacy pin via Game Ended title and isVisible', () {
      expect(
        DutchGameHelpers.shouldKeepEndGameModalVisible({
          'gamePhase': 'playing',
          'messages': {
            'isVisible': true,
            'title': 'Game Ended',
          },
        }),
        isTrue,
      );
    });

    test('stays pinned when module snapshot is present', () {
      expect(
        DutchGameHelpers.shouldKeepEndGameModalVisible({
          'gamePhase': 'playing',
          'messages': {'isVisible': false},
          GameEndedModalPin.stateKey: {'title': 'Game Ended'},
        }),
        isTrue,
      );
    });

    test('snapshot json round-trip survives state detachment', () {
      final data = GameEndedModalData(
        title: 'Game Ended',
        content: 'Winner(s): test',
        messageType: 'success',
        showCloseButton: true,
        autoClose: false,
        autoCloseDelay: 3000,
        orderedWinners: const [
          {'playerName': 'You', 'winType': 'empty_hand', 'points': 0, 'cards': 0},
        ],
        isCurrentUserWinner: true,
        currentUserId: 'u1',
        gameId: 'room_1',
        showPlayAgain: false,
        rematchGameStateSnapshot: const {},
      );
      final restored = GameEndedModalData.fromJson(data.toJson());
      expect(restored?.title, 'Game Ended');
      expect(restored?.orderedWinners.length, 1);
      expect(restored?.gameId, 'room_1');
    });
  });
}
