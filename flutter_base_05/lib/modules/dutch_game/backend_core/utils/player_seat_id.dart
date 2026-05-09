/// Canonical stable seat id for multiplayer humans (`hum_<userId>`), matching Dart WS backend.
String canonicalMultiplayerHumanPlayerId(String sessionId, String userId) {
  final u = userId.trim();
  if (u.isEmpty) return sessionId;
  return 'hum_$u';
}
