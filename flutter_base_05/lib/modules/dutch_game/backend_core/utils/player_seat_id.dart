/// Canonical stable seat id for multiplayer humans (`hum_<userId>`), matching Dart WS backend.
/// Practice mode keeps [sessionId] when it is already `practice_session_<userId>`.
String canonicalMultiplayerHumanPlayerId(String sessionId, String userId) {
  final sid = sessionId.trim();
  if (sid.startsWith('practice_session_')) return sid;
  final u = userId.trim();
  if (u.isEmpty) return sessionId;
  return 'hum_$u';
}
