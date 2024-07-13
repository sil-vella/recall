import 'package:client/services/socket_service.dart';
import 'msg_list.dart';

class Utility {
  static void emitEvent(String eventName, Map<String, dynamic> data) {
    SocketService.emitEvent(eventName, data);
  }

  static List<Map<String, String>> specialPlayCards = [];
  static bool isClickable = false;

  static void handleCardClick(
      String cardId, String playerId, String playerState, String gameId) {
    specialPlayCards.add({'cardId': cardId, 'playerId': playerId});

    if ((playerState == 'JACK_SPECIAL' && specialPlayCards.length == 2) ||
        (playerState == 'QUEEN_SPECIAL' && specialPlayCards.length == 1)) {
      emitEvent('specialRankPlay', {
        'newSelectedCards': List<Map<String, String>>.from(specialPlayCards),
        'playerState': playerState,
        'gameId': gameId
      });
      specialPlayCards.clear();
    } else if (playerState == 'REVEAL_CARDS') {
      if (specialPlayCards.length == 2) {
        emitEvent('revealFirstCards', {
          'newSelectedCards': List<Map<String, String>>.from(specialPlayCards),
          'playerState': playerState,
          'gameId': gameId
        });
        specialPlayCards.clear();
      }
    } else if (playerState == 'CHOOSING_CARD') {
      emitEvent('cardToPlay', {
        'newSelectedCards': List<Map<String, String>>.from(specialPlayCards),
        'gameId': gameId
      });
      specialPlayCards.clear();
    } else if (playerState == 'SAME_RANK_WINDOW') {
      emitEvent('playSameRank', {
        'newSelectedCards': List<Map<String, String>>.from(specialPlayCards),
        'gameId': gameId
      });
      specialPlayCards.clear();
    }
  }

  static String getRoomIdFromUrl() {
    final url = Uri.base.toString();
    final regex = RegExp(r'[?&]room=([^&#]*)', caseSensitive: false);
    final match = regex.firstMatch(url);

    if (match != null && match.group(1) != null) {
      return match.group(1)!; // Return the value of the "room" parameter
    }
    return ''; // Return an empty string if "room" is not found
  }

  static String getSuitEntity(String suit) {
    switch (suit.toLowerCase()) {
      case 'spades':
        return '♠';
      case 'clubs':
        return '♣';
      case 'hearts':
        return '♥';
      case 'diamonds':
        return '♦';
      default:
        return '';
    }
  }

  static String formatMessage(String msgId, Map<String, dynamic> replacements) {
    final messageTemplate = msgList.firstWhere(
      (msg) => msg['id'] == msgId,
      orElse: () => {'msg': ''},
    )['msg'];
    if (messageTemplate == null || messageTemplate.isEmpty) {
      return ''; // Handle case where message template is not found
    }

    String replacer(Match match) {
      final key = match.group(1);
      final value = replacements[key];

      if (value is Map &&
          value.containsKey('rank') &&
          value.containsKey('suit')) {
        return '${value['rank']} of ${value['suit']}';
      }
      return value?.toString() ?? '';
    }

    final regex = RegExp(r'{(\w+)}');
    return messageTemplate.replaceAllMapped(regex, replacer);
  }
}
