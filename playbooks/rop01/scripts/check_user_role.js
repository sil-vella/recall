// Check user 69ad608e5cfa3eb1703c134a in external_system.users (role and _id type)
var d = db.getSiblingDB("external_system");
var userId = "69ad608e5cfa3eb1703c134a";
var u = d.users.findOne({ _id: ObjectId(userId) });
if (!u) u = d.users.findOne({ _id: userId });
if (!u) {
  print("User " + userId + " NOT FOUND (tried ObjectId and string _id)");
  print("Total users in collection: " + d.users.countDocuments());
  var sample = d.users.findOne();
  if (sample) print("Sample _id type: " + typeof sample._id + " value: " + sample._id);
  quit(1);
}
print("=== USER (VPS) ===");
print("_id: " + u._id + " (type: " + typeof u._id + ")");
print("username: " + (u.username || "(missing)"));
print("email: " + (u.email || "(missing)"));
print("role: " + (u.role || "(missing)"));
printjson(u);
