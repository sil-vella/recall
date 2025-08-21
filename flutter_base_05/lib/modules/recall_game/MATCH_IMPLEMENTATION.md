## Recall Match Screen – Flutter Implementation Plan

This document details the architecture and delivery plan for the Recall match screen and related UI/logic, aligned with the Python backend `recall_*` WebSocket events and the existing Flutter Base 05 patterns.

### Goals
- Build the match (gameplay) screen UI and client-side logic on top of existing managers (`RecallGameManager`, `RecallStateManager`, `StateManager`, `WebSocketManager`).
- Align with backend event names and payloads (`recall_*`) for clean, testable integration.
- Keep the UI modular, theme-compliant, and automation-friendly (Semantics identifiers).

---

## 1) Screen Architecture

Routes and Screen Components:
- Route: `/recall/game-play` (registered in `RecallGameCore._registerScreens()` once ready).
- Base class: extend `BaseScreen` → `RecallMatchScreen` and `_RecallMatchScreenState`.
- Feature slots: leverage `FeatureRegistryManager` for pluggable tools (e.g., help, debug overlay) without modifying core.

Layout Regions (widgets):
- Header/status bar: connection + turn/phase/timer display.
- Opponents row/grid: condensed player panels (name, card count, last action), horizontally scrollable on small screens.
- Center board: discard (face-up) pile, draw (face-down) pile, optional center pile for transient animations.
- My hand: selectable cards with play/replace affordances.
- Action bar: context-driven (Draw, Take from Discard, Play, Replace, Call Recall, Use Power).
- Messages panel: integrate existing `MessageBoardWidget` for session/room messages.

Responsiveness:
- Use `LayoutBuilder` to switch between column/row arrangements for mobile/tablet/desktop.
- Use sized constraints to keep card tap targets touch-friendly.

Theme and Accessibility:
- Use `AppColors`, `AppTextStyles`, `AppPadding` consistently.
- Wrap interactive elements in `Semantics` with stable `identifier` values (e.g., `match_action_draw`, `hand_card_<index>`).

---

## 2) State and Event Wiring

Managers:
- `RecallGameManager`: orchestrates high-level flows; already listens to WS and updates `RecallStateManager`.
- `RecallStateManager`: holds current `GameState`; exposes streams for turn/hand/phase.
- `StateManager`: global store to render `MessageBoardWidget` and lobby info.

Event Registration (receive):
- Subscribe via `WebSocketManager`/`WSEventManager` to `recall_*` events:
  - `recall_game_state_updated` → update full `GameState` in `RecallStateManager`.
  - `recall_turn_changed` (or part of `game_state_updated`) → update current player.
  - `recall_card_played`, `recall_card_drawn` → per-action UI updates/animations.
  - `recall_special_power_used` → trigger power dialogs result handling.
  - `recall_recall_called` → enter recall phase, show banners/timers.
  - `recall_game_ended` → show results dialog/panel.
  - `recall_error` → toast/snackbar + session message board entry.

Event Emission (send):
- `recall_join_game`, `recall_leave_game` managed by lobby → reused if needed.
- `recall_player_action` payloads:
  - `{action: 'draw_from_deck'}`
  - `{action: 'take_from_discard'}`
  - `{action: 'play_card', card: {...}, replaceIndex?: int}`
  - `{action: 'place_drawn_card_replace', replaceIndex: int}`
  - `{action: 'place_drawn_card_play'}`
  - `{action: 'play_out_of_turn', card: {...}}`
  - `{action: 'call_recall'}`
  - `{action: 'use_special_power', card: {...}, power_data: {...}}`

Event–UI Mapping:
- Use a lightweight in-screen event router that translates WS events to animated UI intents (e.g., show draw animation when `card_drawn` arrives).

---

## 3) UI Components (Detailed)

Header/Status Bar:
- Shows: connection state, current phase, current player name/avatar, turn timer (if any), out-of-turn window countdown.
- Semantics: `match_status_phase`, `match_status_turn_timer`.

Opponents Panel:
- Show each opponent’s name, card count, last action icon, recall-called badge.
- Semantics per player: `opponent_<playerId>`.

Center Board:
- Discard pile (top card visible). Semantics: `pile_discard_top`.
- Draw pile (count visible). Semantics: `pile_draw`.
- Tap on discard when rule allows “take from discard.”

My Hand:
- Cards as tappable/selectable chips or images with selection overlay.
- Multi-step interactions:
  - Select a card → enabled “Play”/“Replace” actions as per phase.
  - After drawing, offer “Play Drawn” or “Replace With Drawn” with index selection.
- Semantics: `hand_card_<index>`, `hand_action_play`, `hand_action_replace`.

Action Bar (contextual):
- Buttons enabled by rule state and `RecallStateManager`:
  - Draw (face-down), Take from Discard
  - Play, Replace, Place Drawn & Play, Place Drawn & Replace
  - Call Recall, Use Power (with dialog)
- Semantics: `match_action_draw`, `match_action_take_discard`, `match_action_play`, `match_action_replace`, `match_action_call_recall`, `match_action_use_power`.

Special Powers UX:
- Queen (peek): dialog to pick target player and card position or by index abstraction; result emits `use_special_power` with `power_data`.
- Jack (swap): two-step picker (playerA+indexA, playerB+indexB) with clear instructions; emits `use_special_power`.
- Validate server-side results update via `game_state_updated`.

Messages Panel:
- Reuse `MessageBoardWidget` (session + room-specific). Place below the center board or as a collapsible side panel on desktop.

Animations:
- Card draw from draw pile to hand.
- Card play from hand to discard.
- Swap animation for Jack.
- Peek emphasis glow for Queen.
- Use implicit animations and inexpensive transforms; avoid heavy rebuilds.

---

## 4) State Derivations and Guards

From `RecallStateManager` derive:
- `isMyTurn`, `canCallRecall`, `phase`, `turnNumber`, `roundNumber`, `currentPlayerId`.
- Current hand, playable cards (backend determines playable cards, frontend only displays).
- Disable UI actions when not permitted; attempt anyway → server returns `recall_error` to show message.

Client Hints vs Server Truth:
- The server is source of truth. Client hints (e.g., which cards are playable) are advisory; final validation happens server-side.

---

## 5) Timers and Out-of-Turn Window

- Turn timer (if provided in room settings) shown in header; countdown with `Ticker`/`Timer.periodic`.
- Out-of-turn window: show banner/timer when server emits `check_out_of_turn_play` (or include in `card_played` with `timeout`).
- First-claim principle: lock action buttons once a claim is attempted; rely on server acknowledgement.

---

## 6) Error Handling and Messaging

- On `recall_error`: show snackbar + add session message via `RecallMessageManager`.
- On transport errors: show offline banner; disable actions.
- On unexpected payloads: log via `Logger` with sanitized metadata.

---

## 7) Accessibility and Automation

- Semantics for all actionable widgets with stable `identifier` attributes (see examples above).
- Provide keyboard activation for actions; Enter/Space support.
- Ensure CanvasKit interaction works with robust tap scripts used previously.

---

## 8) Performance

- Minimize rebuilds using `AnimatedBuilder` with `StateManager` and targeted `Consumer` scopes.
- Use `ValueListenableBuilder` or dedicated streams for timers.
- Defer heavy animations on low-power devices (optional flag).

---

## 9) Testing Strategy

- Widget tests: action bar enable/disable logic, selection flows, special power dialogs.
- Golden tests: card layout in portrait/landscape.
- Integration (manual + CDP console): semantics-driven end-to-end script (open drawer, navigate, join, draw, play, recall).

---

## 10) Delivery Plan (Milestones)

Phase A – Skeleton and Events
- Add `/recall/game-play` screen with header/center/hand skeleton.
- Wire event listeners (`recall_*`) and update `RecallStateManager` mappings.

Phase B – Core Actions
- Implement Draw, Take from Discard, Play, Replace, Place Drawn variants.
- Add contextual action bar state logic; basic animations.

Phase C – Out-of-Turn and Powers
- Implement out-of-turn prompt/timer and claim action.
- Implement Queen peek and Jack swap dialogs and event emission.

Phase D – Recall and Results
- Implement Call Recall flow; final round state; results panel.

Phase E – Polish
- Add accessibility Semantics across all controls.
- Add message panel integration and richer animations.
- Add tests (widget + golden) and docs.

---

## 11) Backend Alignment Checklist

- Confirm payload contracts for:
  - `recall_game_state_updated`, `recall_card_played`, `recall_card_drawn`, `recall_turn_changed`, `recall_recall_called`, `recall_special_power_used`, `recall_game_ended`, `recall_error`.
- Confirm action payloads accepted under `recall_player_action` for all listed actions.
- Confirm timeouts metadata for out-of-turn window and turn timers.
- Confirm error codes/messages for UX mapping.

---

## 12) Observability

- Use `Logger` for key user actions and server responses.
- Optional metrics hooks (event round trip times) behind a debug flag.

