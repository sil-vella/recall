# User playing habits (current implementation)

How to derive **when** and **how often** users play from data we already collect. No new pipelines — Mongo + Firebase GA4 only.

**Related:**
- [FIREBASE_IMPLEMENTATION.md](./FIREBASE_IMPLEMENTATION.md) — GA4 events and `setUserId`
- [COLLECTION_FLOW.md](./COLLECTION_FLOW.md) — `user_events` → Prometheus
- [METRICS_DEFINITIONS.md](./METRICS_DEFINITIONS.md) — game metric names

---

## 1. Data sources (SSOT map)

| Habit signal | Best source | Identity key | Notes |
|--------------|-------------|--------------|--------|
| Match **ended** (every player in multiplayer stats update) | Mongo `user_events` (`event_type: game_completed`) | `user_id` (Mongo id string) | Written in `update_game_stats` per row in `game_results` |
| Match **ended** (client) | Firebase `match_completed` | GA4 user id = same Mongo id via `AnalyticsService.setUserId` | Once per `game_id` per app session; params include `result`, `game_type`, `match_type`, `source` |
| Match **start intent** | Firebase `start_match_tapped` | GA4 user id | Tap on Start Match; not stored in Mongo |
| Last finished match only | `users.modules.dutch_game.last_match_date` | user `_id` | **Overwrite** each finish — not a history |
| Win history with end time | Mongo `dutch_match_win_outcomes.ended_at` | `user_id` | **Winners only** |
| Match **duration** (length of that game) | `game_results.duration_seconds` → `user_events.event_data.duration` / win outcome rows | `user_id` | From in-memory `match_play_started_at_ms` at end; not a calendar start history |
| Aggregates | `users.modules.dutch_game` (`total_matches`, `wins`, `losses`, `win_rate`, streaks, …) | user `_id` | Lifetime counters, not a timeline |

**Username is not on Firebase events.** Join Mongo `users.username` ↔ `user_id` / GA4 user id when you need a display name.

---

## 2. Habit metrics you can compute today

### 2.1 Time between matches (inter-match gap)

**Question:** How long after finishing a match until they play another?

**Mongo (preferred for backend reports):**

1. Query `user_events` where `event_type == "game_completed"` and `user_id == <id>`.
2. Sort by `timestamp` (ISO) or `created_at` ascending.
3. Gapₙ = `timestamp[n+1] − timestamp[n]`  
   → distribution of “time until next match **end**” (or next completed game).

**Firebase:**

1. Export / Explore `match_completed` for that user id.
2. Same consecutive-diff on GA4 event timestamps.

**Not sufficient alone:** `last_match_date` (single value).

**Caveat:** This is gap between **completions**, not “hours since they closed the app.” A long gap can mean churn or simply not opening the app.

### 2.2 Time from finish → next start

**Question:** After a match ends, how long until they tap Start Match again?

1. Pair Firebase `match_completed` (event time T₁) with the next `start_match_tapped` (T₂) for the same user id.
2. Gap = T₂ − T₁.

Mongo does **not** store start taps; this habit is **Firebase-only** today.

### 2.3 Session / same-day play frequency

**Question:** How many matches per day / week?

- Count `user_events` `game_completed` (or Firebase `match_completed`) grouped by `user_id` and calendar day (UTC from `timestamp` / GA4 time).
- Optional filter: `event_data.game_mode`, Firebase `match_type` (`practice` / `multiplayer`), `game_type` (`classic` / `clear_and_collect`), `source` (`create_room` / `join_room` / `random_join` / `practice`).

### 2.4 Recency / “still active”

**Question:** When did they last finish a match?

- Fast path: `users.modules.dutch_game.last_match_date`.
- Or: `max(timestamp)` on that user’s `game_completed` events (more reliable if you need auditability).

### 2.5 Match length habits

**Question:** How long do their matches last?

- Per finish: `event_data.duration` on backend `game_completed`, or `duration_seconds` on win rows in `dutch_match_win_outcomes`.
- Aggregate: average / p50 / p90 duration per user or cohort.

This is **in-match duration**, not inter-match gap.

### 2.6 Win / loss mix over time

- `user_events.event_data.result` ∈ `{win, loss}` on `game_completed`.
- Firebase `match_completed.result`.
- Lifetime: `users.modules.dutch_game.wins` / `losses` / `total_matches` (no per-day history unless you use events).

### 2.7 Wins-only dated timeline

`dutch_match_win_outcomes` (`ended_at`, `room_id`, `user_id`, `game_type`, …) is good for leaderboards and “when did they win?” — **not** for full play cadence (losses omitted).

---

## 3. Example queries (conceptual)

### Mongo — last 20 match ends for a user

```js
db.user_events.find(
  { user_id: "<mongoObjectIdString>", event_type: "game_completed" },
  { timestamp: 1, created_at: 1, event_data: 1, _id: 0 }
).sort({ created_at: 1 }).limit(20)
```

### Mongo — inter-match gaps (sketch)

```js
// Pseudocode: load sorted timestamps, then
// gaps[i] = timestamps[i+1] - timestamps[i]
```

### Firebase / BigQuery (if linked)

- Table: `events_*` filtered by `event_name IN ('match_completed', 'start_match_tapped')` and `user_id`.
- Window: `LAG(event_timestamp)` over `(user_id ORDER BY event_timestamp)`.

---

## 4. Identity and joins

| System | User key |
|--------|----------|
| Mongo `users` | `_id` |
| Mongo `user_events` | `user_id` (string form of `_id`) |
| Firebase GA4 | `user_id` set at login (`AnalyticsService.setUserId`) |
| Display name | `users.username` (not on GA4 event params) |

Always join habits reports on **user id**, then attach username from Mongo if needed.

---

## 5. What we do **not** have yet

| Gap | Impact |
|-----|--------|
| No full match-history collection with `started_at` + `ended_at` for every game | No first-class “match session” document; reconstruct from events |
| No Mongo event for `start_match_tapped` | Finish→start delay is Firebase-only |
| `last_match_date` overwrite | Cannot rebuild history from the user doc alone |
| Firebase events lack `username` | Must join to Mongo for names |
| Prometheus game counters | Good for totals/rates, not per-user timelines |

---

## 6. Recommended habit definitions (product)

Use these names consistently in dashboards:

| Habit KPI | Definition (current impl) |
|-----------|---------------------------|
| **Inter-match interval** | Δt between consecutive `game_completed` / `match_completed` for the same user |
| **Return-to-start interval** | Δt from `match_completed` → next `start_match_tapped` (Firebase) |
| **Matches per day** | Count of `game_completed` (or `match_completed`) per user per UTC day |
| **Days since last match** | `now − last_match_date` (or max event time) |
| **Avg match length** | Mean `duration` / `duration_seconds` over finishes in the window |

---

## 7. Code touchpoints

| Piece | Location |
|-------|----------|
| Set `last_match_date` + backend `game_completed` | `python_base_04/core/modules/dutch_game/api_endpoints.py` → `update_game_stats` |
| Insert `user_events` | `python_base_04/core/services/analytics_service.py` → `track_event` |
| Win rows + `ended_at` | same `api_endpoints.py` → `dutch_match_win_outcomes` |
| Client `game_completed` + Firebase match | `flutter_base_05/.../dutch_event_handler_callbacks.dart` |
| GA4 match / start events | `flutter_base_05/.../dutch_firebase_analytics.dart` |
| GA4 user id | `flutter_base_05/lib/utils/analytics_service.dart` + login module |

---

**Status:** Documents **current** behavior only. Extending habits (e.g. persist match start in Mongo) would be a separate implementation change.
