import 'dart:math'; // Import the math library
import 'package:flutter/material.dart';
import 'package:client/utilities/utility.dart';
import 'package:client/widgets/game_play/msg_board.dart';

class RoomTable extends StatefulWidget {
  final List<int> faceDownCards;
  final List<Map<String, dynamic>> faceUpCards;
  final String lastFaceUpCardRank;
  final String lastFaceUpCardSuit;
  final String gameId;
  final String playerState;
  final bool isClickable;
  final Map<String, dynamic> activeGamePlayState;
  final Map<String, dynamic> msgBoardAndAnim;

  const RoomTable({
    Key? key, // Add the named key parameter here
    required this.faceDownCards,
    required this.faceUpCards,
    required this.lastFaceUpCardRank,
    required this.lastFaceUpCardSuit,
    required this.gameId,
    required this.playerState,
    required this.isClickable,
    required this.activeGamePlayState,
    required this.msgBoardAndAnim,
  }) : super(key: key); // Pass the key to the superclass

  @override
  _RoomTableState createState() => _RoomTableState();
}

class _RoomTableState extends State<RoomTable> {
  final GlobalKey faceDownKey = GlobalKey();
  final GlobalKey faceUpKey = GlobalKey();
  final GlobalKey gameTableKey = GlobalKey();
  bool deckClicked = false;
  double width = 0;
  double height = 0;

  void onClickDeck(String selectedDeck) {
    if (!deckClicked && widget.playerState == 'CHOOSING_DECK') {
      Utility.emitEvent('cardDeckSelected',
          {'selectedDeck': selectedDeck, 'gameId': widget.gameId});
      setState(() {
        deckClicked = true;
      });
    }
  }

  void adjustBorderRadius() {
    if (gameTableKey.currentContext != null) {
      final RenderBox renderBox =
          gameTableKey.currentContext!.findRenderObject() as RenderBox;
      setState(() {
        width = renderBox.size.width;
        height = renderBox.size.height;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      adjustBorderRadius();
    });
  }

  double generateRandomRotation() {
    return (Random().nextDouble() - 0.5) *
        8; // Random number between -4 and 4 degrees
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: gameTableKey,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        color: widget.activeGamePlayState['game_play_state'] == 'GAME_OVER'
            ? Colors.black12
            : Colors.black26,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: GestureDetector(
                  key: faceDownKey,
                  onTap: () => onClickDeck('face_down_deck'),
                  child: Container(
                    // Added Container for bounded constraints
                    height: 150, // Adjust height as needed
                    child: Stack(
                      children:
                          widget.faceDownCards.asMap().entries.map((entry) {
                        int index = entry.key;
                        int card = entry.value;
                        return Positioned(
                          top: index * 0.07,
                          left: index * 0.07,
                          child: Transform.rotate(
                            angle:
                                (index % 5 == 0) ? generateRandomRotation() : 0,
                            child: Container(
                              width: 50,
                              height: 70,
                              color: Colors.blue, // Example color
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  key: faceUpKey,
                  onTap: () => onClickDeck('face_up_deck'),
                  child: Container(
                    // Added Container for bounded constraints
                    height: 150, // Adjust height as needed
                    child: Stack(
                      children: widget.faceUpCards.asMap().entries.map((entry) {
                        int index = entry.key;
                        Map<String, dynamic> card = entry.value;
                        return Positioned(
                          top: index * 0.07,
                          left: index * 0.07,
                          child: Transform.rotate(
                            angle:
                                (index % 5 == 0) ? generateRandomRotation() : 0,
                            child: Container(
                              width: 50,
                              height: 70,
                              color: Colors.red, // Example color
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(Utility.getSuitEntity(
                                      widget.lastFaceUpCardSuit)),
                                  Text(widget.lastFaceUpCardRank),
                                  Text(Utility.getSuitEntity(
                                      widget.lastFaceUpCardSuit)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          MsgBoardMain(msgBoardAndAnim: widget.msgBoardAndAnim),
        ],
      ),
    );
  }
}
