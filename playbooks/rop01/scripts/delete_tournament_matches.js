// One-off: delete all matches of the "launch" tournament (keeps participants, user_ids, etc.).
// Run via: playbook or docker exec <container> mongosh ...
var d = db.getSiblingDB("external_system");

var tournament = d.tournaments.findOne({ name: /launch/i });
if (!tournament) {
  print("ERROR: Tournament with name containing 'launch' not found");
  quit(1);
}

var matchCount = (tournament.matches && tournament.matches.length) || 0;
if (matchCount === 0) {
  print("Tournament " + tournament._id + " has no matches; nothing to delete.");
  quit(0);
}

var result = d.tournaments.updateOne(
  { _id: tournament._id },
  { $set: { matches: [], updated_at: new Date().toISOString() } }
);

if (result.modifiedCount === 1) {
  print("OK: Deleted " + matchCount + " match(es) from tournament " + tournament._id);
} else {
  print("WARN: updateOne modified " + result.modifiedCount + " document(s)");
}
