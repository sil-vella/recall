# Notifications inbox batched with user stats init

**Status**: Planned  
**Created**: 2026-05-12  
**Last Updated**: 2026-05-12

## Objective

- Load **notification messages from the server** using the **same round-trip as** the existing Dutch **user stats / cosmetics bootstrap** (`GET /userauth/dutch/get-user-stats`), so login / post-auth init performs **one** authenticated GET instead of a separate `GET /userauth/notifications/messages` for that moment.
- Preserve **categorization** already modeled on notifications (`type`, `subtype`, `source` from Python `notifications` collection and [`notification_routes.py`](python_base_04/core/modules/notification_module/notification_routes.py) list shape).
- **Defer FCM** entirely until this batching and UX are stable.

## Current behavior (baseline)

| Concern | Today |
|--------|--------|
| Stats + catalog bootstrap | [`DutchGameHelpers.getUserDutchGameData()`](flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart) → `GET /userauth/dutch/get-user-stats` (optional catalog/table tier revisions in query string). [`get_user_stats()`](python_base_04/core/modules/dutch_game/api_endpoints.py) returns `data`, `table_tiers_revision`, optional embedded `table_tiers` / `consumables_catalog`. |
| Post-auth trigger | [`DutchGameMain._fetchUserStats()`](flutter_base_05/lib/modules/dutch_game/dutch_game_main.dart) on hooks `auth_login_complete` and `auth_login_success`. |
| Notifications fetch | Separate [`NotificationsModule.fetchMessages()`](flutter_base_05/lib/modules/notifications_module/notifications_module.dart) → `GET /userauth/notifications/messages?...` — used from [`screen_base.dart`](flutter_base_05/lib/core/00_base/screen_base.dart) (throttled poll + `inbox_changed`) and [`NotificationsScreen`](flutter_base_05/lib/screens/notifications_screen/notifications_screen.dart) (full list). |
| Categories | Each row includes `type` (`instant` / `admin` / `advert`), `subtype`, `source`. [`InstantMessageModal`](flutter_base_05/lib/core/widgets/instant_message_modal.dart) filters on `type` for modals. |

## Target behavior

1. **Python**: Extend `get_user_stats` success payload (JWT path only) with an optional key, e.g. `notifications_inbox`, containing the **same list shape** as `list_messages` today (reuse query logic or call shared helper to avoid drift). Use sensible defaults: e.g. `limit=50`, `offset=0`, `unread_only=true` for init (product can tune). Respect the same user scoping as notification routes.
2. **Flutter**: In `getUserDutchGameData()` (or immediately after a successful parse in `fetchAndUpdateUserDutchGameData()`), if `notifications_inbox` is present and non-null, apply it to `StateManager` under the existing `notifications` module key (`messages`, `unreadCount`, `lastFetchedAt`) — preferably via a **single public method** on `NotificationsModule` (e.g. `applyInboxFromUserStatsEnvelope`) so `fetchMessages()` remains the source of truth for **standalone** refresh paths.
3. **Keep** `GET /userauth/notifications/messages` for: notifications screen “see all / read history”, manual refresh, and any path that needs different `unread_only` / pagination. Optionally skip the **immediate** duplicate fetch on first `screen_base` check if state was just hydrated from stats (minor optimization; avoid double network on cold start).
4. **Categories**: No schema change required if list items already carry `type` / `subtype` / `source`. **Verify** list UI (notifications screen) exposes or groups by category as product expects; add UI-only grouping only if missing.
5. **FCM**: Out of scope for this plan; see [mobile-push-notifications-implementation.md](Documentation/00_Active_plans/mobile-push-notifications-implementation.md) when re-enabled.

## Implementation steps (checklist)

- [ ] Python: shared “list notifications for user” helper used by `list_messages` route and `get_user_stats` (or inline with identical field mapping).
- [ ] Python: add `notifications_inbox` (or agreed name) to `get_user_stats` JSON; document in API notes if needed.
- [ ] Flutter: parse envelope in `DutchGameHelpers.getUserDutchGameData` / `fetchAndUpdateUserDutchGameData` path; call `NotificationsModule` to update state.
- [ ] Flutter: ensure `lastFetchedAt` is set so `screen_base` throttle does not immediately refetch unless `inbox_changed` clears it (existing pattern).
- [ ] QA: login → one `get-user-stats` response carries inbox → instant modals still appear; WS `inbox_changed` still triggers refresh; notifications screen still works with `fetchMessages(unreadOnly: false)`.

## Files likely to change

- [python_base_04/core/modules/dutch_game/api_endpoints.py](python_base_04/core/modules/dutch_game/api_endpoints.py) — `get_user_stats`
- [python_base_04/core/modules/notification_module/](python_base_04/core/modules/notification_module/) — optional shared list helper
- [flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart](flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart) — merge inbox from stats response
- [flutter_base_05/lib/modules/notifications_module/notifications_module.dart](flutter_base_05/lib/modules/notifications_module/notifications_module.dart) — `applyInboxFromUserStatsEnvelope` (or equivalent)
- [flutter_base_05/lib/screens/notifications_screen/notifications_screen.dart](flutter_base_05/lib/screens/notifications_screen/notifications_screen.dart) — verify category display only if gaps found

## Notes

- **Coupling**: Dutch stats endpoint will depend on notification module data. Acceptable for one fewer round-trip; if circular imports appear in Python, implement list logic in notification module and import a thin function from dutch `get_user_stats`.
- **Service route**: `get_user_stats_service` (Dart/server key) likely should **not** include inbox unless explicitly required.

## Current progress

- Plan only; no code changes yet.

## Next steps

1. Agree payload key name and init query params (`unread_only`, `limit`).
2. Implement Python helper + `get_user_stats` field.
3. Implement Flutter merge + `NotificationsModule` API.
