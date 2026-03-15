// Verify launch tournament: participants (with is_comp_player) and first match players.
var d = db.getSiblingDB("external_system");
var t = d.tournaments.findOne({ name: /launch/i });
if (!t) {
  print("ERROR: No tournament with name matching /launch/i");
  quit(1);
}
print("Tournament: _id=" + t._id + " name=" + (t.name || ""));
print("participants (" + (t.participants ? t.participants.length : 0) + "):");
if (t.participants) {
  t.participants.forEach(function(p, i) {
    print("  [" + i + "] user_id=" + (p.user_id || p._id) + " username=" + (p.username || "") + " is_comp_player=" + (p.is_comp_player === true));
  });
}
var matches = t.matches || [];
print("matches: " + matches.length);
if (matches.length > 0) {
  var m = matches[0];
  print("  match_index=" + m.match_index + " players: " + (m.players ? m.players.length : 0));
  if (m.players) {
    m.players.forEach(function(p, i) {
      print("    [" + i + "] user_id=" + (p.user_id || p._id) + " username=" + (p.username || "") + " is_comp_player=" + (p.is_comp_player === true));
    });
  }
}
