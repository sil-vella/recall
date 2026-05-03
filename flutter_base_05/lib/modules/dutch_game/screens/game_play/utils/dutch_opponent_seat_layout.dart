/// Seat buckets for the round table (must stay in sync with [UnifiedGameBoardWidget]).
///
/// Order (clockwise list index): 1st → left, 2nd → top, 3rd → right; repeats for 4+.
/// Special cases: 1 opponent → left only; 2 → 1st left + 2nd top (no right).
({List<Map<String, dynamic>> top, List<Map<String, dynamic>> left, List<Map<String, dynamic>> right})
bucketOpponentsForDutchTable(List<dynamic> opponents) {
  final list = <Map<String, dynamic>>[];
  for (final o in opponents) {
    if (o is Map<String, dynamic>) {
      list.add(Map<String, dynamic>.from(o));
    }
  }
  if (list.isEmpty) {
    return (top: <Map<String, dynamic>>[], left: <Map<String, dynamic>>[], right: <Map<String, dynamic>>[]);
  }
  if (list.length == 1) {
    return (top: <Map<String, dynamic>>[], left: list, right: <Map<String, dynamic>>[]);
  }
  if (list.length == 2) {
    return (top: [list[1]], left: [list[0]], right: <Map<String, dynamic>>[]);
  }
  final top = <Map<String, dynamic>>[];
  final left = <Map<String, dynamic>>[];
  final right = <Map<String, dynamic>>[];
  for (var i = 0; i < list.length; i++) {
    switch (i % 3) {
      case 0:
        left.add(list[i]);
        break;
      case 1:
        top.add(list[i]);
        break;
      default:
        right.add(list[i]);
    }
  }
  return (top: top, left: left, right: right);
}
