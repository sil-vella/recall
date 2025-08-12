## Recall Gameplay Integration Plan

This document outlines a concrete, staged plan to integrate the legacy gameplay logic from `old_game_logic/` into the new modular architecture in `python_base_04/core/recall_game/`. The goal is to faithfully port game mechanics (rounds, player actions, out-of-turn play, and special powers) while leveraging the new models, declarative rules engine, and WebSocket layer.

### Objectives
- Preserve gameplay rules and player experience from the legacy implementation.
- Use the new domain models (`Card`, `CardDeck`, `Player`, `GameState`) and avoid reintroducing legacy types.
- Express turn rules, special powers, and out-of-turn flows via the declarative `GameLogicEngine` rules (YAML) wherever feasible.
- Implement computer player strategy using `ComputerPlayerLogic` (YAML-driven with Python helpers), not the legacy imperative `ComputerManager`.
- Integrate messaging via `RecallMessageSystem`; integrate transport via existing WebSocket managers in Python Base 04.

### Constraints and Principles
- Do not modify Python Base 04 core managers or base classes. Integrate by extension and modules only.
- Keep logic stateless where possible; keep short-lived timers and buffers out of blocking code paths.
- Prefer YAML rules for action flows and notifications; fall back to small Python effect helpers when rules need compute.

---

## 1) Domain Mapping (Legacy → New)

- Legacy `GameRoomState` → New `GameState`
  - Hands, face up/down piles, turn pointer, winner determination → `GameState` already has equivalents: draw, replace/play, initial peek, call recall, out-of-turn play, end-game.
  - “Known/Unknown” card visibility → `Player` supports `look_at_card`, `get_visible_cards`, `get_hidden_cards` to represent per-player knowledge while holding actual `Card` objects.

- Legacy `Player`/`PlayerManager` → New `Player`, `PlayerType`
  - Keep state transitions via `GameState` methods rather than per-player imperative flows.

- Legacy `RoundManager` (turn loop, buffers, same-rank window, special rank windows) → New `GameLogicEngine` + `GameState` transitions
  - Replace blocking `time.sleep()` buffers with non-blocking timers (threading.Timer) and phase state machine (`GamePhase` in `GameState`).
  - “Same Rank Window” → New phase `OUT_OF_TURN_PLAY` with a timed window broadcast (`check_out_of_turn_play`).
  - “Special Rank Window” (Jack/Queen) → Effects and notifications in YAML rules + helper functions for swap/peek.

- Legacy `ComputerManager` → New `ComputerPlayerLogic`
  - Translate heuristics (e.g., avoid 0/1/5/6, avoid Jack except when needed, prefer highest-value play) into AI decision YAML + helper evaluation functions.

- Legacy `EventManager` emits → New `RecallMessageSystem` + `RecallWebSocketsManager` / `RecallGameMain`
  - All UX-facing notices route through `RecallMessageSystem.info_room/success_room/...`.
  - Transport/broadcast handled by existing WS managers.

---

## 2) Game Flow Specification (New System)

We will drive game flow primarily with `GameState` and YAML rules.

1. Setup and Dealing
   - Use `GameState.start_game()` → deals to players and sets `PLAYER_TURN` phase.
   - Initial peek: `GameState.initial_peek(player_id, indices)`; ensure two-card limit enforced via rules/validation.

2. Player Turn (Active Player)
   - Actions (expressed in YAML):
     - draw_from_deck → replaces legacy draw from face-down.
     - take_from_discard → replaces legacy draw from face-up top.
     - place_drawn_card_replace (replace a hand card with drawn)
     - place_drawn_card_play (play the drawn card to discard)
     - play_card (play a card from hand directly if supported by rules)
   - Effects:
     - Move cards between piles (effects: move_card_to_discard, replace_card_in_hand)
     - Update `GameState` phase appropriately
     - Generate notifications: `card_played`, `draw_from_fd_deck`, `draw_from_fu_deck`

3. Out-of-Turn Window (Same Rank Match)
   - After a card is played, generate notification `check_out_of_turn_play` with timeout (e.g., 5–10 seconds) via YAML rules (already scaffolded in examples).
   - Transition to `OUT_OF_TURN_PLAY` during window; accept first valid out-of-turn claim that matches rank.
   - If claimed:
     - Execute out-of-turn effect path (`play_out_of_turn` rule): move matching card to discard, handle special powers queue, notify room.
     - Return to appropriate phase; continue turn logic if required by rule.
   - If timeout with no claim: return to `PLAYER_TURN` flow and call `next_player` effect.

4. Special Powers
   - Queen (peek): effect `peek_at_card` → private message to target player in YAML; for AI, private knowledge update only.
   - Jack (switch): effect `switch_cards` → swap specified indices between players; update both hands; notify room.
   - Additional power cards: expressed in YAML `special_powers/` and implemented as effects.

5. Recall Call and Final Round
   - Action `call_recall` moves to `RECALL_CALLED` phase, sets queue semantics.
   - Continue turns per rules until all participants finish; then `end_game` with scoring and tiebreakers per rules.

6. End Game and Scoring
   - Use `GameState.end_game()` to compute points and select winner; broadcast via `RecallMessageSystem` and standard room events.

---

## 3) Declarative Rules (YAML) Deliverables

Extend and finalize the YAML declarations to fully capture gameplay.

- Actions (`game_rules/actions/`)
  - `play_card.yaml`: ensure triggers and effects handle both in-turn and post-draw plays; add notification hooks.
  - `draw_from_fd_deck.yaml`: includes expect-reply (if needed) and transitions.
  - `draw_from_fu_deck.yaml`: analogous to face-up draw.
  - `replace_card_in_hand.yaml`: swapping drawn card with selected index.
  - `place_drawn_card_play.yaml`: playing drawn card immediately.
  - `play_out_of_turn.yaml`: validate same-rank condition; on success, apply discard/move effects and potential special-power queue.
  - `call_recall.yaml`: declare phase transition, queue setup, and notifications.

- Cards (`game_rules/cards/`)
  - `queen.yaml`: define `peek_at_card` power, validation, private notifications.
  - `jack.yaml`: define `switch_cards` power, validation, broadcast notifications.
  - Added power cards as needed (e.g., `steal_card.yaml`).

- Special Powers (`game_rules/special_powers/`)
  - `steal_card.yaml` provided; extend for additional powers matching Recall rules.

- Notifications (embedded within rules)
  - Broadcast UX cues: `card_played`, `draw_from_fd_deck`, `draw_from_fu_deck`, `check_out_of_turn_play`, `special_power_used`, `recall_called`, `game_ended`.
  - Use `RecallMessageSystem` on the handler side to fan-out structured messages.

---

## 4) Effects and Helpers (Python side)

Implement small, focused helper functions called by YAML-driven effects inside `GameLogicEngine` when rules require computation beyond simple state moves:

- `effect_check_out_of_turn_window(game_state, action_data)`
  - Set `GamePhase.OUT_OF_TURN_PLAY`, schedule a timer (threading.Timer) for the window duration.
  - On first valid claim (via `play_out_of_turn` action), cancel timer, apply effects, return to flow.
  - On timeout, call `effect_next_player`.

- `effect_switch_cards(game_state, action_data)`
  - Swap two indices between players; update hands and knowledge as needed.

- `effect_peek_at_card(game_state, action_data)`
  - Resolve target card; produce a private notification only to the peeking player; update local “visible” info.

Keep these helpers within `game_logic_engine.py` effect methods to avoid spreading logic across modules. They operate on `GameState` and return structured effect results for logging/testing.

---

## 5) Computer Player Strategy (AI)

Translate legacy heuristics into `ComputerPlayerLogic` and YAML AI decision rules:

- Decision Types and Triggers
  - `play_card` when it is AI’s turn (`is_my_turn`).
  - Consider out-of-turn claims only when `OUT_OF_TURN_PLAY` and AI has matching rank.

- Heuristics (from legacy `ComputerManager`)
  - Prefer not to play `Jack` unless beneficial (e.g., queueing special action is useful).
  - Avoid playing low-utility values (0, 1, 5, 6) unless necessary.
  - Prefer highest-value safe plays when no match/special opportunistic play.
  - When out-of-turn claim is available, play a same-rank if it advances position.
  - During final round: adjust strategy to minimize points retained; opportunistically force swaps/peeks.

- Implementation
  - Extend `game_rules/ai_logic/medium/play_card_decision.yaml` to list evaluation weights (points, special power utility, game progression, risk).
  - Add `ComputerPlayerLogic` helpers:
    - `evaluate_card_value(card, game_state)` factoring Recall scoring and phase.
    - `select_best_card(game_state, player_state)` to choose between candidates.
  - Add an `_action_play_out_of_turn` decision path that triggers the appropriate action if legal.

---

## 6) Timers, Buffers, and Non-Blocking Flow

Replace legacy `time.sleep()` buffers with non-blocking timers and explicit phases:

- Use `GameState` phases (`PLAYER_TURN`, `OUT_OF_TURN_PLAY`, `RECALL_CALLED`) to gate UI and rule evaluation.
- Implement short windows (e.g., 5–10s) via `threading.Timer` registered by the WebSocket/event layer or effect helpers.
- On timer callbacks, drive the state forward (e.g., next player) if no action occurred.

This approach avoids server thread blocking and integrates with concurrent games/rooms.

---

## 7) WebSocket and Messaging Integration

- All gameplay notifications go through `RecallMessageSystem` for consistent, structured messages (room or session scoped).
- `RecallWebSocketsManager` subscribes and routes core WS events to Recall-specific events (`recall_event`, `recall_message`).
- For time-window prompts (out-of-turn, call recall confirmations), broadcast appropriate events with `timeout` metadata so clients can render timers.

---

## 8) Step-by-Step Delivery Plan

Phase 1: Foundations and Rules
- Validate `GameState` covers needed operations; add small effect helpers if missing.
- Finalize core action rules: `play_card`, `draw_from_fd_deck`, `draw_from_fu_deck`, `replace_card_in_hand`, `place_drawn_card_play`.
- Implement unit tests for each action/effect on a minimal `GameState`.

Phase 2: Special Powers and Out-of-Turn
- Implement `peek_at_card` and `switch_cards` helpers and YAML rules.
- Implement out-of-turn window: rule + helper timer; add tests for claims/timeout.

Phase 3: AI Decisions
- Extend AI YAML and `ComputerPlayerLogic` helpers; add tests for decision selection under various phases.

Phase 4: Recall and End Game
- Implement `call_recall` + final-round sequencing via rules/effects.
- Implement scoring and winner selection tests.

Phase 5: WebSocket Wiring and Messaging
- Connect rule notifications to `RecallMessageSystem` broadcasts in handlers.
- Add integration tests for typical multiplayer sequences (join, play, out-of-turn, powers, recall).

---

## 9) Testing Strategy

- Unit tests for `GameState` operations and effect helpers.
- Rule validation tests: run `GameLogicEngine.process_player_action` against fixtures.
- AI tests: verify decision outcomes with controlled hands and phases.
- Integration tests: simulate WebSocket events end-to-end (without UI) using the app’s WS manager.

---

## 10) Risk Mitigation and Compatibility

- Keep `old_game_logic/` as reference only; do not import from it.
- Validate each legacy scenario has an equivalent rule/effect path; track coverage with a checklist.
- Avoid long blocking operations; use timers and phases to keep the server responsive.
- Gate new flows behind feature flags if needed for incremental rollout.

---

## 11) Acceptance Criteria

- Core flows implemented via YAML + helpers: draw, play, replace, out-of-turn, queen peek, jack swap, recall, end-game.
- AI can play full games at “medium” difficulty with sensible decisions.
- Messaging reflects all major events to room and session (where applicable).
- Unit/integration tests pass; end-to-end simulated game completes deterministically under test harness.


