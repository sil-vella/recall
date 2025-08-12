## End-to-end Recall Gameplay Completion Plan

### Overview
- Goal: Make gameplay fully functional from lobby → join → play turns/out-of-turn → powers → recall → results, across backend and Flutter.

### Backend (Python)
- Join flow
  - Ensure handler returns full `recall_event game_joined` payload immediately after join with current state.
  - Add validation that player is in room before actions; unify error messages.
- Out-of-turn window
  - Confirm `game_state` includes any out-of-turn metadata (deadline). If not, add `outOfTurnEndsAt` in recall_event when a card is played.
  - Optionally publish a `check_out_of_turn_play` event with timeout metadata.
- Special powers
  - Validate incoming `use_special_power` data; enforce rules (e.g., queen peek limits, jack swap constraints).
  - Add error responses per invalid cases.
- Scoring and results
  - Ensure `end_game` emits `recall_event game_ended` with winner and final state.
- Persistence (optional)
  - Add per-game logs/history (Redis list) to help frontend rehydrate if needed.

### Frontend (Flutter)
- Navigation and joining
  - On “Enter Game” in lobby, call `RecallGameManager.joinGame(currentRoomId, playerName)` then navigate to `/recall/game-play`.
  - Handle `game_joined` → hydrate `RecallStateManager` with full `game_state`.
- State and events
  - Ensure `RecallGameManager` handles all recall_event types: `game_joined`, `game_state_updated`, `card_played`, `turn_changed`, `recall_called`, `special_power_used`, `game_ended`, `player_joined`, `player_left`, `error`.
- Action bar enablement
  - Enable/disable actions based on `isMyTurn`, `phase`, and pending-draw state.
  - Show replace vs play-drawn options when a pending draw exists (backend returns pending).
- Out-of-turn UX
  - When `card_played` arrives and out-of-turn is allowed, show a banner with countdown (deadline from backend).
  - Provide “Play Out-of-Turn” button; selecting a matching rank card triggers `recall_player_action { action: 'play_out_of_turn', card: {...}}`.
- Special powers UX
  - Queen peek dialog: pick target player/index; call `use_special_power { power: 'peek_at_card', target_player_id, target_card_index }`. Show private result only to requesting player.
  - Jack swap dialog: pick source player/index and destination player/index; call `use_special_power { power: 'switch_cards', ... }`.
- Timers
  - Turn timer (if present in `game_settings`): show countdown on StatusBar; disable inputs on timeout until server advances.
  - Out-of-turn countdown as noted above.
- Animations and polish
  - Draw: animate from draw pile to hand. Play: hand to discard. Swap: crossfade between players.
  - Keep animations optional/lightweight.
- Error handling
  - On `recall_error`: toast + add to session message board. Rollback UI selection after errors.

### Message routing and consistency
- Backend: emit unified `recall_event` envelope with `event_type` and `game_state` after each action.
- Frontend: centralize mapping in `RecallGameManager._handleRecallGameEvent` to update `RecallStateManager` and trigger UI changes.

### Testing
- Backend unit tests: actions, powers, recall, out-of-turn paths.
- Flutter widget tests: action bar state, dialogs, timers; golden tests for layouts.
- Integration: scripted flow joining a game, drawing, playing, out-of-turn claim, calling recall, verifying end.

### Milestones
- M1: Join flow + navigation + initial hydrate
- M2: Core actions with pending-draw flows, state updates, and card/turn changes
- M3: Out-of-turn UX + timer plumbing
- M4: Special powers dialogs + backend validations
- M5: Recall/end-game + results display
- M6: Animations + error polish + tests


