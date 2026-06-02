import '../../../../utils/dev_logger.dart';

/// Trims [game_state] fields before WebSocket broadcast to Flutter clients.
///
/// Draw/discard piles use list tail as the visible top ([DutchGameRound] uses
/// [List.removeLast] on draw/discard and [List.add] on discard).
const bool LOGGING_SWITCH = true; // pile-filter testing — revert to false
const int kFrontendPileTailKeep = 2;

int _pileLength(dynamic raw) {
  if (raw is List) return raw.length;
  return 0;
}

/// Last [keep] pile entries, preserving each element's wire shape (Map or id String).
List<dynamic> copyPileTail(List<dynamic> pile, int keep) {
  if (pile.isEmpty) return [];
  final start = pile.length > keep ? pile.length - keep : 0;
  return pile.sublist(start).map((e) {
    if (e is Map<String, dynamic>) return Map<String, dynamic>.from(e);
    if (e is Map) return Map<String, dynamic>.from(e);
    return e;
  }).toList();
}

String _pileTailCardIds(List<dynamic> pile) {
  if (pile.isEmpty) return '[]';
  final ids = <String>[];
  for (final e in pile) {
    if (e is Map) {
      ids.add(e['cardId']?.toString() ?? '?');
    } else {
      ids.add(e?.toString() ?? '?');
    }
  }
  return ids.join(',');
}

/// Drops [originalDeck]; keeps only the top [kFrontendPileTailKeep] draw/discard cards.
Map<String, dynamic> filterGameStateForFrontend(Map<String, dynamic> gameState) {
  final filtered = Map<String, dynamic>.from(gameState);
  filtered.remove('originalDeck');

  final drawRaw = gameState['drawPile'];
  final discardRaw = gameState['discardPile'];
  final drawLen = _pileLength(drawRaw);
  final discardLen = _pileLength(discardRaw);

  filtered['drawPileCount'] = drawLen;
  filtered['discardPileCount'] = discardLen;
  filtered['drawPile'] =
      drawLen > 0 ? copyPileTail(List<dynamic>.from(drawRaw as List), kFrontendPileTailKeep) : <dynamic>[];
  filtered['discardPile'] = discardLen > 0
      ? copyPileTail(List<dynamic>.from(discardRaw as List), kFrontendPileTailKeep)
      : <dynamic>[];

  if (LOGGING_SWITCH &&
      (drawLen > kFrontendPileTailKeep || discardLen > kFrontendPileTailKeep)) {
    final wireDraw = filtered['drawPile'] as List<dynamic>;
    final wireDiscard = filtered['discardPile'] as List<dynamic>;
    customlog(
      'pileFilterTx: draw full=$drawLen wire=${wireDraw.length} '
      'ids=[${_pileTailCardIds(wireDraw)}] '
      'discard full=$discardLen wire=${wireDiscard.length} '
      'ids=[${_pileTailCardIds(wireDiscard)}]',
    );
  }

  return filtered;
}
