import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client/utilities/utility.dart';
import 'package:client/game_state.dart';

class UserSectionHand extends StatefulWidget {
  @override
  _UserSectionHandState createState() => _UserSectionHandState();
}

class _UserSectionHandState extends State<UserSectionHand> {
  List<String> selectedCards = [];

  void handleCardClick(String cardId) {
    final userSection = context.read<GameState>().userSection;
    final playerId = userSection['id'];
    final gameId = context.read<GameState>().gameId;
    final playerState = userSection['state'];

    Utility.handleCardClick(cardId, playerId, playerState, gameId);

    if (playerState == 'REVEAL_CARDS') {
      setState(() {
        selectedCards.add(cardId);
        if (selectedCards.length == 2) {
          selectedCards.clear(); // Reset after handling in Utility
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        final userSection = gameState.userSection;
        final hand = userSection['hand'] ?? [];
        final state = userSection['state'] ?? 'IDLE';

        return Column(
          children: [
            Text(_getNextActionMessage(state)),
            Row(
              children: hand.map<Widget>((card) {
                return GestureDetector(
                  onTap: () => handleCardClick(card),
                  child: Container(
                    width: 50,
                    height: 70,
                    color: Colors.red, // Placeholder for card appearance
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  String _getNextActionMessage(String state) {
    switch (state) {
      case 'IDLE':
        return 'Idle Player';
      case 'REVEAL_CARDS':
        return 'Select ${2 - selectedCards.length} card(s) to reveal.';
      case 'SHOW_FIRST_CARDS':
        return 'Show First Cards';
      case 'CHOOSING_DECK':
        return 'Choose draw deck.';
      case 'CHOOSING_CARD':
        return 'Choose card to play.';
      case 'SAME_RANK_WINDOW':
        return 'Play same rank?';
      case 'JACK_SPECIAL':
        return "Played Jack. Choose 2 cards from your or other player's hand for Jack Swap.";
      case 'QUEEN_SPECIAL':
        return "Played Queen. Choose a card from your or other player's hand to look at.";
      default:
        return '';
    }
  }
}
