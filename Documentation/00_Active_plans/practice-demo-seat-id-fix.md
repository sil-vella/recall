# Practice/Demo Local Player Seat ID Fix

## Status: Implemented

## Problem

Practice and demo matches placed the human player in the opponents strip instead of myHand because client seat id (`practice_session_<userId>`) did not match roster `players[].id` (`hum_<userId>` from `canonicalMultiplayerHumanPlayerId`).

## Solution

1. **Backend seat id** — `canonicalMultiplayerHumanPlayerId` preserves `practice_session_*` session ids.
2. **Client matcher** — `DutchEventHandlerCallbacks.matchesLocalPlayerSeat` / `findLocalPlayerInRoster` used for opponents panel, widget sync, and board layout.
3. **Logging** — `LocalPlayerSeat:` traces when `DUTCH_DEV_LOG=1` (practice/demo flows).

## Files changed

- `flutter_base_05/lib/modules/dutch_game/backend_core/utils/player_seat_id.dart`
- `dart_bkend_base_01/lib/server/room_manager.dart`
- `flutter_base_05/lib/modules/dutch_game/managers/dutch_event_handler_callbacks.dart`
- `flutter_base_05/lib/modules/dutch_game/managers/dutch_game_state_updater.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/game_play/widgets/unified_game_board_widget.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/demo/demo_action_handler.dart`
- `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/lobby_screen.dart`

## Verification

Launch with `playbooks/frontend/run_*_to_global_log.sh`, filter `global.log` for `[dev] LocalPlayerSeat:`.

- Practice/demo: `selfIndex >= 0`, `oppCount` excludes human, `myHandSlice cardsLen=4` after deal.
- Multiplayer: `getCurrentUserId source=hum_ws`, unchanged opponent filtering.
