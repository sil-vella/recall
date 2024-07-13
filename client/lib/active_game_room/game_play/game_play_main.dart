import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client/utilities/utility.dart';
import 'package:client/active_game_room/game_play/room_table.dart';
import 'package:client/game_state.dart';

class GamePlayMain extends StatelessWidget {
  const GamePlayMain({super.key});

  void handleCardClick(Map<String, dynamic> card, String playerId,
      String playerState, String gameId) {
    Utility.handleCardClick(card['id'], playerId, playerState, gameId);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        // Logging the state each time the widget loads
        print('activeGamePlayState: ${gameState.activeGamePlayState}');
        print('userSection: ${gameState.userSection}');
        print('messageAnimation: ${gameState.messageAnimation}');

        final activeGamePlayState = gameState.activeGamePlayState;
        final userSection = gameState.userSection;
        final msgBoardAndAnim = gameState.messageAnimation;

        String gameId = activeGamePlayState['game_id'] ?? '';
        String playerState = userSection['state'] ?? '';

        List<int> faceDownCards =
            (activeGamePlayState['face_down_cards'] ?? []).cast<int>();
        List<Map<String, dynamic>> faceUpCards =
            (activeGamePlayState['face_up_cards'] ?? [])
                .cast<Map<String, dynamic>>();
        String lastFaceUpCardRank =
            faceUpCards.isNotEmpty ? faceUpCards.last['rank'] : 'None';
        String lastFaceUpCardSuit =
            faceUpCards.isNotEmpty ? faceUpCards.last['suit'] : 'None';
        Map<String, dynamic> players =
            Map<String, dynamic>.from(activeGamePlayState['players'] ?? {});
        players.removeWhere((key, value) => value['id'] == userSection['id']);

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: players.entries.map((entry) {
                      final player = entry.value;
                      return Column(
                        children: [
                          Container(
                              width: 50,
                              height: 50,
                              color: Colors.blue), // Player avatar
                          Row(
                            children: player['hand'].map<Widget>((card) {
                              return GestureDetector(
                                onTap: () => handleCardClick(
                                    card, player['id'], playerState, gameId),
                                child: Container(
                                  width: 50,
                                  height: 70,
                                  color: Colors.red,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            RoomTable(
              faceDownCards: faceDownCards,
              faceUpCards: faceUpCards,
              lastFaceUpCardRank: lastFaceUpCardRank,
              lastFaceUpCardSuit: lastFaceUpCardSuit,
              gameId: gameId,
              playerState: playerState,
              isClickable: Utility.isClickable,
              activeGamePlayState: activeGamePlayState,
              msgBoardAndAnim: msgBoardAndAnim,
            ),
          ],
        );
      },
    );
  }
}
