# Rematch + Tournament + Notifications + Admin — Follow-up Plan

**Status**: Not started (capture for next implementations)  
**Created**: 2026-03-22  
**Last Updated**: 2026-03-22

## Objective

Extend the **working rematch flow** with tournament persistence, consistent **invite delivery** (DB + instant WebSocket), **game-ended UI** for tournament leaderboard context, and a **server-filtered** admin tournaments API (excluding online / single-room match format for the first iteration).

## Context (working today)

- Rematch reset, coin checks, play-screen local flag reset on `initial_peek`, and related fixes are **behaving well** — preserve those behaviors when adding features below.

## Implementation todos

- [ ] **Tournament create on rematch** — Wire in tournament create / registration logic when a rematch is started for a tournament-backed room (align with `_createSingleRoomTournamentStub` / Python API direction in `message_handler.dart`; persist or register `single_room_league` or equivalent as product requires).
- [ ] **Rematch invite: DB + instant WS** — When rematch invites are persisted as **DB notifications**, ensure the same invite is also delivered as an **instant WebSocket** notification (same semantics as current `restart_invite` / `instant_ws` path), not DB-only.
- [ ] **Game ended modal — tournament leaderboard** — On the game-ended modal, read `dutch_game` / game state; when **`is_tournament`** (or equivalent) is true, also show **leaderboard** data (source TBD: API slice already on room or new fetch).
- [ ] **Admin: get tournaments — new endpoint** — Replace or supplement “dash admin get tournaments” with a **new endpoint** that performs **server-side filtering**. **Initial filter**: exclude **online** tournament type when **match format** is **single room** (exact field names to match DB/schema — confirm with `admin_tournaments_screen` and Python routes).

## Current progress

- N/A — planning only.

## Next steps (when picking up)

1. Confirm tournament model fields: `online` vs other types, `single_room` / match format enums.
2. Trace rematch invite path: DB notification writer vs `restart_invite` WS (`ws_event_handler`, `message_handler`).
3. Design leaderboard payload for game-ended modal (minimal vs full table).
4. Spec query params / body for new admin tournaments list endpoint and Flutter client changes.

## Files likely involved (reference)

- `dart_bkend_base_01/lib/server/message_handler.dart` — rematch, tournament stub, broadcasts  
- `flutter_base_05/lib/core/managers/websockets/ws_event_handler.dart` — instant WS notifications  
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/messages_widget.dart` — game ended modal  
- `flutter_base_05/lib/modules/dutch_game/screens/admin_tournaments_screen/admin_tournaments_screen.dart` — admin tournaments UI  
- `python_base_04/core/modules/dutch_game/` (or tournaments module) — new list endpoint + filtering  

## Notes

- **Server-side filtering** keeps the admin UI simple and avoids loading rows that are never shown after the first filter iteration.
- Rematch **same `room_` id** implies UI/state must keep using tournament flags from `Room` / `game_state` after reset — align with existing rematch state merge work.
