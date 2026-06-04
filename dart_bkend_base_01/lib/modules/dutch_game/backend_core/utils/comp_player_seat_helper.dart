/// Helpers to attach equipped cosmetics when seating DB comp players in a match.
library;

/// Reads `modules.dutch_game.inventory.cosmetics.equipped.card_back_id` shape.
String? equippedCardBackIdFromInventory(Map<String, dynamic>? inventory) {
  if (inventory == null) return null;
  final cosmetics = inventory['cosmetics'];
  if (cosmetics is! Map) return null;
  final equipped = cosmetics['equipped'];
  if (equipped is! Map) return null;
  final id = equipped['card_back_id']?.toString().trim() ?? '';
  return id.isEmpty ? null : id;
}

/// Comp roster / get-comp-players payload may include equipped id under either key.
String? equippedCardBackIdFromCompPayload(Map<String, dynamic> comp) {
  final direct = comp['card_back_id']?.toString().trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final equipped = comp['equipped_card_back_id']?.toString().trim();
  if (equipped != null && equipped.isNotEmpty) return equipped;
  final inv = comp['inventory'];
  if (inv is Map<String, dynamic>) {
    return equippedCardBackIdFromInventory(Map<String, dynamic>.from(inv));
  }
  return null;
}

/// Unique display name for a comp seat (avoids collisions in [existingNames]).
String uniqueCompDisplayName(String baseName, Set<String> existingNames) {
  var uniqueName = baseName;
  var suffix = 1;
  while (existingNames.contains(uniqueName)) {
    uniqueName = '$baseName$suffix';
    suffix++;
  }
  existingNames.add(uniqueName);
  return uniqueName;
}

/// Payload first; otherwise loads inventory via [fetchInventoryByUserId] (same as human join).
Future<String?> resolveEquippedCardBackForComp(
  Map<String, dynamic> comp, {
  required Future<Map<String, dynamic>?> Function(String userId) fetchInventoryByUserId,
}) async {
  final fromPayload = equippedCardBackIdFromCompPayload(comp);
  if (fromPayload != null) return fromPayload;
  final userId = (comp['user_id'] ?? '').toString();
  if (userId.isEmpty) return null;
  try {
    final inventory = await fetchInventoryByUserId(userId);
    return equippedCardBackIdFromInventory(inventory);
  } catch (_) {
    return null;
  }
}

/// Game-state player map for a DB comp seat (mirrors human join `card_back_id` field).
Map<String, dynamic> buildCompPlayerSeatEntry({
  required String playerId,
  required String uniqueName,
  required String userId,
  required String username,
  required String email,
  required String difficulty,
  required String rank,
  required int level,
  String? profilePicture,
  String? cardBackId,
}) {
  return {
    'id': playerId,
    'name': uniqueName,
    'isHuman': false,
    'status': 'waiting',
    'hand': <Map<String, dynamic>>[],
    'visible_cards': <Map<String, dynamic>>[],
    'points': 0,
    'known_cards': <String, dynamic>{},
    'collection_rank_cards': <String>[],
    'isActive': true,
    'difficulty': difficulty,
    'rank': rank,
    'level': level,
    'userId': userId,
    'email': email,
    'username': username,
    if (profilePicture != null && profilePicture.isNotEmpty) 'profile_picture': profilePicture,
    if (cardBackId != null && cardBackId.isNotEmpty) 'card_back_id': cardBackId,
  };
}
