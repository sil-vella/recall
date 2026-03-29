# Dutch Leaderboard: Dedicated Match-Win Collection (Option B)

**Status**: In progress  
**Created**: 2026-03-29  
**Last Updated**: 2026-03-29

## Objective

Provide **time-bounded wins** (month / year / arbitrary UTC range) for live and historical leaderboards by storing **authoritative per-match facts** in a **dedicated MongoDB collection**, separate from:

- **`user_events`** — metrics and analytics only; **not** the source of truth for leaderboard rankings.
- **`modules.dutch_game.wins` on `users`** — remains useful for profile and progression, but cumulative totals do **not** answer “wins this month.”

Keep the existing **`leaderboards`** collection as the **frozen snapshot** record for closed periods (audit, “who won March 2026,” disputes). Option B adds the **event stream of wins** so “current period” boards and future snapshot jobs can be based on **wins in period**, not lifetime totals at snapshot time.

## Design decisions (agreed)

| Topic | Decision |
|--------|----------|
| Source of truth for period wins | New collection, written on match completion alongside stats |
| `user_events` | Out of scope for leaderboard semantics |
| Snapshots | Retain; optionally evolve cron to aggregate from new collection for `period_key` closure |
| Granularity | **One document per user per match** where that user **won** (simple counts + idempotency) |

## Proposed collection: `dutch_match_win_outcomes` (name TBD)

Each document represents **one win** by one user in one completed match.

### Fields (draft)

| Field | Type | Notes |
|--------|------|--------|
| `user_id` | ObjectId | Winner’s user id (human or comp accounts in `users`) |
| `room_id` | string | From `update_game_stats` body `room_id` / `game_id` — ties outcome to a single match |
| `ended_at` | datetime (UTC) | When the match completed (use server `datetime.utcnow()` at processing time unless Dart sends explicit `ended_at` — prefer one SSOT) |
| `is_tournament` | bool | From request |
| `tournament_id` | string or null | If tournament |
| `game_mode` | string | Optional copy from `player_result` for filtering later |
| `created_at` | datetime | Insert time (optional; can equal `ended_at`) |

**Idempotency:** unique compound index on `(room_id, user_id)` so duplicate `update_game_stats` deliveries do not double-count wins.

**Losers:** no row (only winners). Tie-break rules for “single winner” are already decided in game logic before `is_winner` is sent.

### Indexes (draft)

- Unique: `(room_id, user_id)` — idempotent insert per match/user.
- Query pattern for “wins in \[start, end)”: `(ended_at, user_id)` or `(ended_at)` + aggregation `$group` by `user_id`.
- Optional filter index if excluding tournaments from a board: `(ended_at, is_tournament)` or partial index.

### Comp players

Period wins **include** computer players when they win (same insert path as humans).

## Write path

- **Location:** `python_base_04/core/modules/dutch_game/api_endpoints.py` — inside **`update_game_stats`**, after a **successful** `users` update for that player (same transaction of trust as stats and coin economy).
- **When:** `is_winner` is true, `room_id` present, stats row updated.
- **Failure policy:** log and optionally soft-fail without failing the whole stats response (or fail closed — product choice); do **not** write to `user_events` for this purpose.

## Read path (new or extended API)

- **Public or authenticated** endpoint: e.g. “leaderboard for period” = aggregate `dutch_match_win_outcomes` where `ended_at` in `[month_start, month_end)` (and same for year), `$group` by `user_id`, `$sum`, join usernames from `users`, sort, limit (e.g. 20).
- **Flutter:** point “current month/year” UI to this aggregate, not only `GET /public/dutch/leaderboards` snapshot list (unless showing **closed** periods only).

## Snapshot job (`snapshot_wins_leaderboard_service`)

- **Today:** uses cumulative `modules.dutch_game.wins` (documented in code as not period-accurate).
- **Future (optional):** for a given `period_key`, compute top N from `dutch_match_win_outcomes` over that calendar month/year in UTC, then write the same shape into `leaderboards` for audit. **Or** keep current behavior for backward compatibility and add a new snapshot metric field — decide when implementing.

## Implementation steps

- [x] Collection name + fields; comp winners included in inserts.
- [ ] Add collection + indexes helper (same pattern as `_ensure_leaderboards_indexes`).
- [ ] Insert winner rows in `update_game_stats` with duplicate-key safe insert.
- [ ] Add aggregation endpoint(s) + query params (`period=monthly|yearly` or `from`/`to` ISO UTC).
- [ ] Wire Flutter leaderboard screen to live endpoint for current period; keep snapshots for past periods if desired.
- [ ] (Optional) Update monthly/yearly cron to snapshot from new collection for true period winners.

## Current progress

- **`ended_at`**: UTC from `datetime.now(timezone.utc)` at `update_game_stats` (one timestamp per request).
- **Writes**: Insert-only into `dutch_match_win_outcomes`; unique `(room_id, user_id)`; `DuplicateKeyError` ignored (idempotent, no races).
- **Reads**: `GET /public/dutch/leaderboard-period-wins?period=monthly|yearly&limit=…` aggregates on each request (no precomputed board).
- **Flutter**: leaderboard screen uses period-wins + snapshot history.

## Next steps

1. Wire Flutter leaderboard to `leaderboard-period-wins` for live month/year.
2. Optional: evolve snapshot cron to use this collection for true period closure.

## Files likely to change

- `python_base_04/core/modules/dutch_game/api_endpoints.py` — insert + new endpoint + index ensure
- `python_base_04/core/modules/dutch_game/dutch_game_main.py` — route registration
- `flutter_base_05/.../leaderboard_screen.dart` (or equivalent) — API for current period
- Playbooks/cron docs if snapshot job behavior changes

## Notes

- `update_game_stats` already receives `game_results` with `user_id`, `is_winner`, `pot`, `game_mode`, and request-level `room_id`, `is_tournament`, `tournament_data` — sufficient to populate outcome rows without new Dart fields unless `ended_at` sync is required.
- **`user_events` / analytics:** leave as-is; do not derive production leaderboard rankings from it.
