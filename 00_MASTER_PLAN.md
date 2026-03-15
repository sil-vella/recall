# Master Plan

## Todos



- **Level based theme:** Add a step before the play buttons: a level-based theme (like 8 Ball Pool) where users unlock themes as they advance.




- **Dutch game:** Comp players to be able to call final round.

  - enable 2 and 3 player only match (for tournament winner deciders)

- **Create games – play again / league style:** At the end modal for create games, add a **Play again** option so the same group can keep playing in a league style (repeat matches, standings). May require DB changes for persistence (e.g. leagues or recurring groups, match history, standings).

- **IRL tournaments (dashboard):** From the dashboard, connect to the Dart backend to create rooms, assign players, and send join notifications. Players only need to create an account and sign up for the tournament beforehand; the dashboard then shows the signed-up players, making it easier to run leaderboard and room create/join logic from the dashboard (e.g. create rooms per round, assign players to rooms, trigger join notifications so players open the app and join).
  - **Dashboard auth + room flow (no Flutter):** (1) Log in via the Python server (existing HTTP auth endpoints); get back a JWT (access token). (2) Connect to the Dart backend WebSocket (e.g. `ws://<host>:8080`). (3) Authenticate the WebSocket by sending `{"event": "authenticate", "token": "<that JWT>"}`; the Dart server validates that token with Python (`/service/auth/validate`). (4) Create the room over the same WebSocket with `{"event": "create_room", "permission": "public", "min_players": 2, "game_type": "classic", "auto_start": false}` (and any other options needed). So: **Python for login/JWT**, **Dart for WebSocket + room creation**. No Flutter involved in this dashboard flow.
  - **Dashboard room/game creation:** For dashboard-driven room creation (organizer creates rooms and assigns players), pass **`add_creator_to_room: false`** in the `create_room` payload so the dashboard user (organizer) is not added to the room; only the assigned players join. The organizer gets `create_room_success` with `room_id` and can then trigger join notifications for players.
  - **Dashboard UX:** (1) **Signed-up players:** Dashboard auto-loads signed-up players so the organizer can easily send join notifications. (2) **Create room:** A simple **Create** button triggers `create_room` (with `add_creator_to_room: false`); the response is shown in the dashboard (room data / `room_id`). (3) **Assign players:** Organizer assigns players to any of the available rooms shown in the dashboard; no extra backend logic—rooms are already created and listed; assignment + join notifications are handled in the dashboard (e.g. notify each player with their room_id so they open the app and join). (4) **Start match remotely:** The non-joined creator (dashboard) can start the match for a room by sending **`start_match`** with **`game_id`** (or **`room_id`**) set to the room id. The backend allows this only when the authenticated user is the room owner; the match then starts for the joined players.
  - **Python – add participants / add participant to match:** Implement in Python (dutch_game module): (1) **Add participants** – endpoint to add participants to a tournament (e.g. by tournament_id), storing user_id plus username and email when provided; updates the tournament’s `participants` (and optionally `user_ids`) in the DB. (2) **Add participant to match** – logic to add a participant to a specific match (e.g. tournament_id + match_index), storing user_id and optional username/email in that match’s `players` and `user_ids` so get-tournaments returns full user details.
  - **IRL sign-up workflow (organizer):** Ask participants for emails; create accounts manually (e.g. via admin/script) with the **default password**; add those users to the tournament (add-participants or DB script). Participants receive the **default password** (e.g. by email or in person) so they can log in to the app for the tournament.