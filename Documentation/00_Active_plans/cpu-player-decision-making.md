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
| Queen peek | Intended yes; **implementation wrong** (see below) | ✅ audited |
| Wrong same-rank | Yes — correct | ✅ |
| Jack swap | Moves already-known cards between owner keys only (no new learn) | ✅ |
| Discard take | No for observers — only drawing CPU gets own card in `handleDrawCard` | ✅ |
| Normal play / successful same-rank | No add — `_processPlayCardUpdate` only removes played id (remember-prob) | ✅ |

### Queen peek — expected vs actual ❌

**Expected** (docs + user): only the peeker learns the card, keyed by **opponent (target) owner id** + card id:

```text
peeker.known_cards[targetPlayerId][peekedCardId] = { rank, suit, points, handIndex: targetCardIndex, ... }
```

**Actual** (`_processQueenPeekUpdate`, backend + Flutter mirror):

1. `updateKnownCards` loops **every** player and mutates each `player['known_cards']`.
2. Inside the helper, the card is written under **`actingPlayerId` (peeker)**, not `targetPlayerId`.
3. Card id key is correct (`peekedCardId`); `handIndex` is the target’s index (right index, wrong owner bucket).

Resulting shape for **every** player:

```text
player.known_cards[peekerId][peekedCardId] = { ..., handIndex: targetCardIndex }
```

Impacts:

- Peeker’s view of the opponent is **missing** (`known_cards[targetId]` never gets the peek) → jack-swap “lowest opponent” strategies cannot see peeked cards.
- Peeked card is stored as if it belonged to the **peeker** → can pollute own same-rank candidates / handIndex checks.
- Non-peekers incorrectly “learn” a card under the peeker’s owner key (info leak / wrong model).

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
| Play card | Yes (prefer unknown own; else highest points) | **No** |
| Same-rank | Yes — **only** own `known_cards[playerId]` matching discard rank | **No** |
| Jack swap | Yes (own highest for some strategies) | **Yes** — but only strategies that read `known_cards[opponentId]` |
| Queen peek | Prefer own unknown | Else random other hand |

### Verified: jack swap vs queen peek (2026-08-07)

**Claim:** Jack swaps are not affected by queen peeks, although `known_cards` do affect jack swap decisions.

| Part | Result |
|------|--------|
| `known_cards` affect jack swap? | **Yes** — `dutch_caller_swap` and `lowest_opponent_higher_own` read the acting player’s full `known_cards` from game state, keyed by **owner** id (`ourFullKnownCards[opponentId]` / skip self). Wrong same-rank (and successful jack-swap moves of already-known cards) can populate those opponent buckets and change swap targets. |
| Queen peeks affect jack swap? | **No in practice** — `_processQueenPeekUpdate` writes under **peeker** id, not `targetPlayerId`. Strategies that look for `known_cards[opponentId]` never see peeked cards. A peek can only pollute the peeker’s **own** bucket (and is skipped when scanning opponents). |

Strategies that **do not** use opponent `known_cards`: `collection_three_swap`, `one_card_player_priority`, `random_except_own` (hand / collection structure only).

Docs note: `COMP_PLAYER_JACK_SWAP.md` still says peeks feed `lowest_opponent_higher_own` and lists outdated 0% fallbacks; live `getJackSwapDecision` tries all five strategies with high % rolls. Intent in docs matches expected peek write; **code write path breaks that link**.

**Verdict:** Wrong same-rank is correct. Queen peek owner key + broadcast-to-all is a **bug**. Discard take / normal play do not add other players’ cards. Opponent knowledge (when keyed correctly) feeds jack swap; peeks currently do not.

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

### 2. Fix known_cards correctness (queen peek)

- [ ] Fix `_processQueenPeekUpdate`: write `known_cards[targetPlayerId][peekedCardId]` with target `handIndex`
- [ ] Restrict update to **peeker only** (do not write into every player’s map)
- [ ] Ensure peek `handIndex` stays valid after later hand mutations
- [ ] Mirror fix in Flutter `dutch_game_round.dart`
- [ ] Optionally later: discard-take → observers learn `known_cards[drawerId]` (out of scope unless requested)

### 3. Lessen missed chances & same-rank skips

- [ ] Reduce or remove double-skip on same-rank (global miss + `(1 - play_probability)`) — prefer one intentional miss knob per difficulty
- [ ] Tighten YAML: lower `miss_chance_to_play` / raise `same_rank_play.play_probability` for medium+ (expert already 0 miss / 1.0 play)
- [ ] Investigate limited attempts on **unknown** own hand for same-rank (e.g. controlled wrong-rank risk) vs current “only if already known”
- [ ] Review `_maybeClearKnownCardsForCpuOnPenalty` (80% wipe at hand ≥ 7) — softens memory and increases later same-rank skips
- [ ] Confirm `handIndex` stays in sync after play removals so valid matches are not dropped as out-of-range

### 4. Use other-player knowledge in decisions (optional stretch)

- [ ] Play: avoid dumping ranks opponents are known to hold if same-rank risk matters
- [ ] Same-rank: still primarily own hand; opponent knowledge only for threat awareness
- [ ] Keep jack-swap strategies working after queen-peek key fix

### 5. Verify

- [ ] Practice/demo: CPU same-ranks when own known matches discard top
- [ ] Queen peek → jack swap uses peeked card under correct owner
- [ ] Miss rates match YAML (log counts of miss vs play for same-rank)
- [ ] Sync backend + Flutter YAML and shared_logic copies

## Current Progress

- Active plan created.
- Queen peek / wrong same-rank / discard / play entry paths verified in code (backend + Flutter mirror match).
- Queen peek bug confirmed; wrong same-rank correct. No code fix yet.

## Next Steps

1. Fix `_processQueenPeekUpdate` (owner = target; peeker-only write); mirror Flutter.
2. Decide miss/skip policy (config-only vs logic change for unknown matches).
3. Implement same-rank miss reduction.

## Files Modified

_(none yet)_

## Notes

- CPU same-rank runs **at end of window**, not mid-window like humans — timing is by design for now; change only if product wants mid-window CPU plays.
- Dead path: `_handleComputerActionWithYAML` case `'same_rank_play'` still uses empty `availableCards`; live path is `_checkComputerPlayerSameRankPlays` only.
- Remember: edit both Dart backend and Flutter practice mirrors for behavior + YAML.
)
