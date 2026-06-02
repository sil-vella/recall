# Notification system documentation

| Document | Purpose |
|----------|---------|
| **[NOTIFICATION_SYSTEM_FLOW.md](./NOTIFICATION_SYSTEM_FLOW.md)** | Canonical end-to-end reference: how messages are created, stored, delivered to the Flutter app, and shown in UI. |
| Seed + sync | `playbooks/00_local/files/global_broadcast_messages.json` — local: `00_local/sync_global_broadcast_messages.yml`; VPS: `rop01/sync_global_broadcast_messages.yml` |
| Example payloads | [examples/](./examples/) — reference only; copy into seed JSON to deploy |
| [../00_FlowCharts/charts/end-to-end/notification_sys/notification-sys.mmd](../00_FlowCharts/charts/end-to-end/notification_sys/notification-sys.mmd) | High-level flowchart (may lag the markdown doc; prefer the flow doc for behaviour). |
| [../Dutch_game/NOTIFICATION_SYSTEM.md](../Dutch_game/NOTIFICATION_SYSTEM.md) | Short Dutch-focused overview; links here for full detail. |

## How do we push notifications to users?

**Today:** notifications are **in-app** (Mongo inbox + modals). There is **no** FCM/APNs / OS notification-tray integration in this repo.

| Goal | Mechanism |
|------|-----------|
| Stored message for a user (list + optional popup) | Python `NotificationService.create()` → Mongo `notifications` → optional `inbox_changed` WebSocket if the user is connected to the Dart game server |
| Popup while user is in a game session (may not be stored) | Dart `WebSocketServer.sendInstantNotification(sessionId, …)` → Flutter `instant_ws` modal |
| Rank-wide announcement (one doc, many users) | Admin `POST …/admin/global-broadcast` → delivered on `GET /userauth/dutch/get-user-stats` as `global_broadcast_messages` |
| Local-only UI (no backend) | `InstantMessageModal.showFrontendOnlyInstant` |

**Not implemented:** device push when the app is closed or backgrounded. User docs may include `notifications.push`, but no Flutter code sends or receives FCM tokens yet.

See **[NOTIFICATION_SYSTEM_FLOW.md §0](./NOTIFICATION_SYSTEM_FLOW.md#0-how-notifications-reach-users)** for the full delivery matrix and step-by-step authoring guide.
