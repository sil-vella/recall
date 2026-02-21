# Master Plan

## Todos

- **Jack swap / special cards:** ~~Full log preserved at `Documentation/server_log_snapshot.txt` (copy of `python_base_04/tools/logger/server.log`; live file is rewritten). Items to check:~~
  1. ~~**Known_cards / visibility:**~~ **Done.** AI now uses only the acting player’s `known_cards` for “lowest opponent card” (Flutter `computer_player_factory.dart`); no use of opponents’ `known_cards`. Doc: `COMP_PLAYER_JACK_SWAP.md` §4.1, §8.
  2. ~~**Timer on jack swap failure:**~~ **Done.** On fail/skip we do not advance or cancel timer; we only proceed when timer expires (player set to `waiting`), matching queen peek. Flutter: no clear/advance on `jack_swap_error`; advance only on state `waiting`. See `SPECIAL_CARD_FAIL_SKIP_FLOW.md`.
  3. ~~**Timer on jack swap success:**~~ **Confirmed.** Timer is cancelled in `handleJackSwap` on success; no change needed.

- **MT platform:** Create the MT platform, including app with new name and domain.

- **Lobby – random join:** Add a step before the play buttons: a level-based theme (like 8 Ball Pool) where users unlock themes as they advance.

- **Tournaments dashboard**
  - Build tournaments dashboard.
  - Front-end app will NOT have an IRL tournament option. Competitors are automatically directed to the play screen when triggered from the dashboard.
  - An API event is sent from the dashboard (e.g. `/start_tour_gameid*`) that the front end listens to and uses to navigate to the play screen, passing the usual game state.
  - Add a new key to game state: `isIrlTournament` (bool).
  - The match does not start immediately. A separate API event triggers the actual start (e.g. after a 3–2–1 countdown animation).
