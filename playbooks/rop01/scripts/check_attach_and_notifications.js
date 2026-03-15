// Check tournament matches for room_id and recent dutch_room_join notifications
var db = db.getSiblingDB("external_system");
var t = db.tournaments.findOne({});
if (t) {
  print("Tournament: " + t.name);
  var matches = t.matches || [];
  for (var i = 0; i < matches.length; i++) {
    var m = matches[i];
    print("  match_index " + (m.match_index || i) + " room_id: " + (m.room_id || "(empty)"));
  }
} else {
  print("No tournaments");
}
print("---");
print("Recent notifications (dutch_room_join):");
db.notifications.find({ subtype: "dutch_room_join" }).sort({ created_at: -1 }).limit(10).forEach(function(n) {
  print("  user_id=" + n.user_id + " room_id=" + (n.data && n.data.room_id) + " created=" + n.created_at);
});
var count = db.notifications.countDocuments({ subtype: "dutch_room_join" });
print("Total dutch_room_join count: " + count);
