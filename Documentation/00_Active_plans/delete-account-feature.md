# Delete Account Feature

**Status:** Completed

## Objective

Allow logged-in users to permanently delete their account from the Account screen, with verification (password for email/guest accounts + typed `DELETE` confirmation), full server-side data purge, and local session teardown.

## API

- **Endpoint:** `POST /userauth/users/delete-account`
- **Auth:** JWT (`/userauth/` prefix)
- **Body:**
  - `confirmation` (required): must be exactly `DELETE`
  - `password` (required for email/guest accounts; omitted for Google-only)
  - `refresh_token` (optional): revokes refresh token like logout

**Responses:**
- `200` — `{ "success": true, "message": "Account deleted" }`
- `400` — invalid confirmation or missing password
- `401` — wrong password
- `403` — computer player (`is_comp_player`)
- `404` — user not found

## Verification rules

| Account type | Password required | Confirmation |
|---|---|---|
| Email / guest | Yes | Type `DELETE` |
| Google-only (`auth_providers: ['google']`, empty password) | No | Type `DELETE` |
| Computer player | Blocked | — |

## Data purged (`_purge_user_data`)

MongoDB collections (per user id, string and/or ObjectId as stored):

- `users` (embedded modules: wallet, dutch_game, subscription, etc.)
- `notifications`
- `user_events`
- `user_audit_logs`
- `global_broadcast_reads`
- `admob_rewarded_claims`
- `play_coin_purchases`, `apple_coin_purchases`
- `play_subscriptions`, `apple_subscriptions`
- `credit_purchases`, `failed_payments`
- `dutch_match_win_outcomes`

Also:

- Profile avatar file on disk (best-effort, from `profile.picture` URL)
- Redis: login session marker, auth generation bump, `init_stats` cache

## Flutter

- **LoginModule:** `deleteAccount(confirmation:, password:, context:)`
- **Account screen:** logged-in "Delete account" outlined button + two-step dialogs; distinct from "Clear all user data from this device"

## Tests

- `python_base_04/tools/tests/test_delete_account.py` — helper and endpoint unit tests

## Out of scope (v1)

- Dart WebSocket game server in-memory rooms
- Admin self-delete block
- Google re-auth (confirmation phrase only for Google-only)
