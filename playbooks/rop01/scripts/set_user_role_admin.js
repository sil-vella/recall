// One-off: set user 69ad608e5cfa3eb1703c134a role to "admin".
// Run via: docker exec <container> mongosh -u external_app_user -p "..." --authenticationDatabase external_system /tmp/set_user_role_admin.js
var d = db.getSiblingDB("external_system");
var userId = "69ad608e5cfa3eb1703c134a";
var result = d.users.updateOne(
  { _id: ObjectId(userId) },
  { $set: { role: "admin", updated_at: new Date().toISOString() } }
);
if (result.matchedCount === 0) {
  print("ERROR: User with _id " + userId + " not found");
  quit(1);
}
if (result.modifiedCount === 1) {
  print("OK: Set role to 'admin' for user " + userId);
} else {
  print("OK: User " + userId + " already had role 'admin' (no change)");
}
