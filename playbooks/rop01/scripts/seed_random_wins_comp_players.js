/**
 * One-off: for each listed comp-player user_id, add a random count K in [1,8] of
 * insert-only rows to dutch_match_win_outcomes and sync users.modules.dutch_game
 * (wins, total_matches, win_rate, level, rank) with Python WinsLevelRankMatcher defaults.
 *
 * Each synthetic win's ended_at is a random instant on 1 April 2026 UTC
 * (inclusive range from 00:00:00.000Z through 23:59:59.999Z).
 *
 * Run (on host with Docker Mongo):
 *   mongosh -u external_app_user -p "$MONGODB_PASSWORD" --authenticationDatabase external_system --file seed_random_wins_comp_players.js
 */
var dbx = db.getSiblingDB("external_system");
var coll = dbx.dutch_match_win_outcomes;

var WINS_PER = 10;
var LEVELS_PER_RANK = 5;
var USER_LEVEL_MIN = 1;
var RANK_HIERARCHY = "beginner,novice,apprentice,skilled,advanced,expert,veteran,master,elite,legend".split(",");

function winsToLevel(w) {
  w = w < 0 ? 0 : Math.floor(w);
  return Math.max(USER_LEVEL_MIN, 1 + Math.floor(w / WINS_PER));
}
function levelToRankIndex(lv) {
  lv = Math.max(USER_LEVEL_MIN, Math.floor(lv));
  var idx = Math.floor((lv - 1) / LEVELS_PER_RANK);
  return Math.min(RANK_HIERARCHY.length - 1, Math.max(0, idx));
}
function levelToRank(lv) {
  return RANK_HIERARCHY[levelToRankIndex(lv)];
}
function rankIndexFromStoredRank(stored) {
  if (!stored) return 0;
  var s = String(stored).toLowerCase();
  var i = RANK_HIERARCHY.indexOf(s);
  return i < 0 ? 0 : i;
}

/** Uniform random BSON Date within 2026-04-01 UTC (whole calendar day). */
var APR_2026_START_MS = Date.UTC(2026, 3, 1, 0, 0, 0, 0);
var APR_2026_END_MS = Date.UTC(2026, 3, 1, 23, 59, 59, 999);
function randomEndedAtAprilFirst2026Utc() {
  var span = APR_2026_END_MS - APR_2026_START_MS + 1;
  return new Date(APR_2026_START_MS + Math.floor(Math.random() * span));
}

var ids = [
  ObjectId("69a76d68a2bc2c7437de56a6"),
  ObjectId("69a76d68a2bc2c7437de56a7"),
  ObjectId("69a76d68a2bc2c7437de56a8"),
  ObjectId("69a76d68a2bc2c7437de56a9"),
  ObjectId("69a76d68a2bc2c7437de56aa"),
  ObjectId("69a76d68a2bc2c7437de56ab"),
  ObjectId("69a76d68a2bc2c7437de56ac"),
  ObjectId("69a76d68a2bc2c7437de56ad"),
  ObjectId("69a76d68a2bc2c7437de56ae"),
  ObjectId("69a76d68a2bc2c7437de56af"),
  ObjectId("69a76d7ca2bc2c7437de5728"),
  ObjectId("69a76d7ca2bc2c7437de5729"),
  ObjectId("69a76d7ca2bc2c7437de572a"),
  ObjectId("69a76d7ca2bc2c7437de572b"),
  ObjectId("69a76d7ca2bc2c7437de572c"),
  ObjectId("69a76db2a2bc2c7437de580e"),
  ObjectId("69a76db2a2bc2c7437de580f"),
  ObjectId("69a76db2a2bc2c7437de5810"),
  ObjectId("69a76db2a2bc2c7437de5811"),
  ObjectId("69a76db2a2bc2c7437de5812"),
];

var summary = [];

ids.forEach(function (uid, uidx) {
  var n = Math.floor(Math.random() * 8) + 1;
  var maxEndedMs = 0;
  for (var i = 0; i < n; i++) {
    var endedAt = randomEndedAtAprilFirst2026Utc();
    var t = endedAt.getTime();
    if (t > maxEndedMs) maxEndedMs = t;
    var roomId =
      "seed_apr2026_" +
      uid.toString() +
      "_" +
      uidx +
      "_" +
      i +
      "_" +
      Math.random().toString(36).slice(2, 12);
    try {
      coll.insertOne({
        room_id: roomId,
        user_id: uid,
        ended_at: endedAt,
        is_tournament: false,
        tournament_id: null,
        game_mode: "seed_batch_apr2026",
      });
    } catch (e) {
      if (e.code === 11000) {
        roomId = roomId + "_dupfix_" + Math.random().toString(36).slice(2);
        coll.insertOne({
          room_id: roomId,
          user_id: uid,
          ended_at: endedAt,
          is_tournament: false,
          tournament_id: null,
          game_mode: "seed_batch_apr2026",
        });
      } else {
        throw e;
      }
    }
  }
  var latestIso = new Date(maxEndedMs).toISOString();

  var u = dbx.users.findOne({ _id: uid }, { modules: 1, username: 1 });
  if (!u) {
    summary.push({ user_id: uid.toString(), error: "user not found" });
    return;
  }
  var dg = (u.modules && u.modules.dutch_game) || {};
  var curWins = Math.max(0, parseInt(dg.wins, 10) || 0);
  var curLosses = Math.max(0, parseInt(dg.losses, 10) || 0);
  var curTotal = Math.max(0, parseInt(dg.total_matches, 10) || 0);
  var newWins = curWins + n;
  var newTotal = curTotal + n;
  var newWinRate = newTotal > 0 ? newWins / newTotal : 0;
  var targetLevel = winsToLevel(newWins);
  var targetRank = levelToRank(targetLevel);
  var idxTarget = levelToRankIndex(targetLevel);
  var idxStored = rankIndexFromStoredRank(dg.rank);
  var setDoc = {
    "modules.dutch_game.wins": newWins,
    "modules.dutch_game.total_matches": newTotal,
    "modules.dutch_game.win_rate": newWinRate,
    "modules.dutch_game.level": targetLevel,
    "modules.dutch_game.last_updated": latestIso,
    "modules.dutch_game.last_match_date": latestIso,
    updated_at: latestIso,
  };
  if (idxTarget > idxStored) {
    setDoc["modules.dutch_game.rank"] = targetRank;
  }
  dbx.users.updateOne({ _id: uid }, { $set: setDoc });
  summary.push({
    username: u.username,
    user_id: uid.toString(),
    added_outcomes: n,
    new_wins: newWins,
    new_total_matches: newTotal,
    level: targetLevel,
    rank: (idxTarget > idxStored) ? targetRank : dg.rank,
  });
});

print(JSON.stringify({ ok: true, users: summary }, null, 2));
