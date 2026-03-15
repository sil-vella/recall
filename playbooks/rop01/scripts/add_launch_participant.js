// One-off: find 3 computer players and add them to the "launch" tournament's participants.
// Run via: docker exec <container> mongosh ...
var d = db.getSiblingDB("external_system");

var compPlayers = d.users.find({ is_comp_player: true }).limit(3).toArray();
if (compPlayers.length === 0) {
  print("ERROR: No computer players found");
  quit(1);
}
print("Found " + compPlayers.length + " computer player(s)");

var tournament = d.tournaments.findOne({ name: /launch/i });
if (!tournament) {
  print("ERROR: Tournament with name containing 'launch' not found");
  quit(1);
}
print("Tournament: _id=" + tournament._id + (tournament.name ? " name=" + tournament.name : ""));

var participants = tournament.participants ? tournament.participants.slice() : [];
var userIds = tournament.user_ids ? tournament.user_ids.map(function(x) { return x; }) : [];

for (var i = 0; i < compPlayers.length; i++) {
  var p = compPlayers[i];
  var uidStr = p._id.toString();
  var existingIdx = -1;
  for (var k = 0; k < participants.length; k++) {
    if ((participants[k].user_id || (participants[k]._id && participants[k]._id.toString())) === uidStr) {
      existingIdx = k;
      break;
    }
  }
  if (existingIdx === -1) {
    var entry = { user_id: uidStr, username: p.username || "", is_comp_player: true };
    if (p.email) entry.email = p.email;
    participants.push(entry);
    print("  Adding participant: " + uidStr + " (" + (p.username || "") + ")");
  } else {
    // Update existing participant so comp players have is_comp_player: true
    participants[existingIdx].is_comp_player = true;
    if (p.username) participants[existingIdx].username = p.username;
    print("  Updated participant: " + uidStr + " -> is_comp_player=true");
  }
  var alreadyInUserIds = userIds.some(function(id) { return id.toString() === uidStr; });
  if (!alreadyInUserIds) {
    userIds.push(p._id);
  }
}

var result = d.tournaments.updateOne(
  { _id: tournament._id },
  { $set: { participants: participants, user_ids: userIds, updated_at: new Date().toISOString() } }
);

if (result.modifiedCount === 1) {
  print("OK: Updated tournament " + tournament._id + " with " + participants.length + " participant(s)");
} else {
  print("WARN: updateOne modified " + result.modifiedCount + " document(s)");
}
