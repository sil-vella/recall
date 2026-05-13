# Global broadcast messages on user stats

**Status:** Implemented (see `Documentation/Notification_Sys/NOTIFICATION_SYSTEM_FLOW.md` §11).

## Summary

- **Personal inbox** remains `GET /userauth/notifications/messages` (Mongo `notifications`, `user_id`-scoped). No global rows are inserted there.
- **Rank-targeted announcements** live in Mongo `global_broadcast_messages`; per-user ack only in `global_broadcast_reads`.
- **`GET /userauth/dutch/get-user-stats`** includes a **`global_broadcast_messages`** array: client-shaped objects with `origin: "global"`, stable `global_id`, `user_read`, and the same general fields as list messages (`title`, `body`, `type`, `data`, `responses`, …). Client `id` is `glob_<MongoObjectId>` so it cannot collide with per-user message ids.
- **Mark read:** `POST /userauth/notifications/global-mark-read` with `{ "global_message_ids": ["glob_...", "..."] }` (batch capped at 50). Does **not** use `POST /userauth/notifications/mark-read` or `.../response` for globals in v1.
- **Admin create:** `POST /userauth/notifications/admin/global-broadcast` (JWT user must have `role == "admin"` on `users`).

Flutter merges unread global `instant` rows ahead of API messages in `BaseScreenState._mergeInstantModalInbox`; dismiss calls global mark-read; response buttons for globals only trigger client-side deeplink / navigation from `data` (no server response dispatch for globals in v1).

## Related doc

Full flow, fields, and file paths: [NOTIFICATION_SYSTEM_FLOW.md](../Notification_Sys/NOTIFICATION_SYSTEM_FLOW.md).
