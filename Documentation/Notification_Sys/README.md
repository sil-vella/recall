# Notification system documentation

## ⚠️ IMPORTANT — sync global broadcasts after every seed edit

Editing **`playbooks/00_local/files/global_broadcast_messages.json`** (or the rop01 copy) **does not update Mongo by itself**. The app reads campaigns from the **`global_broadcast_messages`** collection via **`get-init-data`**. Until you run the sync playbook, users still see **old** titles, bodies, `target_version`, and deeplinks — a common mistake is changing `target_version` in JSON while Mongo still has the previous value (e.g. modal keeps showing on `2.0.20` because Mongo still has `2.0.21`).

**After any change to the seed JSON, run sync from repo root:**

```bash
# Local Docker Mongo
ansible-playbook -i localhost, -c local playbooks/00_local/sync_global_broadcast_messages.yml

# Production VPS (after source .env.prod)
set -a && source .env.prod && set +a
ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/sync_global_broadcast_messages.yml -e vm_name=rop01
```

Full detail: [NOTIFICATION_SYSTEM_FLOW.md §11.1](./NOTIFICATION_SYSTEM_FLOW.md#111-delivery-and-shape) and [§11.2 sync](./NOTIFICATION_SYSTEM_FLOW.md#112-admin-create-json-body).

---

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
| Rank-wide announcement (one doc, many users) | Admin `POST …/admin/global-broadcast` or seed sync → Mongo `global_broadcast_messages` → Flutter via **`GET /userauth/dutch/get-init-data`** (`global_broadcast_messages`) |
| “Update available” until user upgrades | Same global row with `data.target_version` — modal is **version-gated** (read state ignored); see [§11.5](./NOTIFICATION_SYSTEM_FLOW.md#115-version-gated-app-update-vs-read-gated-welcome) |
| Welcome / one-time campaign | Global `instant` without `target_version` — **read-gated**; dismiss → `global-mark-read` |
| Local-only UI (no backend) | `InstantMessageModal.showFrontendOnlyInstant` |

**Not implemented:** device push when the app is closed or backgrounded. There is **no** notification `type` that ignores read for per-user inbox rows — only globals with `data.target_version` use version-only modal rules on the client.

See **[NOTIFICATION_SYSTEM_FLOW.md §0](./NOTIFICATION_SYSTEM_FLOW.md#0-how-notifications-reach-users)** for the full delivery matrix and step-by-step authoring guide.

### Globals not showing in dev?

1. Confirm Mongo has rows (`sync_global_broadcast_messages.yml` after editing seed JSON).
2. **`GET /userauth/dutch/get-init-data`** must return a non-empty `global_broadcast_messages` array (not only deprecated `get-user-stats` naming — same handler).
3. If the API returns `[]` but Mongo has docs, see [§11.6 troubleshooting](./NOTIFICATION_SYSTEM_FLOW.md#116-troubleshooting-empty-global_broadcast_messages).
4. Launch with dev logging (`playbooks/frontend/run_*_to_global_log.sh`) and `DUTCH_DEV_LOG=1` for `customlog` traces in `global_broadcast_service.py`, `api_endpoints.py`, and Flutter `InstantModalFilter`.
