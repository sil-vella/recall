# Dutch rematch tournament — implementation plan

**Status**: In progress (planning)  
**Created**: 2026-03-20  
**Last updated**: 2026-03-21 (instant WS modal wiring)

## Frontend: `rematch` WebSocket (implemented)

- Game-ended modal ([`flutter_base_05/.../messages_widget.dart`](../../flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/messages_widget.dart)): **Play Again** when `is_random_game` is not true (else falls back to `is_random_join`); hidden for `practice_room_` / `demo_game_` ids.
- Emits **`rematch`** via [`DutchGameEventEmitter`](../../flutter_base_05/lib/modules/dutch_game/managers/validated_event_emitter.dart) with `game_id` + `game_state` snapshot (same client path as `play_card`, etc. — **not** the Flutter `game_event_coordinator`; the Dart **server** `message_handler` should accept the event and delegate to coordinator after validation).

### Rematch invite instant modal (implemented, not yet tested)

- **Problem:** `restart_invite` / `instant_ws` payloads were queued in [`NotificationsModule.addPendingWsInstant`](../../flutter_base_05/lib/modules/notifications_module/notifications_module.dart) but only drained when [`BaseScreenState._checkAndShowInstantMessages`](../../flutter_base_05/lib/core/00_base/screen_base.dart) ran (first frame + ~20s periodic poll), so the invite modal could lag behind other UI updates.
- **Change:** Listeners on `NotificationsModule` notify when a pending WS instant is added; each [`BaseScreenState`](../../flutter_base_05/lib/core/00_base/screen_base.dart) registers to drain and show [`InstantMessageModal`](../../flutter_base_05/lib/core/widgets/instant_message_modal.dart) on the next frame—same path as the existing instant notification system, without waiting for the poll.
- **Status:** Implemented in code; **manual / automated testing still pending.**

## Backend (pending)

- **`dart_bkend_base_01`:** Add `rematch` case in WebSocket routing ([`message_handler.dart`](../../dart_bkend_base_01/lib/server/message_handler.dart)), validate session/room, then forward to coordinator / game logic.
- Optional: set `is_random_game` on game state when applicable so the modal predicate matches product naming.

## Objective

Implement rematch flow for tournament matches with correct persistence, scoring, and room lifecycle, while keeping tournament metadata consistent for filtering and reporting.

## Rematch entry: `isTournament` check (first step)

On rematch, determine whether the game that just ended was already a **tournament** match using the same flag used in game state / room payload (e.g. **`is_tournament`** / **`isTournament`** — align naming with Dart backend `gameState['is_tournament']` and any rematch handler).

| Condition | Action |
|-----------|--------|
| **`isTournament` is false** | **Create** a new tournament document **as already planned** (`type`: `online`, `format`: `single_room_league`), including the **finished** match and its data. This is the path from a **non-tournament** game into a rematch tournament. |
| **`isTournament` is true** | **Do not** create a new tournament. **Update** the existing tournament document **according to that tournament’s `format`** (see below). |

## Scope (format-specific behavior)

- **`single_room_league`:** Use the persistence rules in [Rematch persistence](#rematch-persistence-single_room_league-only) (append-after-finish, no pre-created next row, no update-by-`match_id` for repeated rematch iterations). Applies both when **creating** the first tournament (non-tournament → rematch) and when **updating** an existing tournament that already has this format.
- **Other formats** (`League`, `Cup`, etc.): On rematch when `isTournament` is true, **update** using the existing match semantics for that format (e.g. find match by id / index and update in place where that is already defined). Do **not** apply the `single_room_league`-only append rules to those formats.

## Tournament metadata (rematch-specific)

For tournaments created or labeled as **rematch** logic:

| Field    | Value                 | Notes |
|----------|----------------------|--------|
| `type`   | `online`             | Rematch tournaments are online (not IRL). |
| `format` | `single_room_league` | New format value; distinct from existing `League` / `Cup` docs in DB. Admin UI filters may need extending to include this format. |

**Implementation requirement:** When rematch creates or updates a tournament document (or a dedicated rematch tournament), set `type` and `format` to these values so they are stored and returned by `get-tournaments` / service endpoints. Align casing (e.g. lowercase `online` vs title case `Online`) with a single convention across API + Flutter filters.

Current `create_tournament_in_db` in [`python_base_04/core/modules/dutch_game/api_endpoints.py`](../../python_base_04/core/modules/dutch_game/api_endpoints.py) does not persist `type` or `format`; rematch work should extend creation/update paths to write these fields and optionally validate allowed pairs.

## Rematch persistence (`single_room_league` only)

Applies when the tournament **`format`** is **`single_room_league`**, whether the operation is **create** (`isTournament` false) or **update** (`isTournament` true).

1. **Create path** (`isTournament` false): **Create tournament** as already planned (`type`: `online`, `format`: `single_room_league`), and include the **finished** match **and its full data** (scores, players, status completed, etc.) for the game that just ended.
2. **Do not** insert the **next** match row in MongoDB yet at this step. Rematch reuses the **same logical `match_id`** for the upcoming game, so there is no second row to “prepare” in advance.
3. **After** that next game **finishes**, persist it by **appending a new match** to `tournaments.matches` (insert/add match). **Do not** load a match by `match_id` and update in place — with repeated rematches, **all iterations share the same id**, so find-by-id + update would be wrong or ambiguous.
4. **Update path** (`isTournament` true, `format` is `single_room_league`): Follow the same append-after-finish rules when recording each completed rematch round (append new match document; do not update-in-place by shared `match_id`).
5. Net effect: history is **append-only** per completed game; each completion adds a match document; the “live” rematch slot does not get a new DB row until the round completes.

**Implementation note:** Contrast with classic league/cup flows where `match_id` is unique per row and update-by-id is safe — `single_room_league` rematch must branch on `format` and use append-after-finish for subsequent rounds.

## Open design items (from prior discussion)

1. **Room strategy:** New `room_id` per rematch match vs reusing the same `room_id` (affects attach + game lifecycle). Revisit in light of same `match_id` + append-only DB rows for `single_room_league`.
2. **Score API:** Persist full match scores (`scores[]` / `players.points`) and completed status; align with `_record_tournament_match_result`.
3. **Caller auth:** Service key from Dart vs JWT route for non-admin players invoking rematch-related endpoints.
4. **Leaderboard source:** Confirm whether leaderboard is derived from `tournaments.matches` only or another store.

## Next steps

- Implement rematch handler: **read `isTournament`** → **create** vs **update** branch.
- **Create branch:** new tournament (`online` / `single_room_league`) + finished match data; `single_room_league` append rules for later rounds.
- **Update branch:** dispatch on stored tournament **`format`**; `single_room_league` uses append rules; other formats use existing update-by-match semantics.
- Add `type` / `format` persistence and validation where missing.
- Update Flutter admin tournament filters if `single_room_league` should appear as its own format chip.
- Resolve the four design items above in implementation order.

## Files likely touched

- [`python_base_04/core/modules/dutch_game/api_endpoints.py`](../../python_base_04/core/modules/dutch_game/api_endpoints.py) — create/update tournament, rematch hooks.
- [`flutter_base_05/lib/modules/dutch_game/screens/admin_tournaments_screen/admin_tournaments_screen.dart`](../../flutter_base_05/lib/modules/dutch_game/screens/admin_tournaments_screen/admin_tournaments_screen.dart) — filter chips / labels for `single_room_league` if exposed in UI.
- Dart backend / message handler — rematch flow: read **`is_tournament`** from game state, pass tournament id/context for update path; `tournament_data` payload as needed.

## Notes

- Existing sample data used `type`: `Online` / `IRL` and `format`: `League` / `Cup`. Rematch introduces `single_room_league`; document migration or coexistence for dashboards.
