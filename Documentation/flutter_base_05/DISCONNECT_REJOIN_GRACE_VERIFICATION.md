# Disconnect / reconnect grace — verification checklist

Ran: `dart analyze` on `dart_bkend_base_01/lib/server` + `backend_core`; `dart analyze` on touched Flutter Dutch/WS paths (warnings only, no analyzer errors).

## Manual scenario matrix

1. **In-match disconnect, reconnect within grace**  
   Single human + CPUs, match started → kill network/tab → reconnect same account within ~20s → expect `authenticated` (`resumable_room_id` or stored prefs), automatic `resume_room`, `rejoin_success`, snapshot; CPUs continue; timers resume for returning seat.

2. **Reconnect after grace**  
   Same as (1) but wait > grace → `resume_room_error` → `failFastOnMatchRecoveryFailure` (lobby, state cleared, snackbar); stored `dutch_last_multiplayer_room_id` cleared via fail-fast / leave.

3. **App background during match**  
   Multiplayer `room_*` on game-play → home/call (app `paused`) → return within ~20s → `attemptMatchRecoveryOnForeground` on `resumed` → `resume_room` → `rejoin_success` + `game_state_updated`.  
   Background longer than grace → `resume_room_error` → fail-fast to lobby.  
   WS reconnect failure on resume → same fail-fast path.

4. **Explicit `leave_room`**  
   Immediate leave (no grace), player removed from roster; grace hint cleared locally on `leave_room_success`.

5. **Random join / second human**  
   Two humans A+B: A disconnect → grace scheduled; B still receives gameplay; A resumes successfully; duplicate seat Prevention: same `hum_<userId>` roster check.

6. **Server logs / events** (optional with `ENABLE_DISCONNECT_REJOIN_GRACE`/logging)  
   `player_disconnected`, `resume_room`, `rejoin_success`, `grace_expired_leave` (+ hook `leave_room` with `reason: grace_expired_leave`).

## Config (Dart)

- `enable_disconnect_rejoin_grace` / `ENABLE_DISCONNECT_REJOIN_GRACE` (default true)
- `disconnect_rejoin_grace_seconds` / `DISCONNECT_REJOIN_GRACE_SECONDS` (default 20)
