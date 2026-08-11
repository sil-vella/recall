# CPU Player Decision Making Update

**Status**: In Progress  
**Created**: 2026-08-07  
**Last Updated**: 2026-08-07

## Objective

Improve CPU play so it misses fewer legal chances (especially same-rank) and skips same-rank less often when it already knows matching cards. First verify how other players’ cards enter `known_cards` and whether that knowledge is used in play / same-rank decisions.

## Goals

1. **Audit known_cards** — document every path that adds (or fails to add) cards from other players, and whether play / same-rank / specials use that data.
2. **Lessen missed chances** — reduce silent skips when a CPU could legally act (same-rank, play).
3. **Lessen same-rank skips** — when own known cards match discard top, CPUs should play them more reliably (config + logic).

## Scope / Key Files

Mirrored shared logic (fix both sides when behavior changes):

| Area | Dart backend | Flutter practice mirror |
|------|--------------|-------------------------|
| Round / known_cards / same-rank | `dart_bkend_base_01/.../dutch_game_round.dart` | `flutter_base_05/.../dutch_game_round.dart` |
| YAML decisions | `.../computer_player_factory.dart` | same under Flutter module |
| Config | `dart_bkend_base_01/.../config/computer_player_config.yaml` | `flutter_base_05/assets/computer_player_config.yaml` |
| Initial peeks | `.../game_event_coordinator.dart` | mirrored |

Primary helpers: `updateKnownCards`, `_processQueenPeekUpdate`, `_processJackSwapUpdate`, `_processWrongSameRankUpdate`, `_getAvailableSameRankCardsForComputer`, `_checkComputerPlayerSameRankPlays`, `_handleComputerSameRankPlay`.

Canonical intent for opponent knowledge: `Documentation/Dutch_game/COMP_PLAYER_JACK_SWAP.md` §4.1 — `actingPlayer['known_cards'][opponentId][cardId]`.

---

## Phase 0 — Verify known_cards (investigation) ✅

### Shape

Per player: `known_cards[ownerPlayerId][cardId] = { rank, suit, points, handIndex, ... }`.

- Own knowledge: `known_cards[selfId]`
- Opponent knowledge: `known_cards[otherPlayerId]` (intended)

### Verified: entry paths for other players’ cards

Statement: *Other players’ cards enter `known_cards` mainly via queen peek, wrong same-rank reveals, and jack-swap moves — not discard takes or normal plays.*

| Path | Adds other-player cards? | Verified |
|------|--------------------------|----------|
| Queen peek | Yes — peeker only, under `targetPlayerId` (fixed) | ✅ |
| Wrong same-rank | Yes — correct | ✅ |
| Jack swap | Moves already-known cards between owner keys only (no new learn) | ✅ |
| Discard take | No for observers — only drawing CPU gets own card in `handleDrawCard` | ✅ |
| Normal play / successful same-rank | No add — `_processPlayCardUpdate` only removes played id (remember-prob) | ✅ |

### Queen peek — expected vs actual (fixed 2026-08-07)

**Expected** (docs + user): only the peeker learns the card, keyed by **opponent (target) owner id** + card id:

```text
peeker.known_cards[targetPlayerId][peekedCardId] = { rank, suit, points, handIndex: targetCardIndex, ... }
```

**Was (bug):** every player’s map got `known_cards[peekerId][peekedCardId]` (wrong owner + broadcast).

**Now (fixed):** `updateKnownCards` applies queen_peek only when `player.id == peeker`; `_processQueenPeekUpdate` writes under `targetPlayerId`. Backend + Flutter mirrors. Verify via `QueenPeekKnownCards:` logs (`LOGGING_SWITCH = true` in both `dutch_game_round.dart`).

Call site: `handleQueenPeek` → `updateKnownCards('queen_peek', peekingPlayerId, [targetCardId], swapData: { targetPlayerId, targetCardIndex })`.

### Wrong same-rank — expected vs actual ✅

**Expected**: wrong played card added to **all** players’ `known_cards` under the acting player (owner) + card id.

**Actual** (`_processWrongSameRankUpdate`):

1. `updateKnownCards` loops every player.
2. For each map: `known_cards[actingPlayerId][cardId] = fullCard + handIndex`.
3. Also removes stale `removeCandidateIds` from that owner bucket (attempted card kept/added).

Matches `COMP_PLAYER_JACK_SWAP.md`: wrong same-rank reveals go into every player’s view of the acting hand.

### How known_cards are used in decisions

| Decision | Uses own known? | Uses other players’ known? |
|----------|-----------------|----------------------------|
| Play card | Yes (prefer unknown own; else highest points among known, with opponent-rank skip) | **Yes (1B+2A)** — known own cards whose rank matches `known_cards[opponentId]` are dump candidates; rare `dump_same_rank_as_known_opponent` may still dump |
| Same-rank | Yes — **only** own `known_cards[playerId]` matching discard rank | **No** |
| Jack swap | Yes (own highest for some strategies) | **Yes** — but only strategies that read `known_cards[opponentId]` |
| Queen peek | Prefer own unknown first | Else **opponents only** (not self) |

### Queen peek decision (2026-08-07)

**Priority:** keep peeking **own hand cards that are still unknown** until the **whole hand is known**. Partial knowledge is fine (e.g. 3 known + 1 unknown → peek that unknown). Only then → opponent hands → rare skip.

**Skips reduced:** rule 1/2 `execution_probability` raised to expert/hard **1.0**, medium **0.98**, easy **0.95** (was medium 0.7 / easy 0.5 — main skip source when miss_chance already low).

**Fixes:**
- Rule 1 peeks any hand card missing from `known_cards` (not “empty known only”).
- Rule 2 target selection excludes acting player (opponents only).
- `QueenPeekDecision:` logs (`use`, `ownHand`, `targetOwner`, `reasoning`).

### Verified: jack swap vs queen peek (2026-08-07)

**Claim:** Jack swaps are not affected by queen peeks, although `known_cards` do affect jack swap decisions.

| Part | Result |
|------|--------|
| `known_cards` affect jack swap? | **Yes** — `dutch_caller_swap` and `lowest_opponent_higher_own` read the acting player’s full `known_cards` from game state, keyed by **owner** id (`ourFullKnownCards[opponentId]` / skip self). Wrong same-rank (and successful jack-swap moves of already-known cards) can populate those opponent buckets and change swap targets. |
| Queen peeks affect jack swap? | **Yes after fix** — peeker stores under `known_cards[targetId]`; `lowest_opponent_higher_own` / `dutch_caller_swap` can see peeked cards. Was broken (stored under peeker id for everyone). |

Strategies that **do not** use opponent `known_cards`: `collection_three_swap`, `one_card_player_priority`, `random_except_own` (hand / collection structure only).

Docs note: `COMP_PLAYER_JACK_SWAP.md` lists outdated 0% fallbacks; live `getJackSwapDecision` tries all five strategies with high % rolls. Peek → opponent-bucket → jack-swap link restored by queen-peek known_cards fix.

**Verdict:** Wrong same-rank correct. Queen peek fixed (peeker-only, owner = target). Discard take / normal play do not add other players’ cards. Opponent knowledge feeds jack swap (including peeks after fix).

### Same-rank / miss path (current)

1. Window opens → humans can same-rank during window.
2. On timer end → `_checkComputerPlayerSameRankPlays` → `_handleComputerSameRankPlay`.
3. Candidates from `_getAvailableSameRankCardsForComputer` (own known matching rank only).
4. Skips from:
   - Empty candidates (matching cards exist but unknown → silent skip)
   - Global `miss_chance_to_play` (easy 5% … expert 0%)
   - Event `same_rank_play.play_probability` (easy 0.9 … expert 1.0) — second skip layer
5. If play: currently plays **all** availableByIndex (high→low); `wrong_rank_probability` on by-index path appears unused.

---

## Implementation Steps

### 1. Finish audit & confirm queen-peek keying ✅

- [x] Confirmed queen peek writes under peeker id for every player (bug vs `known_cards[targetId][cardId]` for peeker only)
- [x] Confirmed wrong same-rank adds under acting owner for all players (correct)
- [x] Confirmed discard take / normal play do not add other players’ cards
- [ ] List exact config knobs for miss + same-rank (`miss_chance_to_play`, `play_probability`, remember-prob, penalty wipe)

### 2. Fix known_cards correctness (queen peek) ✅

- [x] Fix `_processQueenPeekUpdate`: write `known_cards[targetPlayerId][peekedCardId]` with target `handIndex`
- [x] Restrict update to **peeker only** (do not write into every player’s map)
- [x] Mirror fix in Flutter `dutch_game_round.dart`
- [x] `LOGGING_SWITCH = true` + `QueenPeekKnownCards:` traces for verification
- [ ] Optionally later: discard-take → observers learn `known_cards[drawerId]` (out of scope unless requested)

### 3. Lessen missed chances & same-rank skips

- [ ] Reduce or remove double-skip on same-rank (global miss + `(1 - play_probability)`) — prefer one intentional miss knob per difficulty
- [ ] Tighten YAML: lower `miss_chance_to_play` / raise `same_rank_play.play_probability` for medium+ (expert already 0 miss / 1.0 play)
- [ ] Investigate limited attempts on **unknown** own hand for same-rank (e.g. controlled wrong-rank risk) vs current “only if already known”
- [ ] Review `_maybeClearKnownCardsForCpuOnPenalty` (80% wipe at hand ≥ 7) — softens memory and increases later same-rank skips
- [ ] Confirm `handIndex` stays in sync after play removals so valid matches are not dropped as out-of-range

### 4. Use other-player knowledge in decisions ✅ (play dump skip)

- [x] Play: avoid dumping known own ranks opponents are known to hold (1B hard avoid + `dump_same_rank_as_known_opponent`; 2A known-only)
- [ ] Same-rank: still primarily own hand; opponent knowledge only for threat awareness
- [x] Keep jack-swap strategies working after queen-peek key fix

### 5. Verify

- [ ] Practice/demo: CPU same-ranks when own known matches discard top
- [x] Queen peek → known_cards under correct owner (`QueenPeekKnownCards:`)
- [ ] Miss rates match YAML (log counts of miss vs play for same-rank)
- [x] Sync backend + Flutter YAML and shared_logic copies (play dump skip)

## Current Progress

- Queen peek known_cards bug fixed (peeker-only; owner = target) on backend + Flutter.
- Play-card opponent same-rank skip (1B+2A) implemented: `dump_same_rank_as_known_opponent` YAML + factory safe/risky split; `PlayCardOpponentRank:` logs (`LOGGING_SWITCH = true` in factories).
- Wrong same-rank left unchanged (intended broadcast under acting owner).
- Queen peek skips reduced + opponent-only after own unknowns; own-unknown-first kept; `QueenPeekDecision:` logs.

## Next Steps

1. Redeploy backend; filter `global.log` for `QueenPeekDecision:` — expect `use=true` often, `ownHand=true` while unknowns remain, then `ownHand=false` for opponents.
2. Runtime verify: filter `global.log` for `PlayCardOpponentRank:` after peek + CPU play.
3. Decide miss/skip policy for same-rank window.
4. Implement same-rank miss reduction.

## Files Modified

- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`
- `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/dutch_game_round.dart`
- `dart_bkend_base_01/lib/modules/dutch_game/config/computer_player_config.yaml`
- `flutter_base_05/assets/computer_player_config.yaml`
- `dart_bkend_base_01/lib/modules/dutch_game/utils/platform/computer_player_config_parser.dart`
- `flutter_base_05/lib/modules/dutch_game/utils/platform/computer_player_config_parser.dart`
- `dart_bkend_base_01/lib/modules/dutch_game/backend_core/shared_logic/utils/computer_player_factory.dart`
- `flutter_base_05/lib/modules/dutch_game/backend_core/shared_logic/utils/computer_player_factory.dart`
- `Documentation/00_Active_plans/cpu-player-decision-making.md`

## Notes

- CPU same-rank runs **at end of window**, not mid-window like humans — timing is by design for now; change only if product wants mid-window CPU plays.
- Dead path: `_handleComputerActionWithYAML` case `'same_rank_play'` still uses empty `availableCards`; live path is `_checkComputerPlayerSameRankPlays` only.
- Remember: edit both Dart backend and Flutter practice mirrors for behavior + YAML.
- Play dump skip: unknowns never filtered; known matching opponent ranks skipped unless `allowDump` (easy 0.12 … expert 0.0). When `!allowDump`, known-risky also stripped from `playable_cards` so P3 random fallback cannot dump. Optimal-play roll uses difficulty (not strategy name).
- `PlayCardOpponentRank` logs include `knownRiskyDetail`, `rule=`, `selectedWasRisky=` for live verification.
- `miss_chance_to_play` lowered: easy 0.02, medium 0.01, hard/expert 0.0 (draw/play/peek/swap/collect).
- Queen peek: own unknown first; then opponents only; execution_probability easy 0.95 / medium 0.98 / hard+expert 1.0.)
