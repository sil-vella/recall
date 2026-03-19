## Python Dutch coin deduction: table eligibility gate

**Date:** 2026-03-19  
**Goal:** Ensure `/userauth/dutch/deduct-game-coins` enforces the same eligibility rule as Dart join/create:
`user modules.dutch_game.level >= room game_table_level (1-4)`.

### Current state
* Dart WS already gates join/create by user level vs room table tier.
* Python endpoint `deduct_game_coins` previously only validated coin fee / balance, not the user-level eligibility.

### Changes made
* Updated `python_base_04/core/modules/dutch_game/api_endpoints.py` inside `deduct_game_coins`:
  * Derive `table_level_for_gate` from `game_table_level` (or infer from coin fee as a defensive fallback).
  * For each player, check `WinsLevelRankMatcher.user_may_join_game_table(user_level, table_level_for_gate)` before deducting.
  * Promotional tier still skips deduction, but it still cannot bypass the level gate.

### Validation checklist
* Test scenarios:
  * Player level too low, correct coins -> deduction should fail / not deduct for that player.
  * Player level high enough -> deduction proceeds as before.
  * Promotional tier player with low level -> still blocked (no deduction).
* Confirm client payload includes `game_table_level` during coin deduction (dart sends it via `gameTableLevel: roomTableLevel`).

