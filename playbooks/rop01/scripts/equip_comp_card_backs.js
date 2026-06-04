/**
 * Bulk-grant and equip card_back cosmetics for comp players on VPS/local Mongo.
 *
 * 1) Pick one random catalog card_back; equip ALL comp players with rank in
 *    expert, veteran, master, elite, legend (95 on full VPS pool).
 * 2) From remaining comp players (other ranks), randomly pick half and equip
 *    each with a random card_back (may differ per player).
 *
 * Run:
 *   mongosh -u external_app_user -p "$MONGODB_PASSWORD" \
 *     --authenticationDatabase external_system --file equip_comp_card_backs.js
 */
var dbx = db.getSiblingDB("external_system");

var CARD_BACK_IDS = [
  "card_back_ember",
  "card_back_ocean",
  "card_back_dragon",
  "card_back_forest",
  "card_back_aurora",
  "card_back_phoenix",
  "card_back_rune",
  "card_back_racing",
  "card_back_gold",
  "card_back_ivory",
  "card_back_cosmic",
  "card_back_nebula",
  "card_back_neon",
  "card_back_vintage",
];

var HIGH_RANKS = ["expert", "veteran", "master", "elite", "legend"];
var now = new Date().toISOString();

function pickRandom(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function normalizeInventory(raw) {
  var inv = raw && typeof raw === "object" ? raw : {};
  var boosters = inv.boosters && typeof inv.boosters === "object" ? inv.boosters : {};
  var cosmetics = inv.cosmetics && typeof inv.cosmetics === "object" ? inv.cosmetics : {};
  var owned = Array.isArray(cosmetics.owned_card_backs) ? cosmetics.owned_card_backs.slice() : [];
  var tables = Array.isArray(cosmetics.owned_table_designs) ? cosmetics.owned_table_designs.slice() : [];
  var eq = cosmetics.equipped && typeof cosmetics.equipped === "object" ? cosmetics.equipped : {};
  return {
    boosters: boosters,
    cosmetics: {
      owned_card_backs: owned.map(String).filter(function (x) {
        return x && x.length > 0;
      }),
      owned_table_designs: tables.map(String).filter(function (x) {
        return x && x.length > 0;
      }),
      equipped: {
        card_back_id: String(eq.card_back_id || ""),
        table_design_id: String(eq.table_design_id || ""),
      },
    },
  };
}

function inventoryWithEquipped(rawInv, backId) {
  var inv = normalizeInventory(rawInv);
  var owned = inv.cosmetics.owned_card_backs;
  if (owned.indexOf(backId) < 0) {
    owned.push(backId);
    owned.sort();
  }
  inv.cosmetics.owned_card_backs = owned;
  inv.cosmetics.equipped.card_back_id = backId;
  return inv;
}

function userRank(u) {
  var dg = u.modules && u.modules.dutch_game ? u.modules.dutch_game : {};
  return String(dg.rank || "").toLowerCase();
}

var sharedBack = pickRandom(CARD_BACK_IDS);
print("Catalog card_back ids (" + CARD_BACK_IDS.length + "): " + CARD_BACK_IDS.join(", "));
print("Shared back for high ranks (" + HIGH_RANKS.join(", ") + "): " + sharedBack);

var allComps = dbx.users.find({ is_comp_player: true }).toArray();
print("Total comp players: " + allComps.length);

var highRankUsers = [];
var remainingUsers = [];

allComps.forEach(function (u) {
  var r = userRank(u);
  if (HIGH_RANKS.indexOf(r) >= 0) {
    highRankUsers.push(u);
  } else {
    remainingUsers.push(u);
  }
});

print(
  "High-rank comps: " +
    highRankUsers.length +
    " | Remaining: " +
    remainingUsers.length
);

// Fisher–Yates shuffle for remaining pool
for (var i = remainingUsers.length - 1; i > 0; i--) {
  var j = Math.floor(Math.random() * (i + 1));
  var tmp = remainingUsers[i];
  remainingUsers[i] = remainingUsers[j];
  remainingUsers[j] = tmp;
}

var halfCount = Math.floor(remainingUsers.length / 2);
var halfSample = remainingUsers.slice(0, halfCount);

print("Equipping random backs for half of remaining: " + halfSample.length);

var bulk = [];
var highRankCounts = {};
var randomBackCounts = {};

highRankUsers.forEach(function (u) {
  var inv = inventoryWithEquipped(
    u.modules && u.modules.dutch_game ? u.modules.dutch_game.inventory : null,
    sharedBack
  );
  bulk.push({
    updateOne: {
      filter: { _id: u._id },
      update: {
        $set: {
          "modules.dutch_game.inventory": inv,
          "modules.dutch_game.last_updated": now,
        },
      },
    },
  });
  highRankCounts[sharedBack] = (highRankCounts[sharedBack] || 0) + 1;
});

halfSample.forEach(function (u) {
  var back = pickRandom(CARD_BACK_IDS);
  var inv = inventoryWithEquipped(
    u.modules && u.modules.dutch_game ? u.modules.dutch_game.inventory : null,
    back
  );
  bulk.push({
    updateOne: {
      filter: { _id: u._id },
      update: {
        $set: {
          "modules.dutch_game.inventory": inv,
          "modules.dutch_game.last_updated": now,
        },
      },
    },
  });
  randomBackCounts[back] = (randomBackCounts[back] || 0) + 1;
});

if (bulk.length === 0) {
  print("Nothing to update.");
  quit(0);
}

var result = dbx.users.bulkWrite(bulk, { ordered: false });
print("bulkWrite matched: " + result.matchedCount + " modified: " + result.modifiedCount);

var equippedTotal = dbx.users.countDocuments({
  is_comp_player: true,
  "modules.dutch_game.inventory.cosmetics.equipped.card_back_id": {
    $exists: true,
    $ne: "",
  },
});
print("Comp players with equipped card_back_id now: " + equippedTotal);
print("Random-back distribution (half sample): " + JSON.stringify(randomBackCounts));
